# App starter

A minimal full-stack app with Preact, Vite, vanilla-extract, Wouter, a Go HTTP API, PostgreSQL, and
S3-compatible object storage. OpenAPI generates the shared Go and TypeScript contract; sqlc
generates database access, and Atlas manages versioned database migrations. The home page is a
starting point that displays a greeting from the API.

## Local development

When running a script in `./scripts/`, use the repository root as your working directory.

### Prerequisites

Install [Docker](https://www.docker.com/), [Tilt](https://tilt.dev/), [Go](https://go.dev/),
[Node.js](https://nodejs.org/) 22.12+, [pnpm](https://pnpm.io/) (use the version pinned in
`web/package.json`), and [Atlas](https://atlasgo.io/).

```sh
brew tap ariga/tap
brew install --cask docker-desktop
brew install tilt go node pnpm ariga/tap/atlas
```

Open Docker Desktop and wait for it to finish starting before running Tilt.

### Editor setup

Open the repository root in VS Code and install the workspace's recommended extensions. Shared
settings enable format-on-save and a 100-character ruler, with gofmt for Go, Terraform formatting,
and Prettier configured by [`web/.prettierrc.json`](web/.prettierrc.json).

Install web dependencies with `(cd web && pnpm install --frozen-lockfile)` before using Prettier in
the editor. [`.editorconfig`](.editorconfig) sets shared whitespace and indentation defaults for
supporting editors.

### Start the stack

Start the stack from the repository root:

```sh
tilt up
```

No external accounts or environment file are required for local development.

| Service                  | Local URL                                             |
| ------------------------ | ----------------------------------------------------- |
| Web app                  | [localhost:3000](http://localhost:3000)               |
| Scalar API documentation | [localhost:3001](http://localhost:3001)               |
| pgAdmin                  | [localhost:3002](http://localhost:3002)               |
| ChartDB viewer           | [localhost:3003](http://localhost:3003)               |
| API liveness             | [localhost:8080/health](http://localhost:8080/health) |
| API readiness            | [localhost:8080/ready](http://localhost:8080/ready)   |

Tilt runs the Go API and Vite locally. It installs web dependencies, lets Vite handle hot reload,
and rebuilds/restarts the API when its source changes. Tilt writes API binaries to `.tiltbuild/`. It
starts Postgres and applies committed Atlas migrations before starting the API. The `db-migrate`
resource reapplies pending migrations when `migrations/` changes. Tilt checks both local servers for
readiness; the API's readiness probe checks database connectivity.

Compose runs Postgres and S3Mock by default. Vite serves the app on loopback port 3000 and proxies
`/api` and `/api/*` to Go on port 8080. Configure the local server in
[`web/vite.config.js`](web/vite.config.js).

Scalar runs separately on port 3001 and sends API requests through Vite on port 3000. Vite allows
credentialed CORS from `http://localhost:3001`.

### Database access and fixtures

Postgres is published on loopback only at port 5432. The development database name, username, and
password are all `app`.

pgAdmin is published on loopback only and opens without a login or master password. Its
preconfigured `Local Postgres` server connects to `postgres:5432` using the development credentials.
pgAdmin settings persist in the `pgadmin_data` volume.

Run `./scripts/db-local.sh seed` to load development fixtures from `api/seed.sql`. The minimal
`users` table and `GetUser` query are examples for extending sqlc; there is no authentication or
account flow. The seed file is empty.

## Runtime configuration

### Error reporting

Sentry reports API request panics, startup failures, returned handler errors, and unhandled browser
errors. API Sentry events omit request bodies, cookies, headers, query parameters, and automatically
collected user information. The API sends events synchronously with a one-second timeout because
Cloud Run can suspend CPU between requests; delivery failures do not change the HTTP response.

Set `ENVIRONMENT` for the API: `local` disables Sentry; other values require a valid `SENTRY_DSN`.
The web app uses `VITE_ENVIRONMENT` (default: `local`) and `VITE_SENTRY_DSN` at build time, and
initializes Sentry only outside `local` when a DSN is present. [Terraform](infra/README.md#sentry)
supplies production configuration.

Browser tracing propagates `sentry-trace` and `baggage` through the Pages Worker to Go for
same-origin `/api` requests, correlating related errors by trace ID. Both SDKs sample 10% of new
traces, and the API honors the browser's sampling decision. Error reporting is unsampled. The
`service` tag distinguishes `web` and `api` events. Source-map uploads are not configured.

Generated OpenTelemetry instrumentation uses the global tracer and meter providers.

### Database connection and health

The API accepts `DATABASE_URL` or standard PostgreSQL environment variables (`PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE`). `PORT` defaults to 8080.

[`api/cmd/api/main.go`](api/cmd/api/main.go) pings Postgres and checks bucket access within a shared
five-second startup timeout. It exits if either check fails. Both the application and profiling
listeners bind before either starts serving; a bind failure closes listeners already opened.

The application server has a five-second read-header timeout, a ten-second write timeout, and a
60-second idle timeout. Both servers drain within a shared eight-second deadline on shutdown and
close on failure, leaving time for database cleanup before Cloud Run's shutdown deadline.

- `/health` returns `200` without accessing Postgres.
- `/ready` returns `200` when Postgres responds, or `503` on failure. Each readiness check has a
  one-second timeout and respects request cancellation.
- Both probes return empty bodies with `Cache-Control: no-store` and do not query object storage.

These endpoints sit outside the OpenAPI contract and require no session or idempotency key. Probes
call the API directly on port 8080 by default; the frontend proxy forwards only `/api` paths.
External requests to these endpoints on Cloud Run require Google IAM authentication.

### Profiling

Access Go profiling at `http://127.0.0.1:8080/debug/pprof/`:

```sh
go tool pprof 'http://127.0.0.1:8080/debug/pprof/profile?seconds=30'
```

### Object storage

The API requires `S3_BUCKET` and uses the standard AWS SDK configuration: `AWS_REGION`,
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_ENDPOINT_URL_S3` for an S3-compatible
endpoint. Startup sends a `HeadBucket` request and fails if the bucket is missing or inaccessible.
Health and readiness probes do not query object storage. Upload and download endpoints are not
implemented.

Tilt configures local development credentials and the `app` bucket on S3Mock at
`http://127.0.0.1:9090`. Compose creates the bucket and persists its contents in the gitignored
`s3mock-data/` directory at the repository root, bind-mounted into S3Mock so you can inspect the
files locally. Production Terraform configures a private Cloudflare R2 bucket with region `auto` and
credentials supplied through Secret Manager.

### Frontend and API routing

The frontend uses relative `/api/v1/...` URLs. Vite in development and a Cloudflare Pages Worker in
production proxy these requests to Go under the page's origin. `VITE_BASE_PATH` sets the frontend's
base path and defaults to `/`; API paths remain rooted at `/api`.

The production proxy preserves cookies, request bodies, and status codes, disables API caching, and
rewrites redirects targeting the API origin to the app origin. The Worker authenticates upstream
requests with Google ID tokens; Cloud Run rejects unauthenticated direct calls. Terraform supplies
the Worker's runtime bindings; see the
[infrastructure guide](infra/README.md#service-configuration).

## Extend the app

- Add operations and schemas to `schema/openapi.yaml`, regenerate the contract, and implement
  [API handlers](#api-handlers) in `api/server`.
- Add tables to `api/schema.sql` and queries to `api/queries`. Schema changes also need a
  [versioned migration](#database-migrations).
- Add Preact components and adjacent vanilla-extract styles in `web/src/components` and hooks in
  `web/src/hooks`. Use the generated SDK and Preact Query options for API requests.

### API handlers

Declare operations, request constraints, response bodies, headers, and security requirements in
[`schema/openapi.yaml`](schema/openapi.yaml). Follow the
[code generation instructions](#code-generation) before implementing handlers.

Implement the generated `openapi.Handler` interface in feature handlers and assemble them in
[`server.NewHandler`](api/server/server.go). Use generated response types for expected outcomes.
Implement the generated `openapi.SecurityHandler` interface when adding protected operations. Ogen
performs routing, security checks, decoding, validation, default application, and response encoding.
Keep business rules and persistence in feature handlers and stores.

The temporary `GET /api/v1/hello` operation returns `{ "content": "Hello world!" }` and keeps the
scaffold's generated server usable. The home page uses it as a Preact Query example. Remove both
examples when implementing the real API.

#### Routing and request limits

Use ogen's default routing behavior for unmatched paths, unsupported methods, and `OPTIONS`
requests. Declare `HEAD` operations in the contract when needed; do not rewrite them to `GET`.
Health probes mount separately from generated API operations.

[`server.NewHandler`](api/server/server.go) limits `/api/` request bodies to 16 KiB before passing
them to ogen. Upload file bytes directly to object storage.

#### Error handling

Return expected rejections as generated response types with no handler error. Return unexpected
failures as errors so the shared `WithErrorHandler` hook logs and reports them once and sends a safe
response. The hook preserves ogen's non-500 error status codes while hiding error details. If a
response write fails after headers or body bytes are sent, it reports the error without appending
another response.

#### Raw responses

Reserve `x-ogen-raw-response: true` for idempotent mutations that replay stored JSON bytes. Use
[`httpresponse.JSON`](api/server/httpresponse/json.go) to preserve those bytes. Keep
feature-specific response mapping in each feature; raw responses still use generated request
validation.

### Code generation

After changing the contract, database schema, queries, sqlc configuration, or mocked interfaces, run
from the repository root:

```sh
./scripts/generate.sh
```

This requires Go and pnpm (the version is pinned in `web/package.json`). Install web dependencies
first with `(cd web && pnpm install --frozen-lockfile)`. Commit the generated API contract files
(`api/openapi/oas_*_gen.go` and `web/src/client`), sqlc files in `api/database`, and package-local
mocks as applicable. The Go server uses ogen, configured in `api/ogen.yaml`; the frontend uses Hey
API, configured in `web/openapi-ts.config.ts`, to generate TypeScript types, a fetch client, SDK
functions, and Preact Query options. `web/src/client.ts` configures the shared client to use the
page's origin, and `web/src/main.tsx` provides the Query client. Never edit generated files by hand.

## Database migrations

### Schema and migration history

Keep `api/schema.sql` as the canonical current schema; sqlc reads it directly. After changing the
schema, generate a versioned migration from the repository root:

```sh
atlas migrate diff --env app
./scripts/generate.sh
```

Atlas replays the committed history in a disposable Postgres 18 container and compares it with
`api/schema.sql`. Review the generated SQL and run the [database checks](#database-checks), then
commit the schema, generated code, new `migrations/*.sql`, and `migrations/atlas.sum` together. Do
not rewrite migrations that have been applied; add a new migration instead. After manually editing a
new migration, run `atlas migrate hash --env app` before testing.

The API workflow pins Atlas to `v1.3.0`; update both setup steps together when upgrading. The
migration commands used here do not require an Atlas Cloud account. Database migrations and seed
data run outside the API process.

### Local database commands

Start `tilt up` from the repository root and wait for Postgres to be ready before running local
database commands. Tilt applies pending migrations automatically; to apply them manually, run
`./scripts/db-local.sh migrate` from the repository root. To recreate the local database and load
seed data, run `./scripts/db-local.sh reset`; this deletes all data in the selected local Compose
project's `app` database. These local commands use the Compose Postgres service and ignore an
inherited `DATABASE_URL`.

Atlas keeps revision metadata in a separate `atlas_schema_revisions` schema. Existing databases
created outside Atlas require manual adoption before migrations can be applied. For a disposable
development database, use the reset command above.

### Other databases and production

For other databases, supply `DATABASE_URL` and run `atlas migrate apply --env app` from the
repository root. Production migrations run in the API deployment workflow before the new image is
released; see [the infrastructure guide](infra/README.md). Keep changes compatible with the running
API: add new structures first, deploy code that uses them, and remove old structures in a later
release. Seed data is for development and tests only.

## API testing conventions

Follow the [API testing conventions](AGENTS.md#api-testing) for assertions, mocks, and database
integration tests. See [`health_test.go`](api/server/health/health_test.go) for readiness tests
covering database success, failure, timeout, and request cancellation, and
[`health.go`](api/server/health/health.go) for its mock generation directive.

To upgrade gomock, replace `<version>` with the desired version and run from the repository root:

```sh
(cd api && go get -tool go.uber.org/mock/mockgen@<version>)
./scripts/generate.sh
```

Run the [API checks](#api-and-web-checks) and commit the generated mocks.

## Verification

### API and web checks

Run from the repository root:

```sh
(cd api && go test -race ./...)
(cd web && pnpm build)
(cd web && pnpm format:check)
```

`pnpm build` type-checks the frontend and Worker, builds the frontend, then compiles
[`web/worker/_worker.ts`](web/worker/_worker.ts) to `web/dist/_worker.js` for Cloudflare Pages. For
type checking alone, use `(cd web && pnpm typecheck)`. The frontend formatting command checks files
under `web/`.

### Database checks

After database changes, regenerate code and run from the repository root:

```sh
(cd api && go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 vet)
(cd api && go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 diff)
./scripts/test-db.sh -race
```

Keep the sqlc version aligned in these commands, `api/generate.go`, `.github/workflows/api.yaml`,
and `AGENTS.md`.

The database runner validates migration checksums and schema consistency, starts disposable
Postgres, applies migrations and `api/seed.sql`, and runs API tests with the `integration` tag and
`TEST_DATABASE_URL` set. It removes the container on exit. There are currently no database
integration tests. When adding them, follow the
[integration test requirements](AGENTS.md#database-integration-tests), including failing when
`TEST_DATABASE_URL` is missing.

### Continuous integration

GitHub Actions validates the API, generated code, frontend, and Terraform when changes match each
workflow's path filters.

The API workflow always checks generated code, vets sqlc queries, checks sqlc consistency, and runs
unit tests. Atlas installation and Postgres checks run only for changes to migrations, queries,
schema, seeds, database code, integration tests, Go dependencies, sqlc configuration/generation, or
the validation scripts/workflow. The exact paths are in `.github/workflows/api.yaml`; update them
when moving database code or test setup. HTTP-only changes skip Postgres. Manually running the API
workflow runs all checks.

See [database checks](#database-checks) for the runner's behavior and current test coverage.
Production checks for pending migrations before every API deployment.

## Production deployment

Optional production infrastructure provisions Aiven PostgreSQL, Cloud Run, Cloudflare Pages, private
R2 storage, and GitHub deployment configuration. Deployment jobs are disabled until the repository
Actions variable `DEPLOY_ENABLED` is set to `true`; validation runs without it. See
[the infrastructure guide](infra/README.md) for configuration, provisioning, and deployment.
