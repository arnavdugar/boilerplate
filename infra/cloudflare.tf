data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = var.cloudflare_account_id
}

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
      }
    }
    production = {
      compatibility_date = "2026-09-01"
      env_vars = {
        API_BASE_URL = {
          type  = "plain_text"
          value = google_cloud_run_v2_service.api.uri
        }
      }
    }
  }
}

resource "cloudflare_account_token" "github_pages" {
  account_id = var.cloudflare_account_id
  name       = "${var.name}-github-pages"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = local.cloudflare_pages_write_permission_id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    })
  }]
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
