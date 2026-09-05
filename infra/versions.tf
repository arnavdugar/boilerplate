terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "~> 4.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    sentry = {
      source  = "jianyuan/sentry"
      version = "~> 0.15.7"
    }
  }
}
