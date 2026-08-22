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
  description = "URL where staging serves once the CI workflow's first deploy job succeeds. Push to the `staging` branch to trigger. Coolify auto-generates a sslip.io URL because the bindtech-xyz provider doesn't expose per-service docker_compose_domains yet — set the pretty class-wildcard domain (http://<repo>-staging.ml-capstone.cs.byu.edu) via the Coolify UI's Domains tab after apply if you want it."
  value       = coolify_application.staging.fqdn
}

output "prod_url" {
  description = "URL where production serves once the CI workflow's first deploy job succeeds. Merge to `main` to trigger. Same auto-generated sslip.io caveat as staging_url."
  value       = coolify_application.production.fqdn
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
         webhook. Watch the deploy in Coolify UI, then hit staging_url:
           ${coolify_application.staging.fqdn}

      2. Open a PR from `staging` to `main`, merge — CI runs tests, then POSTs
         the production webhook. Watch the deploy in Coolify UI, then hit
         prod_url:
           ${coolify_application.production.fqdn}

    URLs are Coolify-auto-generated sslip.io addresses. To use the pretty
    class-wildcard domain instead, set it via the Coolify UI's Domains tab
    on each Application (bindtech-xyz provider limitation — it doesn't
    expose per-service docker_compose_domains yet).

    Tear it down when you're done exploring:
      terraform destroy
  EOT
}
