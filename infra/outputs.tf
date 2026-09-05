output "api_url" {
  description = "Cloud Run API base URL."
  value       = google_cloud_run_v2_service.api.uri
}

output "web_url" {
  description = "Cloudflare Pages production URL."
  value       = local.web_origin
}

output "artifact_registry_repository" {
  description = "Docker repository used by the API deployment workflow."
  value       = "${google_artifact_registry_repository.api.location}-docker.pkg.dev/${var.google_project_id}/${google_artifact_registry_repository.api.repository_id}"
}

output "github_actions_variables" {
  description = "Non-secret GitHub repository variables managed for the deployment workflows."
  value       = local.github_actions_variables
}

output "postgres_host" {
  description = "Aiven PostgreSQL hostname, useful when running the schema bootstrap."
  value       = aiven_pg.postgres.service_host
}

output "postgres_port" {
  description = "Aiven PostgreSQL port."
  value       = aiven_pg.postgres.service_port
}

output "database_url" {
  description = "Sensitive Aiven connection URL for out-of-band schema administration."
  value = format(
    "postgresql://%s:%s@%s:%d/%s?sslmode=require",
    aiven_pg.postgres.service_username,
    urlencode(aiven_pg.postgres.service_password),
    aiven_pg.postgres.service_host,
    aiven_pg.postgres.service_port,
    aiven_pg_database.app.database_name,
  )
  sensitive = true
}

output "r2_bucket_name" {
  description = "Private R2 bucket used for application media."
  value       = cloudflare_r2_bucket.media.name
}
