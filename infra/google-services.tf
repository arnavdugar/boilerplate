locals {
  google_apis = toset([
    "artifactregistry.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sts.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.google_apis

  project            = var.google_project_id
  service            = each.value
  disable_on_destroy = false
}
