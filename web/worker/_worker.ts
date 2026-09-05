interface Env {
  API_BASE_URL: string
}

export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url)
    const upstream = new URL(env.API_BASE_URL)

    upstream.pathname = url.pathname
    upstream.search = url.search
    const upstreamRequest = new Request(upstream, request)
    upstreamRequest.headers.set('Host', upstream.host)
    upstreamRequest.headers.set('X-Forwarded-Host', url.host)
    upstreamRequest.headers.set('X-Forwarded-Proto', url.protocol.slice(0, -1))

    let upstreamResponse
    try {
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
