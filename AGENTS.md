# Repository guidance

## Architecture

- `web/` is a Preact and Vite frontend styled with vanilla-extract.
- `api/` is a Go HTTP API.
- `schema/openapi.yaml` is the shared API contract.
- PostgreSQL is the database. The local Compose service is named `postgres`.
- Object storage uses Cloudflare R2 in production and the local Compose service `s3mock` in
  development.
- Vite serves the local app on port 3000 and proxies `/api` requests to Go.
- Cloudflare Pages proxies production `/api` requests to Cloud Run.
- `Tiltfile` and `compose.yaml` define the local stack.

## General conventions

- Order items alphabetically when their order is otherwise unimportant (e.g., config entries,
  fields, imports, parameters, properties).
- Prefer inlining any function that is called only once at its sole call site instead of keeping it
  as a separate helper. Keep a one-call function when it forms a real abstraction boundary, such as
  an API client method, or when a TypeScript function enables `async`/`await`.
- Prefer focused changes and preserve unrelated work in the tree.
- Keep behavior as close to production as possible in every environment. Branch on `ENVIRONMENT`
  only when necessary, and document the reason.
- Use `log/slog` for Go logging, with appropriate levels and structured attributes for variable
  values and errors.
- Never commit credentials, personal data, or production secrets.
- Format Go struct literals with multiple fields using keyed fields and one field per line.
- Use a 100-character editor ruler as a guide. Split long lines at natural boundaries to improve
  readability; preserve literals and URLs when splitting would change their meaning.

## Documentation and writing

- Format Markdown with Prettier using `web/.prettierrc.json` and `--prose-wrap always`.
- Be concise. Use plain, direct language, short paragraphs, and present tense with active voice.
- Focus on repository-specific behavior and decisions. Do not explain well-established concepts or
  familiar tools unless needed to understand an exception or unusual use.
- Start instructions with an action and include necessary prerequisites. Write command examples to
  run from the repository root. Explicitly state when a command requires a different working
  directory.
- Use exact code identifiers in backticks and consistent domain terminology.
- Explain relevant defaults, constraints, ownership, and failure behavior. Distinguish implemented
  behavior from planned features.
- Ground factual claims in the code or verified sources. Do not fabricate information. State
  uncertainty when facts cannot be verified.
- Link to canonical files and existing instructions instead of duplicating explanations.
- Follow the surrounding document's structure.

## Web app

### Components and rendering

- Create web app components in `web/src/components` and hooks in `web/src/hooks`.
- Prefer function components and hooks.
- Import directly from `preact` and `preact/hooks`. Use `preact/compat` only when a React ecosystem
  dependency requires it.
- Use stable domain identifiers as list keys. Do not use array indexes as keys for data that can be
  reordered.
- Preserve loading, error, and empty states.

### Requests and effects

- Use the generated SDK and Preact Query options in `web/src/client` for API requests. Configure the
  shared fetch client in `web/src/client.ts` and put custom storage transfers in
  `web/src/storage.ts`; components must not call `fetch` directly.
- Keep rendering pure. Put subscriptions, requests, timers, and other external synchronization in
  effects with complete dependency lists and appropriate cleanup.
- Prefer `async`/`await` over Promise `.then(...)` chains.

### Styling

- For every component file named `<component>.tsx`, place its related styles in an adjacent
  `<component>.css.ts` file.
- Use vanilla-extract's `style()` for component-local styles. Component-adjacent `.css.ts` files
  must not call `globalStyle()`; global styles belong only in `web/src/styles.css.ts`.
- Define recurring colors, typography, spacing, radii, and breakpoints as shared vanilla-extract
  variables. Reuse existing tokens instead of duplicating literal values.
- Avoid `!important` and inline styles. Inline styles are acceptable only for values calculated at
  runtime.

### Accessibility

- Use semantic HTML and native controls before ARIA. Preserve keyboard navigation, visible focus
  states, and useful alternative text.
- Honor `prefers-reduced-motion` when adding animation.

## API

### Contract

- The API is contract-first. Change `schema/openapi.yaml` and run code generation (see Development
  and verification) before implementing the generated server interface in `api/server`.
- Declare application operations under `/api/v1/`; use a new major version for breaking changes.
  Keep health and profiling routes unversioned.
- Commit the generated `api/openapi/oas_*_gen.go` and `web/src/client` files. Do not edit them by
  hand.
- Do not expose sqlc-generated database structs as API response types. Map them to the
  OpenAPI-generated types at the HTTP boundary.
- Assign each operation one feature tag. Declare tags with short descriptions at the top level of
  `schema/openapi.yaml` and reuse existing tags.
- Define request constraints in OpenAPI. Set `additionalProperties: false` on fixed-shape request
  objects; explicitly define allowed values for dictionary-like inputs.

### Feature organization

- Group handlers, stores, and related business logic in lowercase feature packages under
  `api/server`, such as `health`. Split packages when ownership or reuse requires it, rather than
  creating app-wide packages for each layer.
- Name each feature's exported handler type `<Feature>Handler`, such as `health.HealthHandler`, and
  keep its constructor named `NewHandler`. Distinct type names let `api/server` embed multiple
  feature handlers without field-name collisions or aliases.
- Assemble concrete stores, clients, and handlers in `api/server` and inject dependencies
  explicitly. Keep the compile-time assertion that the combined handler implements `openapi.Handler`
  (and `openapi.RawHandler` when raw responses are declared).
- Use ogen-generated routing, decoding, validation, and response types. Configure shared HTTP
  policies in `api/server` with generated server options; see
  [API handlers](README.md#api-handlers). Keep feature-specific validation and response mapping in
  handlers, and keep sqlc calls and persistence transactions in separate store types.
- Extract logic shared across many API endpoints, such as authentication, into common middleware.
- Return unexpected failures as handler errors so the server logs and reports them once and sends a
  safe response. Send expected rejections and readiness failures as normal HTTP responses with no
  handler error.
- Name store implementation files `<domain>_store.go`, matching the store type's domain name.
- Define narrow dependency interfaces in the feature package that consumes them.
- Let simple handlers call stores directly. Introduce services when business workflows coordinate
  multiple dependencies or need reuse outside HTTP; keep those services independent of HTTP request
  and response types.
- Design store methods around persistence operations needed by the feature. Avoid generic repository
  interfaces and mechanical wrappers around every generated query.
- Use `github.com/arnavdugar/hsm` to generate state machines for values with defined state
  transitions, such as `status`.

### Naming across boundaries

- Name types, methods, and dependencies for their domain responsibility and role at the layer where
  they are used. Use consistent domain terms across layers, and distinguish handlers, services,
  stores, and clients where the role clarifies the name.
- Keep implementation details out of abstraction names. Include a database, protocol, or provider in
  a name only when that detail is part of the contract or distinguishes an implementation callers
  need to select.
- Keep method names focused on the operation callers request. Do not expose lower-level query names,
  table layouts, or transport mechanics through higher-level interfaces.

### Outbound HTTP

- Configure explicit timeouts and service-appropriate redirect policies. Keep request cancellation
  tied to the incoming context.
- Reuse clients and transports; do not mutate them while in use.
- In tests, inject clients with fake transports instead of modifying private handler fields.

## Database

### Schema and record ownership

- Treat `api/schema.sql` as the canonical current database schema and configure sqlc to read it.
- For application-created records, let Postgres generate primary keys and creation timestamps with
  schema defaults. Omit those columns from normal insert queries and return them from the insert. Do
  not generate persisted record IDs or creation timestamps in application code.
- Fixed seed or test fixtures may override defaults for reproducibility.
- Treat client-generated idempotency keys or externally assigned identifiers as separate fields, and
  document any other exception when the database cannot own a value.
- In every table that has them, declare `id` as the first column and `created_at` as the second
  column. Place foreign keys and domain-specific columns after them, and keep explicit `RETURNING`
  column order aligned with the table order.
- Keep development and test data in `api/seed.sql`, which runs outside the production API binary.

### Queries and transactions

- Use sqlc to manage database queries. Keep application queries in `api/queries`; do not embed
  runtime SQL in Go handlers or services.
- Name queries by intent and use the correct sqlc cardinality annotation, such as `:one`, `:many`,
  or `:exec`.
- Prefer explicit result columns over `SELECT *`.
- Use named parameters when positional parameters would generate unclear Go fields.
- Use generated `WithTx` queries inside transactions and keep transaction boundaries explicit.
- Give each atomic business operation one transaction owner. When it spans multiple stores, pass the
  same transaction through the participating persistence operations; do not let each store commit
  independently.
- Use `idempotency_requests` for retryable write operations that could create duplicate records or
  repeat a domain action; save the claim, domain writes, and replayable response in one transaction.

### Migrations

- Manage migrations out of band using root `atlas.hcl` and `migrations/`. Do not keep migration
  files under `api/` or apply schema changes from the API binary.
- After changing `api/schema.sql`, run `atlas migrate diff --env app`. Review the SQL, and commit
  the new migration and `migrations/atlas.sum` alongside the schema and generated code.
- Never rewrite applied migrations. After manually editing a new migration, run
  `atlas migrate hash --env app` before testing.

### Generated code

- Never edit sqlc-generated Go files manually. Regenerate and commit them after changing
  `api/schema.sql`, queries, or sqlc configuration.
- Keep the sqlc version aligned in `api/generate.go`, CI, and the commands in Development and
  verification.

## Object storage

- Reference stored files through `files`; do not duplicate blob storage metadata in domain tables.
- For references requiring a specific file kind, use a composite foreign key to `files (id, kind)`
  with a `NOT NULL` kind column whose `DEFAULT` and `CHECK` fix the required kind.
- Use direct browser-to-storage uploads and downloads with short-lived S3-compatible presigned URLs
  (Cloudflare R2 in production, S3Mock locally). Do not proxy file bytes through the API server.
- Keep authorization, object ownership checks, and metadata handling in the API. Authorize access
  before issuing a presigned URL scoped to the intended object and operation.
- Keep buckets private and storage credentials on the server. Configure bucket CORS for the web
  origins, methods, and headers required by direct transfers.
- Use the generated SDK for presigned URL requests and keep direct storage transfers in
  `web/src/storage.ts`, following the existing frontend request convention.

## API testing

### Test structure and assertions

- Keep tests focused on one behavior and structure them using arrange, act, and assert. Use
  descriptive test and subtest names, named fields in table-driven cases, and explicit expected
  results rather than deriving expectations through conditionals. Separate checks that can fail
  independently for unrelated reasons.
- Use ordinary Go tests rather than testify suites. Use testify `require` for prerequisites such as
  setup and decoding, and `assert` for independent checks. Call `require` only from the goroutine
  running the test.
- Use `httptest` for HTTP behavior and middleware.

### Mocks and interfaces

- Use `go.uber.org/mock/gomock` for business logic and dependency failure paths when interaction
  expectations help; small handwritten fakes are appropriate for simple dependencies.
- Do not add artificial interfaces or mock the whole database API just to enable mocking.
- Keep `mockgen` pinned through the Go `tool` directive and `go.uber.org/mock` requirement in
  `api/go.mod`. Use package-local `//go:generate go tool mockgen` directives and generate adjacent
  `*_mock_test.go` files in the consuming package.
- Regenerate mocks after changing mocked interfaces (see Development and verification). Commit
  generated mocks; never edit them manually.
- Create a fresh `gomock.NewController(t)` for each test or subtest and avoid expectations on
  incidental call order.

### Database integration tests

- Put database integration tests in `*_integration_test.go` files with `//go:build integration`
  followed by a blank line. Ordinary `go test ./...` runs unit tests without Postgres.
- Test sqlc queries, constraints, and transactions against a dedicated disposable Postgres database
  using the integration test runner in Development and verification.
- When the integration tag is enabled, missing `TEST_DATABASE_URL` must fail rather than skip.
  Isolate and clean up test data; mocks do not replace database integration tests.
- Keep the database path filter in `.github/workflows/api.yml` aligned with database code and test
  setup.

## Development and verification

When running a script in `./scripts/`, use the repository root as your working directory. Scripts
assume that working directory; do not add repository discovery or automatic directory-changing
boilerplate.

### Local development

Start the local stack from the repository root:

```sh
tilt up
```

### Code generation

After changing the OpenAPI contract, database schema, sqlc queries or configuration, or mocked
interfaces, regenerate code and include the generated changes:

```sh
./scripts/generate.sh
```

### API changes

```sh
(cd api && go test -race ./...)
```

### Web changes

```sh
(cd web && pnpm build)
(cd web && pnpm format:check)
```

`pnpm build` includes type checking. Use the pnpm version pinned in `web/package.json`, matching the
scripts and Tilt configuration.

### Database changes

After database changes, run code generation above, then validate sqlc:

```sh
(cd api && go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.29.0 vet)
(cd api && go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.29.0 diff)
```

After schema, migration, or query changes, also run database checks:

```sh
./scripts/test-db.sh -race
```

This runner checks migration checksums and consistency with `api/schema.sql`, applies migrations and
`api/seed.sql` in disposable Postgres, and runs API tests with the integration tag and
`TEST_DATABASE_URL` set. Run the API checks above as well.

### Infrastructure changes

Follow [the infrastructure guide](infra/README.md) for Terraform validation and deployment. See
[the README](README.md) for general setup.
