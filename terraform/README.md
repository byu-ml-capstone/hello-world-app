# Bonus: IaC for the Coolify + GitHub wiring

**Prerequisite: you should have already finished Setup Steps 1–11 of the student guide by hand at least once.** This bonus lab teaches nothing about *what* Coolify is — you already know that. It teaches **Infrastructure as Code** by re-doing parts of Setup Steps 4 + 8 as declarative HCL. When you're done, one `terraform apply` recreates that state from a bare fresh repo.

## What Terraform does

- Creates the **Coolify Project** named after your repo
- Creates the **`staging` Environment** (the `production` environment is auto-created when the project is born)
- Writes the **`COOLIFY_API_TOKEN` GitHub Actions secret** on your repo

## What Terraform doesn't do (still manual)

- **Coolify Applications** stay in the UI (Setup Steps 5–6). See "Why" below.
- **`COOLIFY_DEPLOY_WEBHOOK_STAGING` + `COOLIFY_DEPLOY_WEBHOOK_PROD` secrets** — copy each from Coolify's Applications → Webhooks tab and paste into GitHub's UI (Setup Steps 7 + 9).
- **Custom domains** on the Applications — set via Coolify UI's Domains tab.

Think of Terraform as covering the "clerical" wiring around the Application-create step — every UI moment that isn't picking a GitHub App or clicking through the Coolify create-Application wizard.

## Why not Terraform-all-of-it?

Coolify's `POST /api/v1/applications/private-github-app` endpoint has a team-scoping bug: it doesn't respect the `is_system_wide` flag on GitHub Apps. The `byu-ml-capstone-coolify` App is installed on the whole org and lives in Root Team; student tokens live in their own team. Result: `terraform apply` fails with `HTTP 404: Github App not found` when it tries to create an Application from a student token.

Confirmed via direct API call (same failure, not a provider issue). Filed as a Coolify issue; when it's fixed, this lab can add the Application resources back.

## Prerequisites

1. **Terraform** (or OpenTofu — same commands):
   ```bash
   brew tap hashicorp/tap
   brew install hashicorp/tap/terraform
   ```
2. **A Coolify API token.** ml-capstone-admin.cs.byu.edu → top-left dashboard menu → **Keys & Tokens → API Tokens → + New Token**. Description = whatever; **Permissions = root**. Copy immediately (Coolify shows it once).
3. **A GitHub Personal Access Token** with `repo` scope. Easiest source: `gh auth token`. Otherwise Settings → Developer settings → Personal access tokens → Tokens (classic) → new one with `repo` scope. Full walkthrough is in `terraform.tfvars.example`.
4. **Your GitHub repo already exists** under `byu-ml-capstone` from templating `hello-world-app` (Setup Step 1).

## Usage

```bash
# 1. Copy the tfvars template + fill in your secrets
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 2. Init (downloads the coolify + github providers)
terraform init

# 3. Plan (dry-run — shows what will be created)
terraform plan

# 4. Apply
terraform apply
```

3 resources get created. Then follow the `next_steps` output — it walks you through the UI clicks to finish the Application setup.

## Files

- `main.tf` — providers + Project + Environment + api-token secret
- `variables.tf` — inputs + class-default overrides
- `outputs.tf` — UUIDs, URLs, next-steps message
- `terraform.tfvars.example` — copy-to-tfvars template with detailed comments
- `.gitignore` — blocks `terraform.tfvars`, `.terraform/`, `*.tfstate`

## Cleanup

```bash
terraform destroy
```

Removes the Project (cascades to its Environments) and the GitHub secret. Applications you created via UI aren't managed by Terraform, so they stay — delete them separately in Coolify UI if you want a truly fresh slate.

## The point (even at reduced scope)

You're seeing the shape of declarative infrastructure — inputs in tfvars, a plan preview, apply, state file, drift detection, `destroy` reverses everything. That mental shift — "click here, then here" → "declare this shape, let the tool make it happen" — is IaC in one sitting. It generalizes to Terraform for AWS, Kubernetes YAML, Nix, Pulumi, everything modern. The specific coverage gap (Applications stay in UI) is Coolify-provider-immaturity, not an IaC-doesn't-work story.
