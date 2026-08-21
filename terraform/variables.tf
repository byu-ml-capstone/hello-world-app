variable "coolify_token" {
  description = "Coolify API token with root or team-scoped read+create+deploy. Create via ml-capstone-admin.cs.byu.edu -> Keys & Tokens."
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub PAT with repo scope for writing Actions secrets to your student repo. Easiest: `gh auth token`."
  type        = string
  sensitive   = true
}

variable "repo_name" {
  description = "Name of your GitHub repo under byu-ml-capstone (e.g., `qsnell-hello`). Also used as the Coolify Project name and the base for staging + prod domains."
  type        = string
}

variable "github_org" {
  description = "GitHub org that owns the repo."
  type        = string
  default     = "byu-ml-capstone"
}

# Classroom-cluster constants. Same for every student; hardcoded so the
# tfvars file only needs the three secrets above.
locals {
  coolify_endpoint  = "https://ml-capstone-admin.cs.byu.edu/api/v1"
  admin_domain_base = "ml-capstone.cs.byu.edu"

  # UUIDs from the ml-capstone Coolify instance. Query with curl to refresh:
  #   GET /api/v1/servers          -> pick the `localhost` (rigel) server
  #   GET /api/v1/github-apps      -> pick byu-ml-capstone-coolify
  #   GET /api/v1/servers/<uuid>/destinations  -> pick the `coolify` network
  server_uuid      = "n1wne6tvlebvws9zcuz6c1cg" # rigel (Coolify shows it as "localhost")
  github_app_uuid  = "onb2ftjqxx6lxxqwa20ku6ve" # byu-ml-capstone-coolify GitHub App
  destination_uuid = "i12hh0u2pljlnnxrdj0g11xi" # `coolify` Docker network on rigel
}
