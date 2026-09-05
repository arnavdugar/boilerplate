resource "cloudflare_pages_project" "web" {
  account_id        = var.cloudflare_account_id
  name              = var.cloudflare_pages_project_name
  production_branch = "main"

  deployment_configs = {
    preview = {
      compatibility_date = "2026-09-01"
      env_vars = {
        API_BASE_URL = {
          type  = "plain_text"
          value = google_cloud_run_v2_service.api.uri
        }
        GOOGLE_SERVICE_ACCOUNT_KEY = {
          type  = "secret_text"
          value = base64decode(google_service_account_key.pages.private_key)
        }
      }
    }
    production = {
      compatibility_date = "2026-09-01"
      env_vars = {
        API_BASE_URL = {
          type  = "plain_text"
          value = google_cloud_run_v2_service.api.uri
        }
        GOOGLE_SERVICE_ACCOUNT_KEY = {
          type  = "secret_text"
          value = base64decode(google_service_account_key.pages.private_key)
        }
      }
    }
  }
}

resource "google_service_account" "pages" {
  account_id   = "${var.name}-pages"
  display_name = "${var.name} Pages API invoker"
  project      = var.google_project_id

  depends_on = [google_project_service.required]
}

resource "google_service_account_key" "pages" {
  service_account_id = google_service_account.pages.name
}

resource "google_cloud_run_v2_service_iam_member" "pages_invoker" {
  location = google_cloud_run_v2_service.api.location
  member   = "serviceAccount:${google_service_account.pages.email}"
  name     = google_cloud_run_v2_service.api.name
  project  = var.google_project_id
  role     = "roles/run.invoker"

  condition {
    expression = "request.path == '/api' || request.path.startsWith('/api/')"
    title      = "api_paths_only"
  }
}
