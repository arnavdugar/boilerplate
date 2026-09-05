resource "google_project_service" "required" {
  for_each = local.google_apis

  project            = var.google_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "api" {
  project       = var.google_project_id
  location      = var.google_region
  repository_id = "${var.name}-api"
  description   = "${var.name} Go API container images"
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}
