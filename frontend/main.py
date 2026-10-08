"""Public service — the only one Traefik routes to.

This service holds no database driver, no Postgres password, and no SQL. When
it needs data it asks `backend` over the internal Docker network. That is the
whole point of the split: the service exposed to the internet cannot reach the
database even if something here goes wrong.

Routes stay thin. Each one handles HTTP framing — status codes, error
mapping — and delegates the actual work to `greetings` (local content) or
`backend` (anything involving data). See backend_client.py for why that
boundary is worth having.
"""

import logging
import os

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from backend_client import BackendClient, BackendError
from greetings import APP_VERSION, GREETINGS, get_greeting

log = logging.getLogger("uvicorn.error")

# URL of the internal `backend` service defined in docker-compose.yaml.
# `backend` is the Compose service name — Docker's built-in DNS on the compose
# network resolves it to that container. Only THIS service is Traefik-routed
# and public; `backend` is internal-only.
BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:8001")

# Every call to the backend goes through this client.
backend = BackendClient(BACKEND_URL)

app = FastAPI(title="hello-world-app", version=APP_VERSION)


class HealthResponse(BaseModel):
    ok: bool
    version: str


class NoteIn(BaseModel):
    body: str


def _passthrough(e: BackendError) -> HTTPException:
    """Map a backend failure onto a status code for our caller.

    A backend that answered with a client error (4xx) is reporting something
    about the request, so that status is passed through unchanged. Anything
    else — unreachable, timed out, 5xx — is a dependency failure from our
    caller's point of view, which is a 503.
    """
    if e.status is not None and 400 <= e.status < 500:
        return HTTPException(status_code=e.status, detail=str(e))
    return HTTPException(status_code=503, detail=str(e))


@app.get("/")
def hello(lang: str = "en"):
    return {"hello": get_greeting(lang)}


@app.get("/languages")
def languages():
    return {"supported": sorted(GREETINGS.keys())}


@app.get("/health", response_model=HealthResponse)
def health():
    """Liveness only — deliberately does NOT call the backend.

    Coolify gates deploys on this. If it depended on the backend being up, a
    slow backend start would look like a broken frontend and the deploy would
    be rolled back for the wrong reason. Use /ready to check the whole stack.
    """
    return HealthResponse(ok=True, version=APP_VERSION)


@app.get("/ready")
def ready():
    """Readiness — the frontend AND everything it depends on.

    Separate from /health on purpose: this one is allowed to fail when the
    backend is down, which is exactly what makes it useful for answering
    "is the stack actually working" rather than "is this process alive".
    """
    try:
        backend.health()
    except BackendError as e:
        raise HTTPException(
            status_code=503, detail=f"backend not ready: {e}"
        ) from e
    return {"ok": True, "frontend": APP_VERSION, "backend": "ok"}


@app.get("/time")
def current_time():
    """Fetch the current UTC time from the internal `backend` service."""
    try:
        return {"from_backend": backend.now()}
    except BackendError as e:
        raise _passthrough(e) from e


@app.get("/notes")
def list_notes():
    """Notes live in the database, which only `backend` can reach."""
    try:
        return backend.list_notes()
    except BackendError as e:
        raise _passthrough(e) from e


@app.post("/notes", status_code=201)
def create_note(note: NoteIn):
    try:
        return backend.create_note(note.body)
    except BackendError as e:
        raise _passthrough(e) from e


@app.post("/admin/reset")
def admin_reset():
    """Drop and recreate the notes table. Destructive.

    The gate lives in the backend (ALLOW_ADMIN_RESET), not here — the service
    that owns the data owns the decision about who may destroy it. A 403 from
    the backend passes straight through.
    """
    try:
        return backend.reset_notes()
    except BackendError as e:
        raise _passthrough(e) from e
