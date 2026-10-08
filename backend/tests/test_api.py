"""Tests for the internal data service.

Everything involving Postgres is mocked at the NotesDAO boundary. That is the
payoff of extracting the DAO: a test says "when the DAO returns these rows,
the route returns them" without mocking psycopg's connect / cursor /
context-manager stack, and nothing here needs a database running.

Compare frontend/tests/test_api.py, which mocks at the BackendClient boundary
for exactly the same reason one layer up.
"""

from unittest.mock import patch

import psycopg
from fastapi.testclient import TestClient

import main
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# Basic routes — no database involved
# ---------------------------------------------------------------------------


def test_root_identifies_the_service():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["service"] == "backend"


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert "version" in body


def test_health_does_not_touch_the_database():
    """Liveness must not depend on Postgres.

    `frontend` waits on this via depends_on: service_healthy. If it queried
    the database, a slow Postgres start would block the whole stack.
    """
    with patch.object(main.notes_dao, "list_all") as m:
        r = client.get("/health")
    assert r.status_code == 200
    m.assert_not_called()


def test_now_returns_an_iso_timestamp():
    r = client.get("/now")
    assert r.status_code == 200
    assert "utc" in r.json()
    assert "T" in r.json()["utc"]


# ---------------------------------------------------------------------------
# /notes — mocked at the DAO boundary
# ---------------------------------------------------------------------------


def test_notes_list_returns_dao_output():
    fake_rows = [
        {"id": 1, "body": "first", "created_at": "2026-08-20T12:00:00+00:00"},
        {"id": 2, "body": "second", "created_at": "2026-08-20T12:01:00+00:00"},
    ]
    with patch.object(main.notes_dao, "list_all", return_value=fake_rows):
        r = client.get("/notes")
    assert r.status_code == 200
    assert r.json() == fake_rows


def test_notes_create_returns_dao_output():
    fake_row = {
        "id": 42,
        "body": "hello persistence",
        "created_at": "2026-08-20T12:00:00+00:00",
    }
    with patch.object(main.notes_dao, "insert", return_value=fake_row) as m:
        r = client.post("/notes", json={"body": "hello persistence"})
    assert r.status_code == 201
    assert r.json() == fake_row
    m.assert_called_once_with("hello persistence")


def test_notes_create_rejects_a_missing_body():
    """Pydantic validates the request before any route code runs."""
    r = client.post("/notes", json={})
    assert r.status_code == 422


def test_notes_list_returns_503_when_db_unreachable():
    with patch.object(
        main.notes_dao, "list_all", side_effect=psycopg.OperationalError("boom")
    ):
        r = client.get("/notes")
    assert r.status_code == 503
    assert "db unreachable" in r.json()["detail"]


def test_notes_create_returns_503_when_db_unreachable():
    with patch.object(
        main.notes_dao, "insert", side_effect=psycopg.OperationalError("boom")
    ):
        r = client.post("/notes", json={"body": "x"})
    assert r.status_code == 503


# ---------------------------------------------------------------------------
# /admin/reset — env-gated destructive endpoint. The gate lives HERE, in the
# service that owns the data, not in the one that takes the request.
# ---------------------------------------------------------------------------


def test_admin_reset_forbidden_when_disabled():
    with patch.object(main, "ADMIN_RESET_ENABLED", False):
        r = client.post("/admin/reset")
    assert r.status_code == 403
    assert "disabled" in r.json()["detail"]


def test_admin_reset_calls_dao_when_enabled():
    with patch.object(main, "ADMIN_RESET_ENABLED", True), patch.object(
        main.notes_dao, "reset"
    ) as m:
        r = client.post("/admin/reset")
    assert r.status_code == 200
    assert r.json()["ok"] is True
    m.assert_called_once_with()
