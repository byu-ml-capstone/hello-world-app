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
  endpoint = local.coolify_endpoint
  token    = var.coolify_token
}

provider "github" {
  token = var.github_token
  owner = var.github_org
}

# ---------------------------------------------------------------------------
# Coolify structure
# ---------------------------------------------------------------------------
# Project scoping is inherited from the token's team context. Whichever team
# owns the token, the Project lands there.
#
# Coolify auto-creates a `production` Environment when a Project is created,
# so we only explicitly declare `staging`.
# ---------------------------------------------------------------------------

resource "coolify_project" "app" {
  name        = var.repo_name
  description = "Provisioned by Terraform - hello-world-app lab"
}

resource "coolify_environment" "staging" {
  project_uuid = coolify_project.app.uuid
  name         = "staging"
}

# ---------------------------------------------------------------------------
# Applications - one per environment, same git repo, different branch
# ---------------------------------------------------------------------------
# Coolify silently rewrites `ports_exposes` when build_pack=dockercompose
# (compose parses its own ports), which the provider reports as a drift
# error. Ignore that specific attribute on subsequent runs to keep plans
# clean. is_auto_deploy_enabled=false matches "Manual deployments only"
# in the Coolify UI -> tests-gate-deploy pattern via GitHub Actions.
# ---------------------------------------------------------------------------

resource "coolify_application" "staging" {
  project_uuid     = coolify_project.app.uuid
  environment_uuid = coolify_environment.staging.uuid
  server_uuid      = local.server_uuid
  destination_uuid = local.destination_uuid
  github_app_uuid  = local.github_app_uuid

  git_repository = "${var.github_org}/${var.repo_name}"
  git_branch     = "staging"
  build_pack     = "dockercompose"
  ports_exposes  = "8000"

  is_auto_deploy_enabled = false
  instant_deploy         = false

  lifecycle {
    ignore_changes = [ports_exposes, name]
  }
}

resource "coolify_application" "prod" {
  project_uuid     = coolify_project.app.uuid
  environment_name = "production" # auto-created with the project
  server_uuid      = local.server_uuid
  destination_uuid = local.destination_uuid
  github_app_uuid  = local.github_app_uuid

  git_repository = "${var.github_org}/${var.repo_name}"
  git_branch     = "main"
  build_pack     = "dockercompose"
  ports_exposes  = "8000"

  is_auto_deploy_enabled = false
  instant_deploy         = false

  lifecycle {
    ignore_changes = [ports_exposes, name]
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions secrets
# ---------------------------------------------------------------------------
# The three secrets the shipped .github/workflows/ci.yml expects. Populated
# with the deploy webhook URLs Terraform can construct from the App UUIDs
# and the same COOLIFY_API_TOKEN this run authenticated with.
# ---------------------------------------------------------------------------

locals {
  deploy_webhook_staging = "${local.coolify_endpoint}/deploy?uuid=${coolify_application.staging.uuid}&force=false"
  deploy_webhook_prod    = "${local.coolify_endpoint}/deploy?uuid=${coolify_application.prod.uuid}&force=false"
}

resource "github_actions_secret" "coolify_webhook_staging" {
  repository      = var.repo_name
  secret_name     = "COOLIFY_DEPLOY_WEBHOOK_STAGING"
  value = local.deploy_webhook_staging
}

resource "github_actions_secret" "coolify_webhook_prod" {
  repository      = var.repo_name
  secret_name     = "COOLIFY_DEPLOY_WEBHOOK_PROD"
  value = local.deploy_webhook_prod
}

resource "github_actions_secret" "coolify_api_token" {
  repository      = var.repo_name
  secret_name     = "COOLIFY_API_TOKEN"
  value = var.coolify_token
}
