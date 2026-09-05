locals {
  google_apis = toset([
    "artifactregistry.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sts.googleapis.com",
  ])

  web_origin                  = "https://${cloudflare_pages_project.web.subdomain}"
  r2_endpoint                 = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
  github_repository_full_name = "${var.github_owner}/${var.github_repository_name}"
  cloudflare_r2_bucket_item_write_permission_id = one([
    for permission_group in data.cloudflare_account_api_token_permission_groups_list.all.result : permission_group.id
    if permission_group.name == "Workers R2 Storage Bucket Item Write" && contains(permission_group.scopes, "com.cloudflare.edge.r2.bucket")
  ])
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
}
