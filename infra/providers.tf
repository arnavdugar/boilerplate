provider "aiven" {}

provider "cloudflare" {}

provider "google" {
  project = var.google_project_id
  region  = var.google_region
}

provider "github" {
  owner = var.github_owner
}

provider "sentry" {}
