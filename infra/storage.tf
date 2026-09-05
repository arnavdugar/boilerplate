locals {
  cloudflare_r2_bucket_item_write_permission_id = one([
    for permission_group in data.cloudflare_account_api_token_permission_groups_list.all.result : permission_group.id
    if permission_group.name == "Workers R2 Storage Bucket Item Write" && contains(permission_group.scopes, "com.cloudflare.edge.r2.bucket")
  ])

  r2_endpoint = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
}

resource "cloudflare_r2_bucket" "media" {
  account_id    = var.cloudflare_account_id
  name          = var.name
  jurisdiction  = "default"
  location      = var.r2_location
  storage_class = "Standard"

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_r2_bucket_cors" "media" {
  account_id   = var.cloudflare_account_id
  bucket_name  = cloudflare_r2_bucket.media.name
  jurisdiction = cloudflare_r2_bucket.media.jurisdiction

  rules = [{
    id = "presigned-media-from-web"
    allowed = {
      origins = [local.web_origin]
      methods = ["GET", "HEAD", "PUT"]
      headers = ["Content-Type", "Range"]
    }
    expose_headers  = ["Accept-Ranges", "Content-Length", "Content-Range", "ETag"]
    max_age_seconds = 3600
  }]
}

resource "cloudflare_account_token" "api_r2" {
  account_id = var.cloudflare_account_id
  name       = "${var.name}-api-r2"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = local.cloudflare_r2_bucket_item_write_permission_id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${var.cloudflare_account_id}_default_${cloudflare_r2_bucket.media.name}" = "*"
    })
  }]
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
