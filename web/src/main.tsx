import * as Sentry from '@sentry/browser'
import { QueryClient, QueryClientProvider } from '@tanstack/preact-query'
import { render } from 'preact'
import { registerSW } from 'virtual:pwa-register'
import { Link, Route, Router, Switch } from 'wouter-preact'
import { Home } from './components/Home'
import './styles.css'

const environment = import.meta.env.VITE_ENVIRONMENT || 'local'

// Keep local development errors out of Sentry, including local production builds.
if (environment !== 'local' && import.meta.env.VITE_SENTRY_DSN) {
  Sentry.init({
    dsn: import.meta.env.VITE_SENTRY_DSN,
    environment,
    initialScope: { tags: { service: 'web' } },
    integrations: [Sentry.browserTracingIntegration()],
    sendDefaultPii: false,
    tracePropagationTargets: [/^\/api(?:\/|$)/],
    tracesSampleRate: 0.1,
  })
}

registerSW()

const queryClient = new QueryClient()

render(
  <QueryClientProvider client={queryClient}>
    <Router base={import.meta.env.BASE_URL.replace(/\/$/, '')}>
      <Switch>
        <Route path="/" component={Home} />
        <Route>
          <main>
            <h1>Page not found</h1>
            <Link href="/">Go home</Link>
          </main>
        </Route>
      </Switch>
    </Router>
  </QueryClientProvider>,
  document.getElementById('app')!,
)
