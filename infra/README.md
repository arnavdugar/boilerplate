# Production infrastructure

Terraform provisions a configurable application platform:

- An Aiven PostgreSQL 18 service with termination protection, and an application database.
- Google Artifact Registry, Secret Manager, a Cloud Run API, and its runtime service account.
- A private Cloudflare R2 bucket with bucket-scoped API credentials in Secret Manager.
- Cloudflare Pages and its deployment token, stored as a GitHub Actions secret.
- A Sentry application team and project, with separate API and web client keys.
- GitHub-to-Google Workload Identity Federation restricted to the configured repository's `main`
  branch, plus repository Actions variables for deployment.

## Configure and provision

Run the command examples below from the repository root. Terraform commands use `-chdir=infra` to
select the configuration directory.

### Prerequisites

Use Terraform 1.11 or newer, below 2.0, and install the Google Cloud CLI for the `gcloud`
authentication command. Before provisioning, create or select:

- A billed Google Cloud project and an existing versioned GCS bucket for Terraform state.
- An Aiven project and an API token with permission to create its PostgreSQL service.
- An R2-enabled Cloudflare account and a provisioning token with Pages Write, Workers R2 Storage
  Write, Account API Tokens Read, and Account API Tokens Write permissions.
- A GitHub repository and a token with access to manage its Actions variables and secrets.
- A Sentry organization and an authentication token that can manage teams, projects, and client
  keys.

### Deployment settings

Account IDs, project names, repository names, and resource names are inputs. Edit these tracked
configuration files before provisioning:

- [`terraform.tfvars`](terraform.tfvars): set the application `name`, Google project, Aiven project,
  Cloudflare account ID, Pages project, GitHub owner, repository, and Sentry organization slug. Set
  the Google and Aiven regions, Aiven plan, and R2 location hint for your deployment. `name` names
  the PostgreSQL service, application database, and R2 bucket. It also prefixes other service,
  identity, token, and secret names.
- [`backend.tf`](backend.tf): set `bucket` to your existing GCS state bucket and `prefix` to the
  state path for this app and environment. The bucket must exist before initialization.

The configuration files contain non-secret deployment settings. Keep provider credentials in the
environment.

This configuration is intended for a new app. To adopt existing resources, import them into the
selected state and review resource addresses and names before applying.

### Credentials and Terraform apply

Supply provider credentials through the environment and Google Application Default Credentials:

```sh
export AIVEN_TOKEN="..."
export CLOUDFLARE_API_TOKEN="..."
export GITHUB_TOKEN="..."
export SENTRY_AUTH_TOKEN="..."
gcloud auth application-default login
terraform -chdir=infra init
terraform -chdir=infra plan -out=app.tfplan
```

Review the plan, then apply it:

```sh
terraform -chdir=infra apply app.tfplan
```

Terraform state and plan files contain database credentials, the R2 and Pages API tokens, and Sentry
client keys. Restrict access to the state bucket. Terraform creates a new Secret Manager version
when an apply observes changed database or R2 credentials.

## Bootstrap and database migrations

### Placeholder API

The first Terraform apply creates Cloud Run with Google's public
[Cloud Run hello image](https://github.com/GoogleCloudPlatform/cloud-run-hello), pinned by digest in
`cloud-run.tf`. Its catch-all HTTP handler returns `200` on `/health` and `/ready` and honors
`PORT`, so Terraform can configure all three application probes immediately. These checks report the
placeholder's health until the real API is deployed; they do not check Postgres or R2 during
bootstrap.

### Initialize the database

The API workflow initializes a new database by applying the committed Atlas migrations before
deploying the first API image. For a manual migration, install Atlas (`brew tap ariga/tap`, then
`brew install ariga/tap/atlas` on macOS) and run:

```sh
export DATABASE_URL="$(terraform -chdir=infra output -raw database_url)"
atlas migrate apply --env app
unset DATABASE_URL
```

Do not apply `api/schema.sql` directly or run development seed data in production. Existing
databases created outside Atlas require manual adoption before enabling deployment; this starter
does not provide an adoption script. See the [root README](../README.md#database-migrations) for the
schema and migration workflow.

## Deployment

### Enable deployment jobs

Deployment jobs are disabled until the repository Actions variable `DEPLOY_ENABLED` is set to
`true`. Validation still runs when the variable is unset or set to `false`, including for manually
dispatched API and Web workflows.

After provisioning (and adopting an existing database, if applicable), open the GitHub repository's
**Settings → Secrets and variables → Actions → Variables**, then create the repository variable
`DEPLOY_ENABLED` with value `true`. This is a repository variable, not an environment variable or
secret. Terraform leaves this switch under your control. Set it to `false` to disable future
deployment jobs.

Once enabled, deployment jobs fail with an error naming each missing repository variable or secret
when configuration is incomplete.

Run the `API` and then `Web` GitHub Actions workflows on `main` after enabling deployment.
Subsequent pushes to `main` deploy the affected service when they match its workflow's path filters
and validation passes.

### API releases and migration safety

Terraform owns service configuration and probes; the API workflow deploys new images. The deployment
job builds and pushes the image, reads the database URL from Secret Manager, applies migrations, and
then deploys the image to Cloud Run. A migration failure stops the release.

Deployments are serialized, and a newer run does not cancel a running migration. Atlas also locks
migration execution in the database. Migrations run while the previous API version may still serve
traffic, so use changes compatible with that version and remove old structures in a later release.
An application rollback does not undo database migrations.

### Deployment credentials

Google deployment uses short-lived federation credentials; no service-account key is stored in
GitHub. Terraform grants the GitHub deployer access only to the database URL secret and publishes
its name as the repository variable `GCP_DATABASE_SECRET`. Reapply Terraform when adopting this
migration workflow so the permission and variable exist before enabling deployment. Database
credentials are not copied into GitHub secrets; the workflow retrieves and masks the URL for the
migration step.

The Web workflow uses the `CLOUDFLARE_PAGES_API_TOKEN` secret provisioned by Terraform. It builds
the frontend and deploys the static files, `_worker.js`, and `_routes.json` to Cloudflare Pages.
Terraform supplies `API_BASE_URL` as a Pages runtime binding for production and preview deployments.

## Runtime behavior

### Service configuration

Cloud Run is public and scales from zero to one instance, with one CPU and 512 MiB of memory.

Terraform sets `ENVIRONMENT=production` on Cloud Run for staging and production deployments.

The [Pages Worker](../web/worker/_worker.ts) proxies `/api` and `/api/*` to Cloud Run using the
`API_BASE_URL` runtime binding. Other requests use Pages static asset routing. See
[frontend and API routing](../README.md#frontend-and-api-routing) for proxy behavior.

Terraform gives production and preview deployments the same compatibility date and `API_BASE_URL`.
Previews share the production Cloud Run API and database, so preview writes affect production data.

Use `terraform -chdir=infra output` to see the application URLs and deployment configuration.

### Object storage

The R2 bucket has Terraform deletion protection and no public domain. CORS permits `GET`, `HEAD`,
and `PUT` only from the production Pages origin, with content and range headers for direct transfers
using presigned URLs. CORS alone does not grant access; upload and download endpoints are not
implemented yet.

The API token is scoped to objects in this bucket. Following
[Cloudflare's S3 credential derivation](https://developers.cloudflare.com/r2/api/tokens/), Terraform
stores its ID as the access key ID and the SHA-256 hash of its value as the secret access key in
separate Secret Manager secrets. Only the API runtime service account is granted access to those
secrets.

Cloud Run receives `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from Secret Manager, plus
`AWS_ENDPOINT_URL_S3`, `AWS_REGION=auto`, and `S3_BUCKET`. Terraform waits for the secret versions
and IAM grants before configuring the service. Reapply Terraform after rotating the R2 token, then
deploy a fresh Cloud Run revision so it loads the new secret values.

### Sentry

Set the required `sentry_organization` in [`terraform.tfvars`](terraform.tfvars) to an existing
organization slug. [`sentry.tf`](sentry.tf) creates a team and project named exactly `name`, with
separate API and web client keys.

Terraform supplies Cloud Run's `SENTRY_DSN` and the GitHub Actions variables `VITE_ENVIRONMENT` and
`VITE_SENTRY_DSN`, which the Web workflow requires when building a deployment. Both services use the
`production` environment; only public ingestion DSNs enter application configuration.

Rebuild and redeploy the web app after rotating its client key. See
[runtime configuration](../README.md#error-reporting) for reporting behavior.

### Health probes

Terraform configures startup and readiness probes on `/ready` and a liveness probe on `/health`, all
on port 8080 with a two-second probe timeout.

- Startup allows 24 failures at five-second intervals.
- Readiness runs every ten seconds, removes an instance from traffic after three failures, and
  requires two successes to restore traffic.
- Liveness runs every ten seconds and restarts the container after three failures; it does not
  depend on database availability.

The real API must connect to Postgres and verify R2 bucket access during its shared five-second
startup timeout or it exits before serving HTTP. Once running, each readiness check bounds its
database ping to one second.

## Validate without cloud credentials

Run from the repository root:

```sh
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
```

The `Infra` workflow formats and validates configuration; it does not apply cloud changes. Commit
[`infra/.terraform.lock.hcl`](.terraform.lock.hcl) to keep local and CI provider selections
consistent. Validation checks provider schemas and configuration, but a plan with real inputs and
credentials is still needed to verify account permissions and resource availability.
