import json
import logging
import os
import urllib.error
import urllib.request
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from greetings import APP_VERSION, GREETINGS, get_greeting

log = logging.getLogger("uvicorn.error")

# URL of the internal `time` sidecar defined in docker-compose.yaml. `time`
# is the Compose service name — Docker's built-in DNS on the compose network
# resolves it to the sidecar container. Only THIS app is Traefik-routed and
# public; `time` is internal-only.
TIME_SERVICE_URL = "http://time:8001"

# Postgres connection string, injected via docker-compose.yaml. Same
# service-name-as-DNS pattern — `db` resolves to the postgres sidecar
# container on the Compose network. Never publicly reachable.
DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://appuser:apppass@db:5432/appdb"
)

# The `notes` table schema. Kept in code so the app can idempotently
# ensure the table exists at startup (see the lifespan hook below). The
# same schema also lives in db/init.sql for the fresh-volume case, but
# init.sql only runs on postgres's first boot ever — if the data directory
# gets initialized (even partially) with no `notes` table, init.sql
# doesn't re-run and the app is stuck. The lifespan hook covers that gap.
CREATE_NOTES_SQL = """
CREATE TABLE IF NOT EXISTS notes (
    id         SERIAL       PRIMARY KEY,
    body       TEXT         NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
)
"""


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Startup: idempotently ensure the notes table exists.

    Real apps use proper migrations (Alembic, sqlx-migrate, Prisma, etc.).
    For a teaching demo, `CREATE TABLE IF NOT EXISTS` at startup is enough
    and self-heals the "existing volume with no schema" case that init.sql
    can't recover from on its own.

    OperationalError (db not reachable) is swallowed so /health can still
    respond during a partial outage; /notes will surface 503 on request.
    """
    try:
        with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
            cur.execute(CREATE_NOTES_SQL)
        log.info("startup: notes table verified/created")
    except psycopg.OperationalError as e:
        log.warning("startup: db unreachable, skipping schema check: %s", e)
    yield


app = FastAPI(title="hello-world-app", version=APP_VERSION, lifespan=lifespan)


class HealthResponse(BaseModel):
    ok: bool
    version: str


class NoteIn(BaseModel):
    body: str


@app.get("/")
def hello(lang: str = "en"):
    return {"hello": get_greeting(lang)}


@app.get("/languages")
def languages():
    return {"supported": sorted(GREETINGS.keys())}


@app.get("/health", response_model=HealthResponse)
def health():
    return HealthResponse(ok=True, version=APP_VERSION)


@app.get("/time")
def current_time():
    """Fetch the current UTC time from the internal `time` sidecar.

    Demonstrates the multi-service pattern: services in the same Compose
    project reach each other by service name over the Docker network.
    Swap `time` for a real database, cache, or worker later — the calling
    pattern is the same.
    """
    try:
        with urllib.request.urlopen(f"{TIME_SERVICE_URL}/now", timeout=3) as resp:
            body = json.loads(resp.read())
        return {"from_time_service": body}
    except urllib.error.URLError as e:
        return {"error": "time service unreachable", "detail": str(e)}


# ---------------------------------------------------------------------------
# /notes — persistent storage demo backed by the `db` (postgres) sidecar.
#
# Rows written here survive `docker compose down` + `docker compose up`
# because the postgres data directory is mounted on the named volume
# `db-data` declared in docker-compose.yaml. Only `docker compose down -v`
# (or an explicit `docker volume rm`) removes the data.
#
# Connection-per-request is fine for a teaching example. For real load you
# would use a pool (psycopg_pool.ConnectionPool) held in the lifespan
# above alongside the schema check.
# ---------------------------------------------------------------------------


@app.get("/notes")
def list_notes():
    try:
        with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id, body, created_at FROM notes ORDER BY id")
            rows = cur.fetchall()
    except psycopg.OperationalError as e:
        raise HTTPException(status_code=503, detail=f"db unreachable: {e}") from e
    return [
        {"id": r[0], "body": r[1], "created_at": r[2].isoformat()}
        for r in rows
    ]


@app.post("/notes", status_code=201)
def create_note(note: NoteIn):
    try:
        with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO notes (body) VALUES (%s) RETURNING id, created_at",
                (note.body,),
            )
            row = cur.fetchone()
    except psycopg.OperationalError as e:
        raise HTTPException(status_code=503, detail=f"db unreachable: {e}") from e
    return {"id": row[0], "body": note.body, "created_at": row[1].isoformat()}
