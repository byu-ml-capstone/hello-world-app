# Bonus: IaC for the Coolify + GitHub wiring

**Prerequisite: finish Setup Steps 1–11 of the student guide by hand at least once.** This bonus lab teaches nothing about *what* Coolify is — you already know that. It teaches **Infrastructure as Code** by re-doing Setup Steps 4–9 as declarative HCL. When you're done, one `terraform apply` recreates the entire Coolify + GitHub wiring for a bare-fresh repo, no clicks required.

## What Terraform creates

Everything in Setup Steps 4–9, in a single apply:

- **Coolify Project** named after your repo (Step 4)
- **`staging` Environment** — the `production` environment is auto-created when the Project is born
- **`staging` Application** wired to your repo's `staging` branch, `dockercompose` build pack, port 8000, auto-deploy off (Step 5)
- **`production` Application** wired to your repo's `main` branch, ditto config (Step 6)
- **`COOLIFY_API_TOKEN` GitHub Actions secret** — shared by both deploy jobs (Step 8)
- **`COOLIFY_DEPLOY_WEBHOOK_STAGING` secret** — URL is `<coolify-endpoint>/deploy?uuid=<staging_app_uuid>`, constructed in HCL from the Application UUID (Step 7)
- **`COOLIFY_DEPLOY_WEBHOOK_PROD` secret** — same shape, prod Application (Step 9)

Push to `staging` → CI runs tests, POSTs the staging webhook, staging deploys. Merge to `main` → CI runs tests, POSTs the prod webhook, prod deploys.

One thing Terraform can't set right now: **pretty domains**. Coolify's API rejects the flat `domains` field on `dockercompose` build packs (must use per-service `docker_compose_domains`), and the `bindtech-xyz/coolify` provider doesn't expose that structure yet. Applications get Coolify-auto-generated `<uuid>.128.187.112.8.sslip.io` URLs — functional but ugly. If you want the pretty `<repo>-staging.ml-capstone.cs.byu.edu` domain, set it via Coolify UI's Domains tab on each Application after `terraform apply` (Setup Step 6's Domains bullet). One-time click per Application; Coolify persists it.

## Requires a locally-patched Coolify instance

The `coolify_application` resources call `POST /api/v1/applications/private-github-app` with your student team-scoped token. Stock Coolify (as of v4.3.7 and `main` at the time of writing) has a bug — the endpoint returns `HTTP 404: Github App not found` for GitHub Apps flagged `is_system_wide`, which is exactly how the class `byu-ml-capstone-coolify` App is set up.

The class Coolify instance runs a local patch for this. If `terraform apply` fails on the Application resources with the 404, the patch has been wiped (Coolify auto-updated, or the container was recreated). Re-apply from rigel:

```bash
./scripts/repatch-coolify.sh --apply
```

Upstream tracking: [coollabsio/coolify#11449](https://github.com/coollabsio/coolify/issues/11449) (bug), [PR #11451](https://github.com/coollabsio/coolify/pull/11451) (fix — closed without merge on 2026-08-21; maintainer said "already fixed in next" but the fix isn't actually there yet). Likely resolved when Coolify v5 ships, since the `v5.x` branch removes this endpoint entirely. Until then this lab depends on the local patch. When v5 lands and rigel migrates, retest, and if the bug is genuinely gone, delete the patch script and this section.

Forking to a different Coolify instance? You'll hit the same 404 unless that instance is also patched. Either wait for upstream, or patch your own.

## Prerequisites

1. **Terraform** (or OpenTofu — same commands):
   ```bash
   brew tap hashicorp/tap
   brew install hashicorp/tap/terraform
   ```
2. **A Coolify API token.** ml-capstone-admin.cs.byu.edu → top-left dashboard menu → **Keys & Tokens → API Tokens → + New Token**. Description = whatever; **Permissions = root** (or view + create + deploy + delete). Copy immediately (Coolify shows it once).
3. **A GitHub Personal Access Token** with `repo` scope. Easiest: `gh auth token`. Otherwise Settings → Developer settings → Personal access tokens → Tokens (classic) → new one with `repo` scope. Full walkthrough is in `terraform.tfvars.example`.
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

Seven resources get created (Project + Environment + two Applications + three GitHub secrets). Then follow the `next_steps` output — it tells you which branches to push to trigger each deploy.

## Files

- `main.tf` — providers + Project + Environment + Applications + three secrets
- `variables.tf` — inputs + class-default overrides (server UUID, GitHub App UUID)
- `outputs.tf` — UUIDs, URLs, next-steps message
- `terraform.tfvars.example` — copy-to-tfvars template with detailed comments
- `.gitignore` — blocks `terraform.tfvars`, `.terraform/`, `*.tfstate`

## Cleanup

```bash
terraform destroy
```

Removes the Project (cascades to its Environments and Applications) and all three GitHub secrets. Full teardown.

## The point

You're seeing the shape of declarative infrastructure end-to-end — inputs in tfvars, a plan preview, apply, state file, drift detection, `destroy` reverses everything. That mental shift — "click here, then here, then copy this URL to that other UI" → "declare this shape, let the tool make it happen" — is IaC in one sitting. It generalizes to Terraform for AWS, Kubernetes YAML, Nix, Pulumi, everything modern.

The one caveat: this lab depends on a patched Coolify. That's exactly the kind of real-world "you're waiting on an upstream fix and running a local patch" situation you'll hit repeatedly in production infrastructure work. The dependency is documented here; the patch is scripted (`scripts/repatch-coolify.sh`); the upstream ticket + PR are linked. When upstream merges, the patch is removed and this section deleted. That's how you manage this kind of technical debt.
