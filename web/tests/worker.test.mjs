import assert from 'node:assert/strict'
import { afterEach, before, beforeEach, test } from 'node:test'

let env
let keys
let worker
let moduleID = 0
const originalFetch = globalThis.fetch
const originalNow = Date.now
const now = 1_800_000_000

function identityToken(audience = 'https://api.run.app', expiresAt = now + 3600) {
  const payload = Buffer.from(JSON.stringify({ aud: audience, exp: expiresAt })).toString(
    'base64url',
  )
  return `header.${payload}.signature`
}

before(async () => {
  keys = await crypto.subtle.generateKey(
    {
      hash: 'SHA-256',
      modulusLength: 2048,
      name: 'RSASSA-PKCS1-v1_5',
      publicExponent: new Uint8Array([1, 0, 1]),
    },
    true,
    ['sign', 'verify'],
  )
  const privateKey = Buffer.from(await crypto.subtle.exportKey('pkcs8', keys.privateKey))
  env = {
    API_BASE_URL: 'https://api.run.app',
    GOOGLE_SERVICE_ACCOUNT_KEY: JSON.stringify({
      client_email: 'pages@example.iam.gserviceaccount.com',
      private_key: `-----BEGIN PRIVATE KEY-----\n${privateKey.toString('base64')}\n-----END PRIVATE KEY-----`,
      private_key_id: 'test-key',
    }),
  }
})

beforeEach(async () => {
  Date.now = () => now * 1000
  worker = (await import(`../dist/_worker.js?test=${moduleID++}`)).default
})

afterEach(() => {
  globalThis.fetch = originalFetch
  Date.now = originalNow
})

test('exchanges a signed assertion scoped to the Cloud Run audience', async () => {
  let exchange
  globalThis.fetch = async (input, options) => {
    if (typeof input === 'string') {
      exchange = { input, options }
      return Response.json({ id_token: identityToken() })
    }
    return new Response('ok')
  }

  const response = await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)

  assert.equal(response.status, 200)
  assert.equal(exchange.input, 'https://oauth2.googleapis.com/token')
  assert.equal(exchange.options.method, 'POST')
  assert.equal(exchange.options.redirect, 'error')
  assert.equal(
    exchange.options.body.get('grant_type'),
    'urn:ietf:params:oauth:grant-type:jwt-bearer',
  )
  const assertion = exchange.options.body.get('assertion')
  const [header, claims, signature] = assertion.split('.')
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), {
    alg: 'RS256',
    kid: 'test-key',
    typ: 'JWT',
  })
  assert.deepEqual(JSON.parse(Buffer.from(claims, 'base64url')), {
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
    iss: 'pages@example.iam.gserviceaccount.com',
    target_audience: 'https://api.run.app',
  })
  assert.equal(
    await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      keys.publicKey,
      Buffer.from(signature, 'base64url'),
      new TextEncoder().encode(`${header}.${claims}`),
    ),
    true,
  )
})

test('overwrites browser IAM credentials while preserving application credentials and body', async () => {
  let upstream
  globalThis.fetch = async (input) => {
    if (typeof input === 'string') return Response.json({ id_token: identityToken() })
    upstream = input
    return new Response('created', { status: 201 })
  }
  const request = new Request('https://app.pages.dev/api/v1/items?filter=active', {
    body: 'request body',
    headers: {
      Authorization: 'Bearer application-token',
      Cookie: 'session=example',
      'X-Serverless-Authorization': 'Bearer browser-token',
    },
    method: 'POST',
  })

  const response = await worker.fetch(request, env)

  assert.equal(upstream.url, 'https://api.run.app/api/v1/items?filter=active')
  assert.equal(upstream.headers.get('X-Serverless-Authorization'), `Bearer ${identityToken()}`)
  assert.equal(upstream.headers.get('Authorization'), 'Bearer application-token')
  assert.equal(upstream.headers.get('Cookie'), 'session=example')
  assert.equal(await upstream.text(), 'request body')
  assert.equal(response.status, 201)
  assert.equal(response.headers.get('Cache-Control'), 'no-store')
})

test('reuses a valid identity token', async () => {
  let exchanges = 0
  globalThis.fetch = async (input) => {
    if (typeof input === 'string') {
      exchanges++
      return Response.json({ id_token: identityToken() })
    }
    return new Response('ok')
  }

  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)
  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)

  assert.equal(exchanges, 1)
})

test('refreshes a token one minute before expiry', async () => {
  let exchanges = 0
  globalThis.fetch = async (input) => {
    if (typeof input === 'string') {
      exchanges++
      return Response.json({
        id_token: identityToken('https://api.run.app', Date.now() / 1000 + 3600),
      })
    }
    return new Response('ok')
  }

  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)
  Date.now = () => (now + 3540) * 1000
  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)

  assert.equal(exchanges, 2)
})

test('does not reuse a token for another audience', async () => {
  const audiences = []
  globalThis.fetch = async (input, options) => {
    if (typeof input === 'string') {
      const claims = options.body.get('assertion').split('.')[1]
      const audience = JSON.parse(Buffer.from(claims, 'base64url')).target_audience
      audiences.push(audience)
      return Response.json({ id_token: identityToken(audience) })
    }
    return new Response('ok')
  }

  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)
  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), {
    ...env,
    API_BASE_URL: 'https://other.run.app',
  })

  assert.deepEqual(audiences, ['https://api.run.app', 'https://other.run.app'])
})

test('refreshes the token when the credential binding changes', async () => {
  let exchanges = 0
  globalThis.fetch = async (input) => {
    if (typeof input === 'string') {
      exchanges++
      return Response.json({ id_token: identityToken() })
    }
    return new Response('ok')
  }
  const rotatedCredentials = {
    ...JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_KEY),
    private_key_id: 'rotated-test-key',
  }

  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)
  await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), {
    ...env,
    GOOGLE_SERVICE_ACCOUNT_KEY: JSON.stringify(rotatedCredentials),
  })

  assert.equal(exchanges, 2)
})

test('fails closed when the credential binding is missing', async () => {
  let calls = 0
  globalThis.fetch = async () => {
    calls++
    return new Response('unexpected')
  }

  const response = await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), {
    API_BASE_URL: env.API_BASE_URL,
  })

  assert.equal(calls, 0)
  assert.equal(response.status, 502)
  assert.equal(await response.text(), 'API upstream is unavailable')
})

for (const path of ['/api/../debug/pprof/', '/apiary', '/debug/pprof/', '/health']) {
  test(`rejects ${path} without requesting credentials or contacting Cloud Run`, async () => {
    let calls = 0
    globalThis.fetch = async () => {
      calls++
      return new Response('unexpected')
    }

    const response = await worker.fetch(new Request(`https://app.pages.dev${path}`), env)

    assert.equal(calls, 0)
    assert.equal(response.status, 404)
    assert.equal(response.headers.get('Cache-Control'), 'no-store')
  })
}

test('retries token issuance after an exchange failure without calling the API unauthenticated', async () => {
  let exchanges = 0
  let upstreamCalls = 0
  globalThis.fetch = async (input) => {
    if (typeof input === 'string') {
      exchanges++
      if (exchanges === 1) return new Response('sensitive error', { status: 400 })
      return Response.json({ id_token: identityToken() })
    }
    upstreamCalls++
    return new Response('ok')
  }

  const failed = await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)
  const retried = await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)

  assert.equal(failed.status, 502)
  assert.equal(await failed.text(), 'API upstream is unavailable')
  assert.equal(exchanges, 2)
  assert.equal(upstreamCalls, 1)
  assert.equal(retried.status, 200)
})

for (const { name, token } of [
  { name: 'missing', token: undefined },
  { name: 'malformed', token: 'invalid' },
  { name: 'expired', token: identityToken('https://api.run.app', now) },
  { name: 'wrong audience', token: identityToken('https://other.run.app') },
]) {
  test(`rejects identity tokens that are ${name} without calling the API`, async () => {
    let upstreamCalls = 0
    globalThis.fetch = async (input) => {
      if (typeof input === 'string') return Response.json({ id_token: token })
      upstreamCalls++
      return new Response('unexpected')
    }

    const response = await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)

    assert.equal(upstreamCalls, 0)
    assert.equal(response.status, 502)
  })
}

test('rewrites API redirects without following them with IAM credentials', async () => {
  let upstreamOptions
  globalThis.fetch = async (input, options) => {
    if (typeof input === 'string') return Response.json({ id_token: identityToken() })
    upstreamOptions = options
    return new Response(null, {
      headers: { Location: 'https://api.run.app/api/v1/login?next=home' },
      status: 302,
    })
  }

  const response = await worker.fetch(new Request('https://app.pages.dev/api/v1/hello'), env)

  assert.equal(upstreamOptions.redirect, 'manual')
  assert.equal(response.status, 302)
  assert.equal(response.headers.get('Location'), 'https://app.pages.dev/api/v1/login?next=home')
  assert.equal(response.headers.get('X-Serverless-Authorization'), null)
})
