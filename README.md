# hello-world-app

Minimal FastAPI starter for the ML Capstone class deployment lab. Use this to walk through the Coolify setup + push-to-deploy pipeline without getting entangled in ML plumbing.

## Layout

Repo root = orchestration + docs. Each subdirectory = one service (self-contained code + Dockerfile + deps).

```
hello-world-app/
├── docker-compose.yaml           # production compose (Coolify reads this)
├── docker-compose.override.yml   # local-dev only (host port bind); ignored by Coolify
├── smoke-test.sh                 # docker compose up + smoke-test everything; also `./smoke-test.sh URL` to test a deployed instance
├── README.md
├── .gitignore                    # Python/Docker noise + terraform secrets and state
├── .github/workflows/ci.yml      # 3-job pipeline: test → deploy-staging → deploy-prod
│
├── frontend/                     # PUBLIC service — Traefik-routed
│   ├── main.py                   #   FastAPI wiring + endpoints (thin)
│   ├── greetings.py              #   content + logic (split out from main.py on purpose)
│   ├── backend_client.py         #   BackendClient — every call to the backend goes here
│   ├── requirements.txt          #   no database driver — see backend/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── conftest.py               #   makes frontend/ the pytest rootdir
│   └── tests/test_api.py         #   16 tests; mocked at the client boundary
│
├── backend/                      # INTERNAL service — owns the database
│   ├── main.py                   #   FastAPI wiring + endpoints (thin)
│   ├── notes_dao.py              #   NotesDAO — the only SQL in the repo
│   ├── migrations/               #   *.sql files — applied on startup in filename order
│   │   └── 001_create_notes.sql  #   initial schema; add 002_*.sql etc. as you evolve it
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── conftest.py               #   makes backend/ the pytest rootdir
│   └── tests/test_api.py         #   11 tests; mocked at the DAO boundary
│
└── terraform/                    # NOT a service — provisions the Coolify side
    ├── main.tf                   #   the resources: project, 2 envs, 2 apps, 3 GitHub secrets
    ├── variables.tf              #   every input, what it means, which have class defaults
    ├── outputs.tf                #   URLs + UUIDs printed after `apply`
    ├── terraform.tfvars.example  #   copy to terraform.tfvars and fill in 4 values
    ├── .terraform.lock.hcl       #   pins provider versions + checksums — committed on purpose
    ├── .gitignore                #   keeps terraform.tfvars (real tokens) and *.tfstate out of git
    └── README.md                 #   the deeper walkthrough, incl. why domains stay manual
```

`frontend/` is the only public service. `backend/` holds your application logic
and is the only service that touches the database — it is internal-only,
reachable just from `frontend`. Note the symmetry: each service has exactly one
file that owns its outward boundary (`backend_client.py`, `notes_dao.py`) and a
`main.py` that stays thin because of it. There's no `db/` subdirectory — the Postgres sidecar in `docker-compose.yaml` uses the stock `postgres:16-alpine` image directly. Postgres is a generic storage service; the backend owns the schema and materializes it at startup via a FastAPI lifespan hook in `backend/main.py`. That's the modern Django/Rails/Alembic convention: db container = dumb storage, app codebase = schema source of truth. Add more services the same way: their own subdirectory (if they need one) or just an `image:` line in compose, `expose:` for the port, no `${SERVICE_FQDN_*}` so Coolify keeps them internal-only.

`terraform/` is the odd one out — it isn't a service and nothing in it ships inside a container. It describes the Coolify and GitHub resources your app needs *around* it: the Project, the two Environments, the two Applications, and the three Actions secrets. You can ignore it entirely and click through the Coolify UI instead; see [Provisioning with Terraform](#provisioning-with-terraform) below.

## Architecture

```
Browser / curl
      │  http://<domain>          (Coolify Traefik in prod, host:8000 locally)
      ▼
┌────────────────────┐
│ frontend (FastAPI) │  PUBLIC — port 8000
│                    │  serves pages and the HTTP API
│ backend_client.py  │  no database driver, no SQL, no credentials
└──────────┬─────────┘
           │  http://backend:8001     Docker DNS by service name
           ▼
┌────────────────────┐
│ backend  (FastAPI) │  INTERNAL — port 8001
│                    │  application logic; owns the data
│ notes_dao.py       │  the only file with SQL in it
└──────────┬─────────┘
           │  postgres://appuser:apppass@db:5432/appdb
           ▼
┌────────────────────┐
│   db (postgres)    │  INTERNAL — port 5432
│                    │  persistent volume: db-data
│                    │  → survives `docker compose down`
└────────────────────┘  → wiped only by `docker compose down -v`
```

**One direction, one owner per layer.** A request for data goes
frontend → backend → db and the answer comes back the same way. The
frontend never talks to Postgres: it has no driver installed, no password,
and no SQL anywhere in it. That is deliberate, and it is the shape your own
project should take.

Why it matters beyond tidiness:

- **The service exposed to the internet holds no credentials.** A bug in
  `frontend` cannot leak or corrupt data it has no way to reach.
- **One owner for the schema.** Every read and write goes through one DAO in
  one service. Two services both holding a `DATABASE_URL` is how schemas drift.
- **Layers change independently.** Swap Postgres for something else and only
  `backend` changes. Rebuild the UI and only `frontend` changes.

Only `frontend` gets a public URL. `backend` and `db` are reachable only from other services on the Compose network. Coolify isolates volumes per-Application, so staging and prod each get their own `db-data` — they never share data.

### The three services

| Service | Built from | Port | Public? | What it is |
|---|---|---|---|---|
| `frontend` | `./frontend` (FastAPI) | 8000 | **yes** | The service users reach. Serves every endpoint below. For anything involving data it calls `backend` through `backend_client.py`. No database access of its own. |
| `backend` | `./backend` (FastAPI) | 8001 | no | Application logic and the **only** service that touches Postgres. All SQL lives in its `notes_dao.py`. Also serves `/now`, standing in for real backend work. |
| `db` | `postgres:16-alpine` | 5432 | no | Postgres. Data lives on the named volume `db-data`. |

**How they find each other.** Compose gives every service a DNS name matching its key, so `frontend` reaches the backend at `http://backend:8001`, and `backend` reaches the database at `db:5432`. No IP addresses, no port juggling — that's why `backend` and `db` declare `expose:` rather than `ports:`, making them reachable *only* from inside the Compose network.

**Why `frontend` uses `expose:` too.** The cluster server is shared, so binding a host port would collide with every other student. Coolify's Traefik routes to the container directly. Locally, `docker-compose.override.yml` adds the `ports:` mapping that puts it on `localhost:8000`.

**How `frontend` gets its public URL.** Referencing `${SERVICE_FQDN_FRONTEND}` in the compose file is what tells Coolify to generate a domain and wire up Traefik. Don't declare that variable — just reference it. The name follows the service (`frontend` → `SERVICE_FQDN_FRONTEND`).

**Startup order.** The chain is declared the same way it runs: `backend` waits on `db`, and `frontend` waits on `backend`, both with `condition: service_healthy`. A cold `docker compose up` therefore starts Postgres, waits for it to accept connections, starts the backend, waits for it to answer, then starts the frontend — reliable instead of a race. Note `frontend` does *not* declare `depends_on: db`; the database is the backend's dependency, not its own.

**Liveness vs readiness.** Both services' health checks hit `/health`, which deliberately does **not** touch anything downstream — `frontend`'s `/health` does not call the backend, and `backend`'s `/health` does not query Postgres. Coolify gates deploys on these, and a check that failed whenever a dependency was slow would roll back good deploys. To ask "is the whole stack working", use `GET /ready` on the frontend, which is allowed to fail.

**Environment variables** (all set in `docker-compose.yaml`):

| Variable | Service | Purpose |
|---|---|---|
| `BACKEND_URL` | `frontend` | `http://backend:8001` — where the frontend sends every data request |
| `APP_URL` | `frontend` | Set to `${SERVICE_FQDN_FRONTEND}` — the reference that triggers Coolify's routing |
| `DATABASE_URL` | `backend` | `postgresql://appuser:apppass@db:5432/appdb`. **Only** the backend gets this |
| `ALLOW_ADMIN_RESET` | `backend` | Gates `POST /admin/reset`. On the backend because the service that owns the data owns the decision to destroy it. Set only in `docker-compose.override.yml`, so the destructive endpoint is local-only by default |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `db` | `appuser` / `apppass` / `appdb` |

## Endpoints

Every example below is runnable. Locally the base URL is `http://localhost:8000`; deployed it's your Coolify domain. Set it once:

```bash
BASE=http://localhost:8000
# BASE=http://<your-repo>-staging.ml-capstone.cs.byu.edu    # deployed staging (VPN)
```

### `GET /` — greeting

```bash
curl -s $BASE/
# {"hello":"Hello, world"}

curl -s "$BASE/?lang=es"
# {"hello":"Hola, mundo"}
```

Takes an optional `?lang=` of `en`, `es`, `fr`, `de`, or `ja`. An unsupported code falls back to English rather than erroring.

### `GET /languages` — what `?lang=` accepts

```bash
curl -s $BASE/languages
# {"supported":["de","en","es","fr","ja"]}
```

### `GET /health` — liveness + version

```bash
curl -s $BASE/health
# {"ok":true,"version":"0.1.1"}
```

**This endpoint gates your deploys.** Coolify polls it after starting a new container: 200 and the new version takes over, non-200 and the old container keeps serving. Bump `APP_VERSION` in `frontend/greetings.py` and you can watch a deploy land by curling this.

### `GET /ready` — the whole stack, not just this process

```bash
curl -s $BASE/ready
# {"ok":true,"frontend":"0.1.1","backend":"ok"}
# {"detail":"backend not ready: backend unreachable: ..."}   -> HTTP 503
```

Unlike `/health`, this one calls the backend and is *allowed* to fail. Use it to answer "is the stack working", and `/health` for "is this process alive". Keeping them separate is why a slow backend start cannot roll back a good frontend deploy.

### `GET /time` — proxied from the backend

```bash
curl -s $BASE/time
# {"from_backend":{"utc":"2026-09-23T22:18:04.336421+00:00"}}
```

`frontend` calls `http://backend:8001/now` over the Compose network. If this works, service-to-service networking works.

### `GET /notes` — read the database, through the backend

```bash
curl -s $BASE/notes
# []                      (empty until you POST one)
# [{"id":1,"body":"first note","created_at":"2026-09-23T22:18:04.470242+00:00"}]
```

### `POST /notes` — write to the database, through the backend

```bash
curl -s -X POST $BASE/notes \
  -H 'Content-Type: application/json' \
  -d '{"body":"first note"}'
# {"id":1,"body":"first note","created_at":"2026-09-23T22:18:04.470242+00:00"}
```

Returns **201 Created**. `body` is required — omitting it gives FastAPI's validation error:

```bash
curl -s -X POST $BASE/notes -H 'Content-Type: application/json' -d '{}'
# HTTP 422
# {"detail":[{"type":"missing","loc":["body","body"],"msg":"Field required","input":{}}]}
```

Rows survive `docker compose down` and every redeploy, because they live on the `db-data` volume — that is the point of this endpoint existing.

**Follow the call path**, because it is the pattern to copy. The route in `frontend/main.py` calls `backend.create_note(...)` and returns the result — it names no URL and no status code. `frontend/backend_client.py` turns that into `POST http://backend:8001/notes`. The route in `backend/main.py` calls `notes_dao.insert(...)` — no cursor, no table name. `backend/notes_dao.py` turns that into the actual `INSERT`. Each layer talks to the next in its own vocabulary, and each boundary is one file you can mock in a test or replace wholesale.

### `POST /admin/reset` — drop and recreate the table

```bash
curl -s -X POST $BASE/admin/reset
# {"ok":true,...}                                                      (local, env var set)
# {"detail":"admin reset disabled; set ALLOW_ADMIN_RESET=true to enable"}   -> HTTP 403
```

**Destructive — it drops the `notes` table and every row in it.** Gated behind `ALLOW_ADMIN_RESET=true` **on the backend**, which only `docker-compose.override.yml` sets, so it is local-only unless you deliberately add the variable in Coolify. The gate lives in the backend because the service that owns the data owns the decision to destroy it; the frontend just passes the resulting 403 through. Useful for resetting state while working on migrations; not something to leave enabled on a deployed app.

## Smoke test

```bash
./smoke-test.sh                                             # local: builds + starts + tests
./smoke-test.sh http://your-app.ml-capstone.cs.byu.edu      # remote: tests a deployed instance
```

Or run a single service without Docker. The frontend needs the backend running
to answer anything data-related, so this is mostly useful for the greeting
routes:

```bash
cd frontend
python -m pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Then `curl http://127.0.0.1:8000/` and `curl http://127.0.0.1:8000/health`. For the full chain use `docker compose up` — getting three services and their startup order right by hand is exactly the work compose is doing for you.

## Unit tests

Two suites, one per service. Neither needs Docker or a database.

```bash
python -m pip install fastapi 'uvicorn[standard]' pydantic httpx 'psycopg[binary]' pytest

cd frontend && pytest tests/ -v    # 16 tests — mocks at the BackendClient boundary
cd ../backend && pytest tests/ -v  # 11 tests — mocks at the NotesDAO boundary
```

That split is the payoff of the two boundary objects. The frontend tests never construct an HTTP response; the backend tests never construct a database cursor. Each suite describes what its routes do with whatever the layer below returns, which is why they stay short and stop breaking for unrelated reasons.

CI runs both — see `.github/workflows/ci.yml`. A failure in either blocks the deploy.

## Deploy

This app is deploy-ready for the ml-capstone cluster. Steps:

1. Fork or copy this directory into your team's GitHub repo.
2. Follow **`student-guide.md` → Part B → Setup: Create your repo, then sign in and create your Coolify Applications** (in the top-level of `ml-capstone-platform`) to wire up the Coolify Applications + GitHub secrets.
3. Push to `staging` branch → GitHub Actions runs unit tests → fires the Coolify staging webhook → your app is live at `http://<your-repo>-staging.ml-capstone.cs.byu.edu`.
4. Merge `staging` → `main` → same flow to prod at `http://<your-repo>.ml-capstone.cs.byu.edu`.

> **`http://`, not `https://`.** The CS wildcard certificate covers one level under `cs.byu.edu`, and these hostnames are two levels deep, so student apps are routed on the HTTP entrypoint only. An `https://` request gets `503 no available server` rather than a certificate warning. Traffic is encrypted at the VPN layer.
>
> The hostname comes from your **repository name**, not your team name.

Bump `APP_VERSION` in `frontend/greetings.py` on each meaningful change so you can eyeball `/health` after a deploy and confirm it's the new build.

## Provisioning with Terraform

`terraform/` creates everything on the Coolify side in one command: the Project, both Environments, both Applications (with auto-deploy off, since GitHub Actions drives deploys), and all three GitHub Actions secrets. It's the alternative to clicking through Steps 4–9 of the student guide.

### What you need first

1. **Terraform 1.5+** — `brew install hashicorp/tap/terraform`, `winget install -e --id Hashicorp.Terraform`, or [the Linux packages](https://developer.terraform.io/terraform/install).
2. **A Coolify API token.** Switch to *your own team* in Coolify's team switcher first — the token is scoped to whichever team is active, and that decides where your Applications get created. Then Coolify wordmark → **Keys & Tokens → API Tokens → + New Token**, permissions **`write`** and **`deploy`**. Copy it immediately; it's shown once. (There's no `root` option outside the instructor's Root Team, and you don't need one.)
3. **A GitHub token** with `repo` scope — `gh auth token` if you have the GitHub CLI.
4. **Your Coolify server UUID.** Every team has its own server record — all named `ml-capstone`, all pointing at the same machine, each with a different UUID — so there's no shared value:

   ```bash
   curl -H "Authorization: Bearer <your-coolify-token>" \
     https://ml-capstone-admin.cs.byu.edu/api/v1/servers
   ```

   Exactly one comes back. Copy its `uuid`.

### Run it

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars        # fill in the four values above

terraform init                  # downloads providers, verifies against the lock file
terraform plan                  # READ THIS before applying
terraform apply                 # type: yes
```

`plan` should end with **`Plan: 7 to add, 0 to change, 0 to destroy`**. Reading it before applying is most of the point of using Terraform at all — you get to see exactly what will happen while it's still free to change your mind.

The outputs give you both URLs and the Application UUIDs.

### What it created

| Resource | Where to see it |
|---|---|
| `coolify_project` | Coolify → your team → Projects |
| `coolify_environment` ×2 | inside that project: `production` and `staging` |
| `coolify_application` ×2 | one per environment, tracking `main` and `staging` |
| `github_actions_secret` ×3 | GitHub → repo → Settings → Secrets and variables → Actions |

### The one manual step

**Terraform cannot set your domains.** Coolify's API won't accept per-service domains on a Docker Compose application, so for each of the two Applications: **Access → gear icon on "1 configured domain"** (or the **Domains** tab) → under service `frontend`, set `http://<your-repo>-staging.ml-capstone.cs.byu.edu` (or the prod equivalent) → **Save**. Delete the auto-generated `sslip.io` placeholder and the `www.` variant.

Do this **before** your first deploy. Traefik bakes its routing labels into a container when it starts, so a domain added afterwards leaves your URL returning `404 page not found` until you hit **Redeploy**.

### Files

| File | What it's for |
|---|---|
| `main.tf` | The resources themselves — read this one to see what maps to what in the UI |
| `variables.tf` | Every input, what it means, and which have class defaults |
| `outputs.tf` | What gets printed after `apply` |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` and fill in |
| `.terraform.lock.hcl` | Pins exact provider versions + checksums. **Committed on purpose** so everyone gets identical providers |
| `.gitignore` | Keeps `terraform.tfvars` (real tokens) and `*.tfstate` out of git |

`terraform.tfvars` holds two live credentials. It's gitignored — never commit it.

### Tearing it down

```bash
terraform destroy
```

Removes the Project, both Applications, and the three GitHub secrets. Your repo and its code are untouched. See [`terraform/README.md`](terraform/README.md) for the deeper walkthrough, including why the domain step resists automation.
