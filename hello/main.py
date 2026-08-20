import json
import os
import urllib.error
import urllib.request

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from greetings import APP_VERSION, GREETINGS, get_greeting

app = FastAPI(title="hello-world-app", version=APP_VERSION)

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
# would use a pool (psycopg_pool.ConnectionPool) held in a FastAPI lifespan.
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
