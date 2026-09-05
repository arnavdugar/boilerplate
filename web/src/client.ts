import type { CreateClientConfig } from '@/client/client.gen'

export class APIError extends Error {
  readonly retryAfterMs?: number

  constructor(public readonly response: Response) {
    super(`Request failed with status ${response.status}.`)
    const retryAfter = response.headers.get('Retry-After')?.trim()
    if (retryAfter) {
      if (/^\d+$/.test(retryAfter)) this.retryAfterMs = Number(retryAfter) * 1000
      else if (/^[a-z]/i.test(retryAfter)) {
        const deadline = Date.parse(retryAfter)
        if (!Number.isNaN(deadline)) this.retryAfterMs = Math.max(0, deadline - Date.now())
      }
    }
  }

  get status() {
    return this.response.status
  }
}

export const fetchHTTP: typeof fetch = async (input, init) => {
  const response = await fetch(input, init)
  if (!response.ok) throw new APIError(response)
  return response
}

const maximumRetryDelayMs = 30_000

export const queryRetryOptions = {
  retry: (count: number, error: Error) => {
    if (count >= 2) return false
    if (!(error instanceof APIError)) return true
    if (error.retryAfterMs !== undefined && error.retryAfterMs > maximumRetryDelayMs) return false
    return error.status === 408 || error.status === 429 || error.status >= 500
  },
  retryDelay: (attempt: number, error: Error) =>
    Math.max(
      Math.min(1000 * 2 ** attempt, maximumRetryDelayMs),
      error instanceof APIError ? (error.retryAfterMs ?? 0) : 0,
    ),
}

export const createClientConfig: CreateClientConfig = (config) => ({
  ...config,
  baseUrl: window.location.origin,
  fetch: fetchHTTP,
})
