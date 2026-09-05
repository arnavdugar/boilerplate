resource "aiven_pg" "postgres" {
  project                = var.aiven_project_name
  service_name           = var.name
  cloud_name             = var.aiven_cloud_name
  plan                   = var.aiven_postgres_plan
  termination_protection = true

  pg_user_config {
    pg_version = "18"
  }
}

resource "aiven_pg_database" "app" {
  project       = var.aiven_project_name
  service_name  = aiven_pg.postgres.service_name
  database_name = var.name
}

resource "google_secret_manager_secret" "database_url" {
  project   = var.google_project_id
  secret_id = "${var.name}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id
  secret_data = format(
    "postgresql://%s:%s@%s:%d/%s?sslmode=require",
    aiven_pg.postgres.service_username,
    urlencode(aiven_pg.postgres.service_password),
    aiven_pg.postgres.service_host,
    aiven_pg.postgres.service_port,
    aiven_pg_database.app.database_name,
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_secret_manager_secret_iam_member" "api_database_url" {
  project   = var.google_project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}
