output "project_uuid" {
  description = "Coolify Project UUID — match against the URL bar in Coolify UI to jump to your Project."
  value       = coolify_project.app.uuid
}

output "staging_env_uuid" {
  description = "Coolify staging Environment UUID."
  value       = coolify_environment.staging.uuid
}

output "staging_app_uuid" {
  description = "Coolify staging Application UUID."
  value       = coolify_application.staging.uuid
}

output "production_app_uuid" {
  description = "Coolify production Application UUID."
  value       = coolify_application.production.uuid
}

output "staging_url" {
  description = "URL where staging serves once the CI workflow's first deploy job succeeds. Push to the `staging` branch to trigger."
  value       = "http://${var.repo_name}-staging.${var.app_domain_base}"
}

output "prod_url" {
  description = "URL where production serves once the CI workflow's first deploy job succeeds. Merge to `main` to trigger."
  value       = "http://${var.repo_name}.${var.app_domain_base}"
}

output "next_steps" {
  description = "What to do after `terraform apply` succeeds."
  value = <<-EOT

    Terraform created:
      Coolify Project:        ${var.repo_name}   (uuid=${coolify_project.app.uuid})
      Coolify Environments:   staging, production
      Coolify Applications:   staging  (uuid=${coolify_application.staging.uuid})
                              production (uuid=${coolify_application.production.uuid})
      GitHub Actions secrets: COOLIFY_API_TOKEN
                              COOLIFY_DEPLOY_WEBHOOK_STAGING
                              COOLIFY_DEPLOY_WEBHOOK_PROD

    Nothing left to click. To deploy:

      1. `git push origin staging` — CI runs tests, then POSTs the staging
         webhook. Watch the deploy in Coolify UI, then hit:
           ${var.repo_name}-staging.${var.app_domain_base}

      2. Open a PR from `staging` to `main`, merge — CI runs tests, then POSTs
         the production webhook. Watch the deploy in Coolify UI, then hit:
           ${var.repo_name}.${var.app_domain_base}

    Tear it down when you're done exploring:
      terraform destroy
  EOT
}
