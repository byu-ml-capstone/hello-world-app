# hello-world-app

Minimal FastAPI starter for the ML Capstone class deployment lab. Use this to walk through the Coolify setup + push-to-deploy pipeline without getting entangled in ML plumbing.

## Layout

Repo root = orchestration + docs. Each subdirectory = one service (self-contained code + Dockerfile + deps).

```
hello-world-app/
├── docker-compose.yaml           # production compose (Coolify reads this)
├── docker-compose.override.yml   # local-dev only (host port bind); ignored by Coolify
├── test-local.sh                 # docker compose up + smoke-test both services
├── README.md
├── .github/workflows/ci.yml      # 3-job pipeline: test → deploy-staging → deploy-prod
│
├── hello/                        # PUBLIC service — Traefik-routed
│   ├── main.py                   #   FastAPI wiring + endpoints
│   ├── greetings.py              #   content + logic (split out from main.py on purpose)
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── conftest.py               #   makes hello/ the pytest rootdir
│   └── tests/test_api.py         #   six tests; /time test mocks the sidecar
│
└── time/                         # INTERNAL sidecar — no external routing
    ├── main.py                   #   FastAPI returning UTC time on /now
    ├── requirements.txt
    └── Dockerfile
```

Stand-in for real-world sidecars (database, cache, worker, local model server). The `hello/` service talks to `time` via `http://time:8001` — Compose's built-in DNS resolves the service name over the internal network. Only `hello` gets a public URL; add more sidecars the same way (their own subdirectory, `expose:` in compose, no `${SERVICE_FQDN_*}`).

## Architecture

Two services in one Compose project:

```
Browser / curl
      │  http://<domain>            (via Coolify Traefik in prod, or host:8000 locally)
      ▼
┌─────────────────┐        http://time:8001/now       ┌───────────────┐
│  app (FastAPI)  │  ─────────────────────────────▶   │  time (FastAPI) │
│  port 8000      │  internal Docker DNS by service    │  port 8001      │
│  PUBLIC         │  name — no external routing        │  INTERNAL       │
└─────────────────┘                                    └───────────────┘
```

Only `app` gets a public URL. `time` is reachable only from other services on the Compose network. Swap `time` for a real database / cache / worker later — the calling pattern is the same.

## Endpoints

| Method | Path | Returns |
|---|---|---|
| GET | `/` | `{"hello": "Hello, world"}` — or `{"hello": "Hola, mundo"}` etc. with `?lang=es\|fr\|de\|ja` |
| GET | `/languages` | `{"supported": ["de", "en", "es", "fr", "ja"]}` |
| GET | `/health` | `{"ok": true, "version": "0.1.1"}` |
| GET | `/time` | `{"from_time_service": {"utc": "<iso timestamp>"}}` — proxies the `time` sidecar |

## Local test

```bash
./test-local.sh
```

Or run without Docker:

```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

Then `curl http://127.0.0.1:8000/` and `curl http://127.0.0.1:8000/health`.

## Unit tests

```bash
pip install fastapi 'uvicorn[standard]' pydantic httpx pytest
pytest tests/ -v
```

## Deploy

This app is deploy-ready for the ml-capstone cluster. Steps:

1. Fork or copy this directory into your team's GitHub repo.
2. Follow **`student-guide.md` → Part B → Setup: Sign in and create your Coolify Applications** (in the top-level of `ml-capstone-platform`) to wire up the Coolify Applications + GitHub secrets.
3. Push to `staging` branch → GitHub Actions runs unit tests → fires the Coolify staging webhook → your app is live at `https://<team>-staging.ml-capstone.cs.byu.edu`.
4. Merge `staging` → `main` → same flow to prod at `https://<team>.ml-capstone.cs.byu.edu`.

Bump `APP_VERSION` in `greetings.py` on each meaningful change so you can eyeball `/health` after a deploy and confirm it's the new build.

## After you've mastered this

`hello-world-app` is the on-ramp for the BYU CS ml-capstone class. Once you have the Coolify deploy pipeline working end-to-end and understand every piece of this repo, the natural next step is [`byu-ml-capstone/sentiment-test-app`](https://github.com/byu-ml-capstone/sentiment-test-app) — a fuller build-out with the same shape (FastAPI + Docker + tests + 3-job CI/CD) but adds:

- Modular Python (separate `config.py`, `device.py`, `schemas.py`, `llm_client.py`, `local_classifier.py`)
- Both a remote LLM path (via LiteLLM) and a local HuggingFace model path
- GPU detection + graceful CPU fallback
- Deep integration tests via `integration-test.sh`
- Base+app Docker image split for fast rebuilds
- Docker Compose runtime config

**You're not meant to fork `sentiment-test-app` directly.** Instead, `student-guide.md` Section 1 walks you through growing your templated `hello-world-app` into something structurally like `sentiment-test-app`, one file at a time. That way you understand every piece.
