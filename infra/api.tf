resource "google_service_account" "api" {
  project      = var.google_project_id
  account_id   = "${var.name}-api"
  display_name = "${var.name} Cloud Run API"

  depends_on = [google_project_service.required]
}

resource "google_artifact_registry_repository" "api" {
  project       = var.google_project_id
  location      = var.google_region
  repository_id = "${var.name}-api"
  description   = "${var.name} Go API container images"
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}

resource "google_cloud_run_v2_service" "api" {
  deletion_protection  = false
  ingress              = "INGRESS_TRAFFIC_ALL"
  invoker_iam_disabled = false
  location             = var.google_region
  name                 = "${var.name}-api"
  project              = var.google_project_id

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

resource "google_cloud_run_v2_service_iam_member" "debug_invoker" {
  for_each = var.debug_invokers

  location = google_cloud_run_v2_service.api.location
  member   = each.value
  name     = google_cloud_run_v2_service.api.name
  project  = var.google_project_id
  role     = "roles/run.invoker"

  condition {
    expression = "request.path.startsWith('/debug/')"
    title      = "debug_paths_only"
  }
}

resource "google_cloud_run_v2_service_iam_member" "debug_viewer" {
  for_each = var.debug_invokers

  location = google_cloud_run_v2_service.api.location
  member   = each.value
  name     = google_cloud_run_v2_service.api.name
  project  = var.google_project_id
  role     = "roles/run.viewer"
}
