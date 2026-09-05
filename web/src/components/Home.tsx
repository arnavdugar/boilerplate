import { useQuery } from '@tanstack/preact-query'
import { getHelloOptions } from '../client/@tanstack/preact-query.gen'
import * as styles from './Home.css'

export function Home() {
  const hello = useQuery(getHelloOptions())

  return (
    <main class={styles.page}>
      <h1>App starter</h1>
      <p>Build your app with Preact, Go, and PostgreSQL.</p>
      {hello.isPending && <p role="status">Loading greeting…</p>}
      {hello.isError && <p role="alert">Could not load the greeting.</p>}
      {hello.isSuccess && <p role="status">{hello.data.content}</p>}
    </main>
  )
}
