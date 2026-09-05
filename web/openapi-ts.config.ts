import { defineConfig } from '@hey-api/openapi-ts'

export default defineConfig({
  input: '../schema/openapi.yaml',
  output: 'src/client',
  plugins: [
    '@hey-api/typescript',
    {
      name: '@hey-api/client-fetch',
      runtimeConfigPath: './src/client.ts',
    },
    '@hey-api/sdk',
    '@tanstack/preact-query',
  ],
})
