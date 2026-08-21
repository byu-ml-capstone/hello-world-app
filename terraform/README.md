# Bonus: the same Coolify setup, in Terraform

**Prerequisite: you should have already finished Setup Steps 1–11 of the student guide by hand at least once.** This bonus lab teaches nothing about *what* Coolify is — you already know that. It teaches **Infrastructure as Code** by re-doing everything you clicked through in the UI as declarative HCL. When you're done, one `terraform apply` recreates the whole thing.

## What this does

Same result as Setup Steps 4–9 of the student guide, but expressed in ~150 lines of HCL:

- Creates a **Coolify Project** named after your repo
- Creates the **`staging` Environment** inside it (the `production` environment is auto-created by Coolify when the project is born)
- Creates two **Coolify Applications** — one per environment — both pointing at your GitHub repo, both set to `Manual deployments only` so GitHub Actions gates deploys behind tests
- Wires the **three GitHub Actions secrets** on your repo (`COOLIFY_DEPLOY_WEBHOOK_STAGING`, `COOLIFY_DEPLOY_WEBHOOK_PROD`, `COOLIFY_API_TOKEN`) so the CI pipeline works out of the box

## What this does NOT do

- **Doesn't create your GitHub repo** — you templated that manually from `byu-ml-capstone/hello-world-app` in Setup Step 1. This lab expects the repo already exists.
- **Doesn't set custom domains** — Coolify's API doesn't let Terraform pin custom domains at Application create time. After `apply`, open each Application in Coolify UI → Domains tab → set your `<repo>-staging.ml-capstone.cs.byu.edu` / `<repo>.ml-capstone.cs.byu.edu` values by hand. This is ~30 seconds of clicking, but it's the honest state of the provider today.
- **Doesn't grant you Coolify access** — you already signed in and got your team via the roster + `provision-teams.sh` script the instructor ran. Terraform can't create a Coolify user that doesn't already exist in the DB.

## Prerequisites

1. **Terraform** (or OpenTofu — same commands):
   ```bash
   brew tap hashicorp/tap
   brew install hashicorp/tap/terraform
   ```
2. **A Coolify API token** with root permissions. Create at [ml-capstone-admin.cs.byu.edu](https://ml-capstone-admin.cs.byu.edu) → top-left dashboard menu → **Keys & Tokens → API Tokens → + New Token**. Description = whatever you like; **Permissions = root**. Copy the token.
3. **A GitHub Personal Access Token** with `repo` scope. Easiest source: `gh auth token` (if you have the GitHub CLI installed and authenticated). Otherwise generate one at [github.com/settings/tokens](https://github.com/settings/tokens).
4. **Your GitHub repo already exists** under `byu-ml-capstone` from templating `hello-world-app` (Setup Step 1).

## Usage

```bash
# 1. Copy the tfvars template + fill in your secrets
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars            # paste in your Coolify token, GitHub token, repo name

# 2. Init (downloads the coolify + github providers)
terraform init

# 3. Plan (dry-run - shows what will be created without touching anything)
terraform plan

# 4. Apply (actually creates the 7 resources)
terraform apply
```

Roughly 5 seconds of API calls. After success, follow the printed "next steps" output — mostly the manual domain-set in Coolify UI mentioned above.

## Files

- `main.tf` — providers + all 7 resources
- `variables.tf` — input variables and cluster-wide UUIDs (server, GitHub App, destination)
- `outputs.tf` — UUIDs + URLs + a next-steps message
- `terraform.tfvars.example` — copy this to `terraform.tfvars` and fill in the three secrets
- `.gitignore` — keeps `terraform.tfvars`, `.terraform/`, and `*.tfstate` out of your commits

## Cleanup

```bash
terraform destroy    # removes the Coolify Project + Environment + Applications AND the GitHub secrets
```

Deleting the Coolify Project cascades to its Environments and Applications. `terraform destroy` handles the same by removing them in dependency order.

## Provider quirks (why some lines look weird)

If you read the HCL and wonder about the odd bits:

- **`git_repository = "byu-ml-capstone/repo"`** (not the full HTTPS URL). Coolify's API accepts the short form only.
- **`lifecycle { ignore_changes = [ports_exposes, name] }`** on the Applications. Coolify silently rewrites `ports_exposes` when `build_pack = "dockercompose"` (compose parses its own ports), and Coolify auto-generates the Application name from `<repo>:<branch>-<hash>`. Ignoring these fields keeps future `terraform plan` runs clean.
- **`ports_exposes = "8000"`** is set even though we `ignore_changes` on it. Coolify still validates the initial value on create; the ignore just tells Terraform not to fight Coolify's later rewrite.
- **No `domains` attribute on the Applications.** Coolify assigns an auto sslip.io domain at create time; setting a custom one requires a follow-up UI edit. See "What this does NOT do" above.

## When would you use this for real?

Right now: as a teaching prop. You already know how Coolify works from Setup Steps 1–11; this shows you the same setup as code. That mental shift — "click here, then here" → "declare this shape, let the tool make it happen" — is IaC in one sitting.

Once your class project is done, this file becomes reproducible infrastructure for your next project. Copy it, change `repo_name`, `terraform apply`, and you have a whole new deploy pipeline. Rinse for every side project you ever build on this cluster.

For team-scale work (multiple contributors, many Applications, drift detection, remote state), you'd graduate to real remote state (S3 backend, Terraform Cloud) and probably switch to a more polished provider ecosystem. For a one-person class project, this is exactly the right amount of tool.
