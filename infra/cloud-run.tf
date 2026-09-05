resource "google_service_account" "api" {
  project      = var.google_project_id
  account_id   = "${var.name}-api"
  display_name = "${var.name} Cloud Run API"

  depends_on = [google_project_service.required]
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

resource "google_secret_manager_secret" "r2_access_key_id" {
  project   = var.google_project_id
  secret_id = "${var.name}-r2-access-key-id"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "r2_access_key_id" {
  secret      = google_secret_manager_secret.r2_access_key_id.id
  secret_data = cloudflare_account_token.api_r2.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_secret_manager_secret_iam_member" "api_r2_access_key_id" {
  project   = var.google_project_id
  secret_id = google_secret_manager_secret.r2_access_key_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret" "r2_secret_access_key" {
  project   = var.google_project_id
  secret_id = "${var.name}-r2-secret-access-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "r2_secret_access_key" {
  secret      = google_secret_manager_secret.r2_secret_access_key.id
  secret_data = sha256(cloudflare_account_token.api_r2.value)

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_secret_manager_secret_iam_member" "api_r2_secret_access_key" {
  project   = var.google_project_id
  secret_id = google_secret_manager_secret.r2_secret_access_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_cloud_run_v2_service" "api" {
  project             = var.google_project_id
  name                = "${var.name}-api"
  location            = var.google_region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account                  = google_service_account.api.email
    max_instance_request_concurrency = 40

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello@sha256:4229c16c0c549905376c79943d0c122a728901330d10a080ec8ceb52e3f21f3e"

      startup_probe {
        timeout_seconds   = 2
        period_seconds    = 5
        failure_threshold = 24
        http_get {
          path = "/ready"
          port = 8080
        }
      }

      readiness_probe {
        timeout_seconds   = 2
        period_seconds    = 10
        failure_threshold = 3
        success_threshold = 2
        http_get {
          path = "/ready"
          port = 8080
        }
      }

      liveness_probe {
        timeout_seconds   = 2
        period_seconds    = 10
        failure_threshold = 3
        http_get {
          path = "/health"
          port = 8080
        }
      }

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name = "AWS_ACCESS_KEY_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.r2_access_key_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "AWS_ENDPOINT_URL_S3"
        value = local.r2_endpoint
      }
      env {
        name  = "AWS_REGION"
        value = "auto"
      }
      env {
        name = "AWS_SECRET_ACCESS_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.r2_secret_access_key.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "ENVIRONMENT"
        value = "production"
      }
      env {
        name  = "S3_BUCKET"
        value = cloudflare_r2_bucket.media.name
      }
      env {
        name = "SENTRY_DSN"
        # Only the public ingestion DSN belongs in application configuration.
        value = nonsensitive(sentry_key.app["api"].dsn["public"])
      }
    }
  }

  lifecycle {
    # Terraform owns service configuration; CI owns subsequent image updates.
    ignore_changes = [template[0].containers[0].image]
  }

  depends_on = [
    google_project_service.required,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.r2_access_key_id,
    google_secret_manager_secret_version.r2_secret_access_key,
    google_secret_manager_secret_iam_member.api_database_url,
    google_secret_manager_secret_iam_member.api_r2_access_key_id,
    google_secret_manager_secret_iam_member.api_r2_secret_access_key,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_api" {
  project  = var.google_project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
