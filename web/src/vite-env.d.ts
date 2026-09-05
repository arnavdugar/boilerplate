/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />

interface ImportMetaEnv {
  readonly VITE_ENVIRONMENT?: string
  readonly VITE_SENTRY_DSN?: string
}
