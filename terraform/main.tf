terraform {
  required_version = ">= 1.5"
  required_providers {
    coolify = {
      source  = "bindtech-xyz/coolify"
      version = "~> 0.1.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "coolify" {
  endpoint = var.coolify_endpoint
  token    = var.coolify_token
}

provider "github" {
  token = var.github_token
  owner = var.github_org
}

# ---------------------------------------------------------------------------
# What this lab covers (and what it doesn't)
# ---------------------------------------------------------------------------
# Terraform handles the "clerical wiring" of Setup Steps 4 + 8:
#   - Coolify Project (Step 4)
#   - Coolify `staging` Environment (Step 4; `production` auto-created)
#   - COOLIFY_API_TOKEN GitHub Actions secret (part of Step 8)
#
# What Terraform does NOT handle (still manual, per Setup Steps 5-7 and 9):
#   - Coolify Applications (`staging` + `production`). Coolify's
#     private-github-app create endpoint has a team-scoping bug that rejects
#     `is_system_wide` GitHub Apps when the calling token isn't in the same
#     team as the App. The `byu-ml-capstone-coolify` App lives in Root Team
#     and student tokens live in their own team, so create fails with 404.
#     Until Coolify fixes this, Applications get created via the Coolify UI
#     the way the student-guide already teaches.
#   - COOLIFY_DEPLOY_WEBHOOK_STAGING + COOLIFY_DEPLOY_WEBHOOK_PROD secrets.
#     Copy the Deploy Webhook URL from each Application's Coolify UI ->
#     Webhooks tab, add manually via GitHub UI (Settings -> Secrets).
# ---------------------------------------------------------------------------

resource "coolify_project" "app" {
  name        = var.repo_name
  description = "Provisioned by Terraform - hello-world-app lab"
}

resource "coolify_environment" "staging" {
  project_uuid = coolify_project.app.uuid
  name         = "staging"
}

# COOLIFY_API_TOKEN gets reused across your app's staging + production deploys
# in the GitHub Actions workflow. Same value for both, so no need to duplicate.
resource "github_actions_secret" "coolify_api_token" {
  repository  = var.repo_name
  secret_name = "COOLIFY_API_TOKEN"
  value       = var.coolify_token
}
