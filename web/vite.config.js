import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  base: process.env.VITE_BASE_PATH || '/',
  plugins: [
    preact(),
    vanillaExtractPlugin(),
    VitePWA({
      registerType: 'autoUpdate',
      pwaAssets: {
        image: 'public/favicon.svg',
        preset: 'minimal-2023',
      },
      manifest: {
        name: 'App starter',
        short_name: 'App starter',
        description: 'A starter for building a web app.',
        theme_color: '#2563eb',
        background_color: '#ffffff',
        display: 'standalone',
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        globIgnores: ['_worker.js'],
        navigateFallbackDenylist: [/^\/api(?:\/|$)/],
      },
    }),
  ],
  server: {
    host: '127.0.0.1',
    port: 3000,
    strictPort: true,
    cors: {
      origin: 'http://localhost:3001',
      credentials: true,
      methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Accept', 'Authorization', 'Content-Type', 'Idempotency-Key'],
    },
    proxy: {
      '^/api(?:/|$)': {
        target: 'http://127.0.0.1:8080',
        xfwd: true,
      },
    },
  },
})
