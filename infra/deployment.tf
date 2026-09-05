locals {
  cloudflare_pages_write_permission_id = one([
    for permission_group in data.cloudflare_account_api_token_permission_groups_list.all.result : permission_group.id
    if permission_group.name == "Pages Write" && contains(permission_group.scopes, "com.cloudflare.api.account")
  ])

  github_actions_variables = {
    CLOUDFLARE_ACCOUNT_ID          = var.cloudflare_account_id
    CLOUDFLARE_PAGES_PROJECT       = cloudflare_pages_project.web.name
    GCP_ARTIFACT_REPOSITORY        = google_artifact_registry_repository.api.repository_id
    GCP_CLOUD_RUN_SERVICE          = google_cloud_run_v2_service.api.name
    GCP_DATABASE_SECRET            = google_secret_manager_secret.database_url.secret_id
    GCP_DEPLOY_SERVICE_ACCOUNT     = google_service_account.github_deployer.email
    GCP_PROJECT_ID                 = var.google_project_id
    GCP_REGION                     = var.google_region
    GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    VITE_ENVIRONMENT               = "production"
    # Public ingestion DSNs are safe to embed in the browser bundle.
    VITE_SENTRY_DSN = nonsensitive(sentry_key.app["web"].dsn["public"])
  }

  github_repository_full_name = "${var.github_owner}/${var.github_repository_name}"
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.google_project_id
  workload_identity_pool_id = "${var.name}-github"
  display_name              = "${var.name} GitHub Actions"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.google_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.name}-github"
  display_name                       = "${var.name} main branch deploys"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == '${local.github_repository_full_name}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_deployer" {
  project      = var.google_project_id
  account_id   = "${var.name}-api-deployer"
  display_name = "${var.name} GitHub API deployer"

  depends_on = [google_project_service.required]
}

resource "google_service_account_iam_member" "github_workload_identity_user" {
  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_repository_full_name}"
}

resource "google_project_iam_member" "github_cloud_run_developer" {
  project = var.google_project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_artifact_registry_repository_iam_member" "github_writer" {
  project    = var.google_project_id
  location   = google_artifact_registry_repository.api.location
  repository = google_artifact_registry_repository.api.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "github_api_service_account_user" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_secret_manager_secret_iam_member" "github_database_url" {
  project   = var.google_project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "cloudflare_account_token" "github_pages" {
  account_id = var.cloudflare_account_id
  name       = "${var.name}-github-pages"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = local.cloudflare_pages_write_permission_id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    })
  }]
}

resource "github_actions_variable" "deploy_enabled" {
  repository    = var.github_repository_name
  variable_name = "DEPLOY_ENABLED"
  value         = "true"

  lifecycle {
    ignore_changes = [value]
  }

  # Enable deployments only after their settings, permissions, and storage CORS are provisioned.
  depends_on = [
    cloudflare_r2_bucket_cors.media,
    github_actions_secret.cloudflare_pages_deploy_token,
    github_actions_variable.deployment,
    google_artifact_registry_repository_iam_member.github_writer,
    google_cloud_run_v2_service_iam_member.pages_invoker,
    google_project_iam_member.github_cloud_run_developer,
    google_secret_manager_secret_iam_member.github_database_url,
    google_service_account_iam_member.github_api_service_account_user,
    google_service_account_iam_member.github_workload_identity_user,
  ]
}

resource "github_actions_variable" "deployment" {
  for_each = local.github_actions_variables

  repository    = var.github_repository_name
  variable_name = each.key
  value         = each.value
}

resource "github_actions_secret" "cloudflare_pages_deploy_token" {
  repository  = var.github_repository_name
  secret_name = "CLOUDFLARE_PAGES_API_TOKEN"
  value       = cloudflare_account_token.github_pages.value
}
