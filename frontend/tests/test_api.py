"""Tests for the public service.

Everything involving data is mocked at the BackendClient boundary. That is
the payoff of having a client object: a test says "when the backend returns
these notes, the route returns them" without constructing an httpx response,
and nothing here knows the backend speaks HTTP.

Compare backend/tests/test_api.py, which mocks at the NotesDAO boundary for
exactly the same reason one layer down.
"""

from unittest.mock import patch

from fastapi.testclient import TestClient

import main
from backend_client import BackendError
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# Basic routes — no external dependencies
# ---------------------------------------------------------------------------


def test_hello_default():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json() == {"hello": "Hello, world"}


def test_hello_spanish():
    r = client.get("/", params={"lang": "es"})
    assert r.status_code == 200
    assert r.json() == {"hello": "Hola, mundo"}


def test_hello_unknown_lang_falls_back_to_default():
    r = client.get("/", params={"lang": "xx"})
    assert r.status_code == 200
    assert r.json() == {"hello": "Hello, world"}


def test_languages_lists_all_supported():
    r = client.get("/languages")
    assert r.status_code == 200
    body = r.json()
    assert "en" in body["supported"]
    assert "es" in body["supported"]


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert "version" in body


def test_health_does_not_call_the_backend():
    """/health is liveness only.

    If it called the backend, a slow backend start would fail Coolify's
    health gate and roll back a perfectly good deploy.
    """
    with patch.object(main.backend, "health") as m:
        r = client.get("/health")
    assert r.status_code == 200
    m.assert_not_called()


# ---------------------------------------------------------------------------
# /ready — the one that IS allowed to fail when a dependency is down
# ---------------------------------------------------------------------------


def test_ready_ok_when_backend_healthy():
    with patch.object(main.backend, "health", return_value={"ok": True}):
        r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["ok"] is True


def test_ready_503_when_backend_down():
    with patch.object(
        main.backend, "health", side_effect=BackendError("backend unreachable: x")
    ):
        r = client.get("/ready")
    assert r.status_code == 503
    assert "backend not ready" in r.json()["detail"]


# ---------------------------------------------------------------------------
# /time — proxied from the backend
# ---------------------------------------------------------------------------


def test_time_endpoint_wraps_backend_response():
    with patch.object(
        main.backend, "now", return_value={"utc": "2026-08-20T12:34:56+00:00"}
    ):
        r = client.get("/time")
    assert r.status_code == 200
    assert r.json() == {"from_backend": {"utc": "2026-08-20T12:34:56+00:00"}}


def test_time_endpoint_503_when_backend_unreachable():
    with patch.object(
        main.backend, "now", side_effect=BackendError("backend unreachable: x")
    ):
        r = client.get("/time")
    assert r.status_code == 503


# ---------------------------------------------------------------------------
# /notes — mocked at the client boundary. No database, no HTTP, no SQL.
# ---------------------------------------------------------------------------


def test_notes_list_returns_backend_output():
    fake_rows = [
        {"id": 1, "body": "first", "created_at": "2026-08-20T12:00:00+00:00"},
        {"id": 2, "body": "second", "created_at": "2026-08-20T12:01:00+00:00"},
    ]
    with patch.object(main.backend, "list_notes", return_value=fake_rows):
        r = client.get("/notes")
    assert r.status_code == 200
    assert r.json() == fake_rows


def test_notes_create_passes_body_through():
    fake_row = {
        "id": 42,
        "body": "hello persistence",
        "created_at": "2026-08-20T12:00:00+00:00",
    }
    with patch.object(main.backend, "create_note", return_value=fake_row) as m:
        r = client.post("/notes", json={"body": "hello persistence"})
    assert r.status_code == 201
    assert r.json() == fake_row
    m.assert_called_once_with("hello persistence")


def test_notes_list_503_when_backend_unreachable():
    with patch.object(
        main.backend,
        "list_notes",
        side_effect=BackendError("backend unreachable: connection refused"),
    ):
        r = client.get("/notes")
    assert r.status_code == 503
    assert "unreachable" in r.json()["detail"]


def test_notes_list_503_when_backend_returns_5xx():
    """A backend 503 (its database is down) stays a 503 for our caller."""
    with patch.object(
        main.backend,
        "list_notes",
        side_effect=BackendError("backend returned 503: db unreachable", status=503),
    ):
        r = client.get("/notes")
    assert r.status_code == 503


# ---------------------------------------------------------------------------
# /admin/reset — the gate lives in the backend, so a 403 passes through
# ---------------------------------------------------------------------------


def test_admin_reset_passes_through_backend_403():
    with patch.object(
        main.backend,
        "reset_notes",
        side_effect=BackendError("backend returned 403: disabled", status=403),
    ):
        r = client.post("/admin/reset")
    assert r.status_code == 403


def test_admin_reset_returns_backend_result():
    with patch.object(
        main.backend, "reset_notes", return_value={"ok": True, "message": "done"}
    ) as m:
        r = client.post("/admin/reset")
    assert r.status_code == 200
    assert r.json()["ok"] is True
    m.assert_called_once_with()
