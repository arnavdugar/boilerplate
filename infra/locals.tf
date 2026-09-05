locals {
  web_origin = "https://${cloudflare_pages_project.web.subdomain}"
}

data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = var.cloudflare_account_id
}
