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
    # magodo/restful covers the one thing bindtech-xyz/coolify doesn't:
    # PATCHing docker_compose_domains on dockercompose applications
    # (see the restful_operation blocks near the bottom of this file).
    restful = {
      source  = "magodo/restful"
      version = "~> 0.20"
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

provider "restful" {
  # base_url is the host root (without /api/v1) — each restful_operation
  # resource specifies the full path including /api/v1.
  base_url = replace(var.coolify_endpoint, "/api/v1", "")
  header = {
    Authorization = "Bearer ${var.coolify_token}"
  }
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
# Pretty per-service domains via docker_compose_domains
# ---------------------------------------------------------------------------
# The bindtech-xyz/coolify provider only exposes the flat `domains` field,
# and Coolify's API rejects that field for build_pack=dockercompose
# (must use per-service `docker_compose_domains`). Fill the gap with a
# `restful_operation` from magodo/restful — a native terraform resource
# that PATCHes the field on the existing Application.
#
# `restful_operation` is a "one-time API call" resource: it fires the PATCH
# on create, re-fires when `body` changes, and does nothing on destroy
# (the domain lives on the parent Application, which cascade-deletes with
# the project via the coolify provider). No drift detection — if someone
# changes the domain via the Coolify UI, terraform won't notice until the
# `body` here changes. That's the same trade-off you'd get from a
# `local-exec` provisioner, but with cleaner HCL and no `curl` dependency
# on the machine running apply.
#
# `SERVICE_NAME` is the docker-compose service name from docker-compose.yaml
# that should own the public URL (see the `SERVICE_FQDN_HELLO` note in that
# file). Change it if you rename the service or route a different one.
#
# Delete this block (and drop the restful provider) when bindtech-xyz adds
# docker_compose_domains support, or when we migrate to Coolify v5.
# ---------------------------------------------------------------------------

locals {
  compose_service_name  = "hello"
  staging_pretty_domain = "http://${var.repo_name}-staging.${var.app_domain_base}"
  prod_pretty_domain    = "http://${var.repo_name}.${var.app_domain_base}"

  # Coolify rejects `docker_compose_domains` unless `docker_compose_raw` is
  # already populated on the Application. Normally Coolify populates that by
  # cloning the repo on first deploy, but we PATCH domains BEFORE any deploy
  # has happened. Workaround: read the compose file from the local repo (one
  # dir up from the terraform module — students clone the whole template,
  # keeping this relative path stable) and PATCH it into docker_compose_raw
  # ourselves, then PATCH the domains.
  compose_raw = file("${path.module}/../docker-compose.yaml")
}

# Step 1 of 2: seed docker_compose_raw so Coolify's per-service validation
# has something to check the `name` field against.
resource "restful_operation" "staging_compose_raw" {
  path   = "/api/v1/applications/${coolify_application.staging.uuid}"
  method = "PATCH"
  body = {
    docker_compose_raw = local.compose_raw
  }
}

resource "restful_operation" "production_compose_raw" {
  path   = "/api/v1/applications/${coolify_application.production.uuid}"
  method = "PATCH"
  body = {
    docker_compose_raw = local.compose_raw
  }
}

# Step 2 of 2: PATCH the per-service domain. depends_on forces this to run
# AFTER the corresponding compose_raw is populated (terraform can't infer
# the ordering because the two operations target the same parent resource
# via literal strings, not resource-attribute references).
resource "restful_operation" "staging_domain" {
  path   = "/api/v1/applications/${coolify_application.staging.uuid}"
  method = "PATCH"
  body = {
    docker_compose_domains = [{
      name   = local.compose_service_name
      domain = local.staging_pretty_domain
    }]
  }

  depends_on = [restful_operation.staging_compose_raw]
}

resource "restful_operation" "production_domain" {
  path   = "/api/v1/applications/${coolify_application.production.uuid}"
  method = "PATCH"
  body = {
    docker_compose_domains = [{
      name   = local.compose_service_name
      domain = local.prod_pretty_domain
    }]
  }

  depends_on = [restful_operation.production_compose_raw]
}
