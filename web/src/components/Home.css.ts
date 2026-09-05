import { style } from '@vanilla-extract/css'
import { vars } from '../styles.css'

export const page = style({
  maxWidth: '48rem',
  margin: '0 auto',
  padding: `${vars.space.large} ${vars.space.medium}`,
})
