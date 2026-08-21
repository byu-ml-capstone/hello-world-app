# ---------------------------------------------------------------------------
# Required per-student secrets + name
# ---------------------------------------------------------------------------

variable "coolify_token" {
  description = "Coolify API token with root or team-scoped read+create+deploy. Create via ml-capstone-admin.cs.byu.edu -> Keys & Tokens."
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub PAT with `repo` scope for writing Actions secrets to your student repo. Easiest: `gh auth token`."
  type        = string
  sensitive   = true
}

variable "repo_name" {
  description = "Just the repo name (e.g. `qsnell-hello`), NOT including the org prefix. The org comes from `github_org` (default byu-ml-capstone) and gets prepended internally. Also used as the Coolify Project name and the base for staging + prod domains."
  type        = string

  validation {
    condition     = !can(regex("/", var.repo_name))
    error_message = "repo_name should be just the repo name (e.g. `qsnell-hello`), NOT `byu-ml-capstone/qsnell-hello`. The `byu-ml-capstone/` org prefix comes from the `github_org` variable and gets prepended automatically."
  }
}

# ---------------------------------------------------------------------------
# Overrides (defaults are correct for the BYU ml-capstone class)
# ---------------------------------------------------------------------------
# All the values below default to what the ml-capstone cluster ships with,
# so class students never need to touch them. Change them in
# terraform.tfvars if you fork this lab to a different Coolify instance,
# a different GitHub org, or your own class cluster.

variable "github_org" {
  description = "GitHub org (or user) that owns the repo. Defaults to `byu-ml-capstone` for the class. Override if you fork to a different org or your personal account."
  type        = string
  default     = "byu-ml-capstone"
}

variable "coolify_endpoint" {
  description = "Coolify's REST API base URL. `https://<your-coolify-host>/api/v1`. Defaults to the ml-capstone class instance."
  type        = string
  default     = "https://ml-capstone-admin.cs.byu.edu/api/v1"
}

variable "app_domain_base" {
  description = "Wildcard-covered base domain for student apps (Coolify + Traefik route `<repo_name>.<app_domain_base>` and `<repo_name>-staging.<app_domain_base>`). Defaults to the ml-capstone class wildcard."
  type        = string
  default     = "ml-capstone.cs.byu.edu"
}
