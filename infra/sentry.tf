resource "sentry_team" "app" {
  name         = var.name
  organization = var.sentry_organization
  slug         = var.name
}

resource "sentry_project" "app" {
  default_key  = false
  name         = var.name
  organization = var.sentry_organization
  platform     = "other"
  slug         = var.name
  teams        = [sentry_team.app.slug]
}

resource "sentry_key" "app" {
  for_each = toset(["api", "web"])

  name         = "${var.name}-${each.key}"
  organization = var.sentry_organization
  project      = sentry_project.app.slug
}
