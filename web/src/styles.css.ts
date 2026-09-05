import { createGlobalTheme, globalStyle } from '@vanilla-extract/css'

export const vars = createGlobalTheme(':root', {
  color: {
    background: '#ffffff',
    text: '#1f2937',
    accent: '#2563eb',
  },
  font: {
    body: 'ui-sans-serif, system-ui, sans-serif',
  },
  space: {
    small: '0.5rem',
    medium: '1rem',
    large: '2rem',
  },
})

globalStyle(':root', {
  fontFamily: vars.font.body,
  color: vars.color.text,
  background: vars.color.background,
  fontSynthesis: 'none',
  lineHeight: 1.5,
})

globalStyle('body', { margin: 0 })
globalStyle('a', { color: vars.color.accent })
globalStyle(':focus-visible', {
  outline: `3px solid ${vars.color.accent}`,
  outlineOffset: '3px',
})
