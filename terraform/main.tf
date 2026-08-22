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
# What this lab creates (mirrors Setup Steps 4-9 of the student guide)
# ---------------------------------------------------------------------------
# One `terraform apply` builds the entire Coolify + GitHub wiring:
#
#   - Coolify Project                          (Step 4)
#   - Coolify staging Environment              (Step 4; production auto-created)
#   - Coolify Application: staging             (Step 5)
#   - Coolify Application: production          (Step 6)
#   - COOLIFY_API_TOKEN GitHub secret          (Step 8)
#   - COOLIFY_DEPLOY_WEBHOOK_STAGING secret    (Step 7)
#   - COOLIFY_DEPLOY_WEBHOOK_PROD secret       (Step 9)
#
# Deploy webhook URLs are deterministic from each Application's UUID
# (`<endpoint>/deploy?uuid=<app_uuid>`), so no post-apply UI copy-paste.
#
# Requires the class Coolify instance to be running the local patch for
# coollabsio/coolify#11449 — without it, the coolify_application resources
# fail with `HTTP 404: Github App not found` on team-scoped tokens.
# Upstream tracking: coollabsio/coolify PR #11451.
# See coolify-runbook.md "Post-install patches" for reapplying after Coolify
# updates. Delete this comment once the fix ships upstream.
# ---------------------------------------------------------------------------

resource "coolify_project" "app" {
  name        = var.repo_name
  description = "Provisioned by Terraform - hello-world-app lab"
}

resource "coolify_environment" "staging" {
  project_uuid = coolify_project.app.uuid
  name         = "staging"
}

# The `production` Environment is auto-created by Coolify when the Project
# is born, so we don't declare it as a resource — the production Application
# below references it by name.

resource "coolify_application" "staging" {
  project_uuid     = coolify_project.app.uuid
  environment_uuid = coolify_environment.staging.uuid
  server_uuid      = var.coolify_server_uuid
  github_app_uuid  = var.coolify_github_app_uuid
  git_repository   = "${var.github_org}/${var.repo_name}"
  git_branch       = "staging"
  build_pack       = "dockercompose"
  # Coolify silently forces ports_exposes="80" server-side for dockercompose
  # apps (the field is really about Coolify's proxy ingress, not container
  # ports). Sending "8000" causes the bindtech-xyz provider to error with
  # "provider produced inconsistent result" on state read-back. The value
  # doesn't affect routing — Coolify + Traefik pick container ports from
  # docker-compose.yaml directly.
  ports_exposes = "80"

  # Coolify's API rejects the flat `domains` field for build_pack=dockercompose
  # (must use per-service `docker_compose_domains`, which the bindtech-xyz
  # provider doesn't expose yet). Auto-generated sslip.io URL is functional
  # but ugly — set the pretty class-wildcard domain via Coolify UI's
  # Domains tab after apply, or wait for provider support / Coolify v5.

  # CI/CD triggers deploys explicitly via the webhook after tests pass;
  # let Coolify's own GitHub-push auto-deploy stay off to avoid double-firing.
  is_auto_deploy_enabled = false
}

resource "coolify_application" "production" {
  project_uuid     = coolify_project.app.uuid
  environment_name = "production"
  server_uuid      = var.coolify_server_uuid
  github_app_uuid  = var.coolify_github_app_uuid
  git_repository   = "${var.github_org}/${var.repo_name}"
  git_branch       = "main"
  build_pack       = "dockercompose"
  # Coolify silently forces ports_exposes="80" server-side for dockercompose
  # apps (the field is really about Coolify's proxy ingress, not container
  # ports). Sending "8000" causes the bindtech-xyz provider to error with
  # "provider produced inconsistent result" on state read-back. The value
  # doesn't affect routing — Coolify + Traefik pick container ports from
  # docker-compose.yaml directly.
  ports_exposes = "80"

  is_auto_deploy_enabled = false
}

# COOLIFY_API_TOKEN is reused by both staging + production deploy jobs in the
# CI workflow. One token, one secret.
resource "github_actions_secret" "coolify_api_token" {
  repository  = var.repo_name
  secret_name = "COOLIFY_API_TOKEN"
  value       = var.coolify_token
}

# Deploy webhook URLs are `<endpoint>/deploy?uuid=<application_uuid>`.
# coolify_endpoint already includes the /api/v1 suffix, so this appends
# /deploy?uuid=... directly. CI workflow POSTs here with the bearer token.
locals {
  webhook_staging = "${var.coolify_endpoint}/deploy?uuid=${coolify_application.staging.uuid}"
  webhook_prod    = "${var.coolify_endpoint}/deploy?uuid=${coolify_application.production.uuid}"
}

resource "github_actions_secret" "deploy_webhook_staging" {
  repository  = var.repo_name
  secret_name = "COOLIFY_DEPLOY_WEBHOOK_STAGING"
  value       = local.webhook_staging
}

resource "github_actions_secret" "deploy_webhook_prod" {
  repository  = var.repo_name
  secret_name = "COOLIFY_DEPLOY_WEBHOOK_PROD"
  value       = local.webhook_prod
}

# ---------------------------------------------------------------------------
# Pretty domains — one manual UI click per Application (see outputs.tf)
# ---------------------------------------------------------------------------
# Setting per-service domains on dockercompose Applications is not something
# terraform can do end-to-end today. Chain of provider/API limitations:
#
#   1. The bindtech-xyz/coolify provider exposes only a flat `domains` field.
#   2. Coolify's API rejects that field for build_pack=dockercompose (must
#      use per-service `docker_compose_domains` instead).
#   3. Coolify's UPDATE endpoint doesn't allow `docker_compose_raw` in its
#      allowedFields list, and `docker_compose_domains` requires
#      `docker_compose_raw` to be non-empty first. That field is only
#      populated by Coolify on first deploy, or set at Application create
#      (which the bindtech-xyz provider doesn't expose either).
#
# Nets out to: this last step is a manual UI click. The `next_steps` output
# tells the student exactly what to paste and where.
#
# Real fixes worth doing at some point: fork bindtech-xyz/coolify to add
# `docker_compose_raw` at Application create time and `docker_compose_domains`
# as a settable field, OR wait for Coolify v5 where the API rewrite may
# obviate all of this. Track upstream in tickets/coolify-upstream/.
# ---------------------------------------------------------------------------

locals {
  compose_service_name  = "hello"
  staging_pretty_domain = "http://${var.repo_name}-staging.${var.app_domain_base}"
  prod_pretty_domain    = "http://${var.repo_name}.${var.app_domain_base}"
}
