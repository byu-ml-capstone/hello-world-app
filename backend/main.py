"""Internal API service — owns the database, exposes it over HTTP.

This is the only service that talks to Postgres. `frontend` cannot reach the
database at all; it asks this service, over the internal Docker network, and
this service decides what the data looks like. Nothing outside the Compose
stack can reach either one directly.

Why split it this way:

  1. One owner for the data. Every read and write goes through the same DAO,
     so there is exactly one place where the schema is known. Two services
     both holding a `DATABASE_URL` is how schemas drift.
  2. The service exposed to the internet holds no credentials. `frontend` has
     no Postgres password, no database driver, and no SQL — so a bug there
     cannot leak or corrupt data.
  3. Each layer can change independently. Swap Postgres for something else and
     only this service changes. Redesign the UI and only `frontend` changes.

Routes here stay thin on purpose: they handle HTTP framing (status codes,
error mapping) and delegate the actual SQL to NotesDAO. See notes_dao.py for
why that boundary is worth having.
"""

import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from notes_dao import NotesDAO

APP_VERSION = "0.1.0"

log = logging.getLogger("uvicorn.error")

# Postgres connection string, injected via docker-compose.yaml. `db` is the
# Compose service name and Docker's built-in DNS resolves it to the postgres
# container on the internal network — never publicly reachable.
DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://appuser:apppass@db:5432/appdb"
)

# All Postgres access goes through the DAO.
notes_dao = NotesDAO(DATABASE_URL)

# Env-gated admin reset. Off by default — `docker-compose.override.yml` turns
# it on for local development only. In Coolify you would add
# ALLOW_ADMIN_RESET=true to the Application's env vars, use it, then remove it.
ADMIN_RESET_ENABLED = os.environ.get("ALLOW_ADMIN_RESET", "").lower() in (
    "1",
    "true",
    "yes",
)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Startup: apply any pending schema migrations.

    Reads backend/migrations/*.sql, runs each file whose name isn't already
    recorded in the `_migrations` tracking table, records the newly-applied
    ones. The same code runs on staging AND production on every deploy, so
    the schema stays in sync across environments automatically.

    This belongs here rather than in `frontend` for the same reason the SQL
    does: the service that owns the data owns its shape.

    OperationalError (db not reachable) is swallowed so /health can still
    respond during a partial outage; the data routes surface 503 instead.
    """
    try:
        notes_dao.apply_migrations()
    except psycopg.OperationalError as e:
        log.warning("startup: db unreachable, skipping migrations: %s", e)
    yield


app = FastAPI(title="backend-service", version=APP_VERSION, lifespan=lifespan)


class HealthResponse(BaseModel):
    ok: bool
    version: str


class NoteIn(BaseModel):
    body: str


@app.get("/")
def root():
    return {
        "service": "backend",
        "hint": "GET /notes, POST /notes, GET /now",
    }


@app.get("/health", response_model=HealthResponse)
def health():
    """Liveness only — deliberately does NOT touch the database.

    Compose and Coolify both gate on this, and `frontend` waits for it via
    depends_on. If it required a working database, a slow Postgres start
    would read as a broken backend.
    """
    return HealthResponse(ok=True, version=APP_VERSION)


@app.get("/now")
def now():
    """Current UTC time. Stands in for real backend work."""
    return {"utc": datetime.now(timezone.utc).isoformat()}


@app.get("/notes")
def list_notes():
    try:
        return notes_dao.list_all()
    except psycopg.OperationalError as e:
        raise HTTPException(status_code=503, detail=f"db unreachable: {e}") from e


@app.post("/notes", status_code=201)
def create_note(note: NoteIn):
    try:
        return notes_dao.insert(note.body)
    except psycopg.OperationalError as e:
        raise HTTPException(status_code=503, detail=f"db unreachable: {e}") from e


@app.post("/admin/reset")
def admin_reset():
    """Drop and recreate the notes table. Destructive.

    Env-gated by ALLOW_ADMIN_RESET so it cannot be hit by accident on a
    production Application.
    """
    if not ADMIN_RESET_ENABLED:
        raise HTTPException(
            status_code=403,
            detail="admin reset disabled; set ALLOW_ADMIN_RESET=true to enable",
        )
    try:
        notes_dao.reset()
    except psycopg.OperationalError as e:
        raise HTTPException(status_code=503, detail=f"db unreachable: {e}") from e
    return {"ok": True, "message": "notes table dropped and recreated (empty)"}
