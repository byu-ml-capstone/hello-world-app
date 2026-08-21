output "project_uuid" {
  description = "Coolify Project UUID — useful when creating Applications through the UI (Setup Step 5-6). Match this against the URL bar in Coolify."
  value       = coolify_project.app.uuid
}

output "staging_env_uuid" {
  description = "Coolify staging Environment UUID."
  value       = coolify_environment.staging.uuid
}

output "staging_url" {
  description = "Where staging will be reachable once you finish creating the Application in Coolify and push to the staging branch."
  value       = "http://${var.repo_name}-staging.${var.app_domain_base}"
}

output "prod_url" {
  description = "Where prod will be reachable once you finish creating the Application in Coolify and merge to main."
  value       = "http://${var.repo_name}.${var.app_domain_base}"
}

output "next_steps" {
  description = "What to do after `terraform apply` succeeds."
  value = <<-EOT

    Terraform created:
      Coolify Project:            ${var.repo_name}   (uuid=${coolify_project.app.uuid})
      Coolify Environments:       staging, production
      GitHub Actions secret:      COOLIFY_API_TOKEN

    What's still manual (per student-guide Setup Steps 5, 6, 7, 9):

      1. Coolify UI -> your Project (${var.repo_name}) -> production Environment
         -> + Add Resource -> GitHub Repo (with GitHub App).
         Wire it to ${var.github_org}/${var.repo_name} branch `main`,
         Build Pack Dockerfile, port 8000, Auto Deploy = Manual only.
         Set the Domain to http://${var.repo_name}.${var.app_domain_base}.

      2. Repeat for the staging Environment: branch `staging`, Domain
         http://${var.repo_name}-staging.${var.app_domain_base}.

      3. From each Application's Webhooks tab, copy the Deploy Webhook URL.

      4. GitHub repo Settings -> Secrets -> add
         COOLIFY_DEPLOY_WEBHOOK_STAGING (from staging Application)
         COOLIFY_DEPLOY_WEBHOOK_PROD    (from production Application)

    Why isn't this all Terraformed? Coolify's create-Application API endpoint
    has a team-scoping bug that rejects system-wide GitHub Apps from tokens
    outside Root Team. Until it's fixed, Applications get created via UI.
  EOT
}
