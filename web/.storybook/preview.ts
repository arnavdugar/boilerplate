import type { Preview } from '@storybook/preact-vite'

import '@/styles.css'

export default {
  beforeEach: ({ globals }) => {
    const frame = window.frameElement as HTMLIFrameElement | null
    if (!frame) return

    // The story's media query follows the embedding iframe's color scheme.
    const previousScheme = frame.style.colorScheme
    const scheme = globals.colorScheme
    frame.style.colorScheme = scheme === 'dark' || scheme === 'light' ? scheme : 'light dark'
    return () => {
      frame.style.colorScheme = previousScheme
    }
  },
  globalTypes: {
    colorScheme: {
      toolbar: {
        dynamicTitle: false,
        items: [
          { title: 'System', value: 'system' },
          { title: 'Light', value: 'light' },
          { title: 'Dark', value: 'dark' },
        ],
        title: 'Color scheme',
      },
    },
  },
  initialGlobals: { colorScheme: 'system' },
} satisfies Preview
