variable "debug_invokers" {
  default     = []
  description = "User, group, or service-account IAM principals allowed to invoke /debug/ paths."
  nullable    = false
  type        = set(string)

  validation {
    condition = alltrue([
      for principal in var.debug_invokers :
      can(regex("^(group|serviceAccount|user):[^[:space:]]+@[^[:space:]]+$", principal))
    ])
    error_message = "debug_invokers must contain user:, group:, or serviceAccount: email principals."
  }
}

variable "google_project_id" {
  description = "Google Cloud project that owns Artifact Registry, Secret Manager, and Cloud Run."
  type        = string
}

variable "google_region" {
  description = "Google Cloud region for Artifact Registry and Cloud Run."
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the private R2 bucket, Pages project, and API tokens."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character lowercase hexadecimal account ID."
  }
}

variable "cloudflare_pages_project_name" {
  description = "Cloudflare Pages project name and pages.dev subdomain prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,56}[a-z0-9])?$", var.cloudflare_pages_project_name))
    error_message = "cloudflare_pages_project_name must contain 1-58 lowercase letters, digits, or hyphens and cannot begin or end with a hyphen."
  }
}

variable "aiven_project_name" {
  description = "Existing Aiven project in which to create PostgreSQL."
  type        = string
}

variable "aiven_cloud_name" {
  description = "Aiven cloud and region for PostgreSQL."
  type        = string
}

variable "aiven_postgres_plan" {
  description = "Aiven PostgreSQL service plan."
  type        = string
}

variable "github_owner" {
  description = "GitHub account that owns the deployment repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_owner))
    error_message = "github_owner must contain only letters, digits, underscores, periods, or hyphens."
  }
}

variable "github_repository_name" {
  description = "GitHub repository whose main branch is allowed to deploy the application."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_repository_name))
    error_message = "github_repository_name must contain only letters, digits, underscores, periods, or hyphens."
  }
}

variable "name" {
  description = "Application name used for the PostgreSQL service, application database, and R2 bucket, and as a prefix for other provisioned resources."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}[a-z0-9]$", var.name))
    error_message = "name must be 3-17 lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "r2_location" {
  description = "Best-effort R2 location hint."
  type        = string

  validation {
    condition     = contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], var.r2_location)
    error_message = "r2_location must be one of apac, eeur, enam, weur, wnam, or oc."
  }
}

variable "sentry_organization" {
  description = "Existing Sentry organization slug in which to create the application team, project, and client keys."
  nullable    = false
  type        = string

  validation {
    condition     = trimspace(var.sentry_organization) != ""
    error_message = "sentry_organization must not be empty."
  }
}
