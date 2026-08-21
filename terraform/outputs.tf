output "project_uuid" {
  description = "Coolify Project UUID - useful for debugging or manual API calls."
  value       = coolify_project.app.uuid
}

output "staging_app_uuid" {
  description = "Coolify Application UUID for the staging deploy."
  value       = coolify_application.staging.uuid
}

output "prod_app_uuid" {
  description = "Coolify Application UUID for the production deploy."
  value       = coolify_application.prod.uuid
}

output "staging_url" {
  description = "Where staging will be reachable once deployed (Coolify auto-assigns a domain; may not match exactly what the manual guide taught)."
  value       = "http://${var.repo_name}-staging.${local.admin_domain_base}"
}

output "prod_url" {
  description = "Where prod will be reachable once deployed."
  value       = "http://${var.repo_name}.${local.admin_domain_base}"
}

output "next_steps" {
  description = "What to do after `terraform apply` succeeds."
  value = <<-EOT

    Terraform created:
      Coolify Project:      ${var.repo_name}
      Environments:         staging, production
      Applications:         2 (staging + prod), both set to Manual deploy
      GitHub Actions secrets: 3 (COOLIFY_DEPLOY_WEBHOOK_STAGING, ..._PROD, COOLIFY_API_TOKEN)

    IMPORTANT - you still need to set the domain manually (Coolify's API
    doesn't let Terraform pin custom domains at create time). Open each
    Application in Coolify's UI -> Domains tab -> replace the auto-generated
    sslip.io domain with:
      staging:  http://${var.repo_name}-staging.${local.admin_domain_base}
      prod:     http://${var.repo_name}.${local.admin_domain_base}

    Then push a commit to your `staging` branch to trigger the first deploy
    through GitHub Actions -> Coolify.
  EOT
}
