import assert from 'node:assert/strict'
import { QueryClient } from '@tanstack/preact-query'
import { afterEach, test, vi } from 'vitest'

import { APIError, fetchHTTP, queryRetryOptions } from '@/client'

afterEach(() => vi.useRealTimers())

function httpError(status: number, retryAfter?: string) {
  const headers = new Headers()
  if (retryAfter !== undefined) headers.set('Retry-After', retryAfter)
  return new APIError(new Response(null, { headers, status }))
}

for (const { error, name, retries } of [
  { error: httpError(400), name: 'invalid input', retries: false },
  { error: httpError(401), name: 'expired session', retries: false },
  { error: httpError(403), name: 'forbidden resource', retries: false },
  { error: httpError(404), name: 'missing resource', retries: false },
  { error: httpError(408), name: 'request timeout', retries: true },
  { error: httpError(409), name: 'conflicting write', retries: false },
  { error: httpError(429), name: 'rate limit', retries: true },
  { error: httpError(500), name: 'server failure', retries: true },
  { error: httpError(503), name: 'unavailable server', retries: true },
  { error: new TypeError('Failed to fetch'), name: 'network failure', retries: true },
]) {
  test(`${name} applies the query retry limit`, () => {
    assert.equal(queryRetryOptions.retry(0, error), retries)
    assert.equal(queryRetryOptions.retry(1, error), retries)
    assert.equal(queryRetryOptions.retry(2, error), false)
  })
}

for (const { expected, header, name } of [
  { expected: undefined, header: undefined, name: 'absent header' },
  { expected: undefined, header: 'invalid', name: 'malformed date' },
  { expected: undefined, header: '-1', name: 'negative seconds' },
  { expected: undefined, header: '1.5', name: 'fractional seconds' },
  { expected: 5000, header: '5', name: 'delay seconds' },
  { expected: 0, header: '0', name: 'zero seconds' },
  { expected: 10_000, header: 'Fri, 30 Oct 2026 15:00:10 GMT', name: 'future HTTP date' },
  { expected: 0, header: 'Fri, 30 Oct 2026 14:59:00 GMT', name: 'past HTTP date' },
]) {
  test(`API errors preserve Retry-After from ${name}`, () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-10-30T15:00:00Z'))

    const error = httpError(429, header)

    assert.equal(error.retryAfterMs, expected)
  })
}

test('HTTP failures throw an API error with the response', async () => {
  const response = new Response(null, { status: 429 })
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(response)

  await assert.rejects(fetchHTTP(new Request('https://app.example.test/api/resource')), (error) => {
    assert.ok(error instanceof APIError)
    assert.equal(error.response, response)
    return true
  })
})

test('queries back off exponentially when Retry-After is unavailable', () => {
  const error = httpError(408)

  assert.equal(queryRetryOptions.retryDelay(0, error), 1000)
  assert.equal(queryRetryOptions.retryDelay(1, error), 2000)
  assert.equal(queryRetryOptions.retryDelay(10, error), 30_000)
})

test('Retry-After never shortens the exponential backoff', () => {
  const error = httpError(429, '0')

  assert.equal(queryRetryOptions.retryDelay(1, error), 2000)
})

for (const status of [408, 429, 503]) {
  test(`${status} stops automatic retries when Retry-After exceeds the wait limit`, () => {
    const error = httpError(status, '31')

    assert.equal(queryRetryOptions.retry(0, error), false)
  })
}

test('a query waits for Retry-After before making its next request', async () => {
  vi.useFakeTimers()
  const cache = new QueryClient({
    defaultOptions: { queries: { ...queryRetryOptions, gcTime: Infinity } },
  })
  const request = vi.fn().mockRejectedValueOnce(httpError(429, '3')).mockResolvedValue('loaded')
  try {
    const result = cache.fetchQuery({ queryFn: request, queryKey: ['retry-after'] })
    await vi.advanceTimersByTimeAsync(2999)
    assert.equal(request.mock.calls.length, 1)

    await vi.advanceTimersByTimeAsync(1)

    assert.equal(await result, 'loaded')
    assert.equal(request.mock.calls.length, 2)
  } finally {
    cache.clear()
  }
})
