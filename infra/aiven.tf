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
