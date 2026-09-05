resource "github_actions_variable" "deployment" {
  for_each = local.github_actions_variables

  repository    = var.github_repository_name
  variable_name = each.key
  value         = each.value
}

resource "github_actions_secret" "cloudflare_pages_deploy_token" {
  repository  = var.github_repository_name
  secret_name = "CLOUDFLARE_PAGES_API_TOKEN"
  value       = cloudflare_account_token.github_pages.value
}
