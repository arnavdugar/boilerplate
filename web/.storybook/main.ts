import type { StorybookConfig } from '@storybook/preact-vite'

export default {
  core: { disableTelemetry: true },
  framework: '@storybook/preact-vite',
  stories: ['../src/components/**/*.stories.@(ts|tsx)'],
} satisfies StorybookConfig
