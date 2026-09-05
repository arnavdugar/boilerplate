interface Env {
  API_BASE_URL: string
  GOOGLE_SERVICE_ACCOUNT_KEY: string
}

interface CachedToken {
  audience: string
  credentials: string
  expiresAt: number
  token: string
}

let cachedToken: CachedToken | undefined

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
}

async function getIdentityToken(env: Env, signal: AbortSignal): Promise<string> {
  const audience = new URL(env.API_BASE_URL).origin
  const now = Math.floor(Date.now() / 1000)
  if (
    cachedToken?.audience === audience &&
    cachedToken.credentials === env.GOOGLE_SERVICE_ACCOUNT_KEY &&
    cachedToken.expiresAt > now + 60
  ) {
    return cachedToken.token
  }

  const credentials = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_KEY) as {
    client_email: string
    private_key: string
    private_key_id: string
  }
  const privateKey = Uint8Array.from(
    atob(credentials.private_key.replace(/-----[^-]+-----|\s/g, '')),
    (character) => character.charCodeAt(0),
  )
  const key = await crypto.subtle.importKey(
    'pkcs8',
    privateKey,
    { hash: 'SHA-256', name: 'RSASSA-PKCS1-v1_5' },
    false,
    ['sign'],
  )
  const encoder = new TextEncoder()
  const header = base64url(
    encoder.encode(JSON.stringify({ alg: 'RS256', kid: credentials.private_key_id, typ: 'JWT' })),
  )
  const claims = base64url(
    encoder.encode(
      JSON.stringify({
        aud: 'https://oauth2.googleapis.com/token',
        exp: now + 3600,
        iat: now,
        iss: credentials.client_email,
        target_audience: audience,
      }),
    ),
  )
  const unsigned = `${header}.${claims}`
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(unsigned))
  const response = await fetch('https://oauth2.googleapis.com/token', {
    body: new URLSearchParams({
      assertion: `${unsigned}.${base64url(new Uint8Array(signature))}`,
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    }),
    method: 'POST',
    redirect: 'error',
    signal: AbortSignal.any([signal, AbortSignal.timeout(5000)]),
  })
  if (!response.ok) {
    throw new Error('Google identity token exchange failed')
  }
  const { id_token: token } = (await response.json()) as { id_token?: string }
  if (typeof token !== 'string') {
    throw new Error('Google identity token is missing')
  }
  const payload = token.split('.')[1]
  if (!payload) {
    throw new Error('Google identity token is malformed')
  }
  const { aud, exp } = JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/'))) as {
    aud?: string
    exp?: number
  }
  if (aud !== audience || typeof exp !== 'number' || !Number.isFinite(exp) || exp <= now + 60) {
    throw new Error('Google identity token has invalid claims')
  }
  cachedToken = {
    audience,
    credentials: env.GOOGLE_SERVICE_ACCOUNT_KEY,
    expiresAt: Math.min(exp, now + 3600),
    token,
  }
  return token
}

export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url)
    if (url.pathname !== '/api' && !url.pathname.startsWith('/api/')) {
      return new Response('Not found', {
        headers: { 'Cache-Control': 'no-store' },
        status: 404,
      })
    }
    const upstream = new URL(env.API_BASE_URL)

    upstream.pathname = url.pathname
    upstream.search = url.search
    const upstreamRequest = new Request(upstream, request)
    upstreamRequest.headers.set('Host', upstream.host)
    upstreamRequest.headers.set('X-Forwarded-Host', url.host)
    upstreamRequest.headers.set('X-Forwarded-Proto', url.protocol.slice(0, -1))

    let upstreamResponse
    try {
      // Keep application Authorization headers separate from Cloud Run's IAM credentials.
      upstreamRequest.headers.set(
        'X-Serverless-Authorization',
        `Bearer ${await getIdentityToken(env, request.signal)}`,
      )
      upstreamResponse = await fetch(upstreamRequest, {
        redirect: 'manual',
        cache: 'no-store',
      })
    } catch {
      return new Response('API upstream is unavailable', {
        status: 502,
        headers: { 'Cache-Control': 'no-store' },
      })
    }

    const response = new Response(upstreamResponse.body, upstreamResponse)
    response.headers.set('Cache-Control', 'no-store')
    const location = response.headers.get('Location')
    if (location) {
      const redirect = new URL(location, upstream)
      if (redirect.origin === upstream.origin) {
        response.headers.set(
          'Location',
          `${url.origin}${redirect.pathname}${redirect.search}${redirect.hash}`,
        )
      }
    }
    return response
  },
}
