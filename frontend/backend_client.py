"""Client for the internal `backend` service.

This is the frontend's half of the same pattern `NotesDAO` gives the backend:
one object owns one boundary, and the routes in main.py stay thin.

  - `backend/notes_dao.py` hides SQL behind Python method calls.
  - `frontend/backend_client.py` hides HTTP behind Python method calls.

Neither one lets its transport details leak into a route handler. A route in
`frontend/main.py` calls `backend.list_notes()` and never mentions a URL, a
status code, or a JSON body — exactly as a backend route calls
`notes_dao.list_all()` and never mentions a cursor.

Three payoffs, the same three the DAO gets:

  1. Routes read like a contract instead of plumbing.
  2. Tests patch these methods (`patch("main.backend.list_notes", ...)`)
     instead of mocking httpx's request/response/context-manager stack.
  3. Swapping the transport is a one-file change. Move the backend behind
     gRPC or a message queue and `main.py` does not change.

`BackendError` is the single exception type routes have to know about: every
failure reaching the backend — connection refused, timeout, a 5xx — arrives
as one thing, so the HTTP mapping in main.py is one `except` clause rather
than a pile of httpx-specific cases.
"""

import httpx


class BackendError(RuntimeError):
    """The backend could not be reached, or answered with an error.

    Carries `status` when the backend did answer (so a route can pass a 404
    through as a 404), and None when the request never got that far.
    """

    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


class BackendClient:
    """Typed wrapper over the backend's HTTP API."""

    def __init__(self, base_url: str, timeout: float = 5.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    # -- the single place HTTP errors become BackendError --------------------

    def _request(self, method: str, path: str, **kwargs):
        url = f"{self.base_url}{path}"
        try:
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.request(method, url, **kwargs)
        except httpx.RequestError as e:
            # Never reached the backend at all: DNS, connection refused,
            # timeout. The backend's own status is unknown, hence status=None.
            raise BackendError(f"backend unreachable: {e}") from e
        if resp.status_code >= 400:
            raise BackendError(
                f"backend returned {resp.status_code}: {resp.text[:200]}",
                status=resp.status_code,
            )
        return resp.json()

    # -- notes ---------------------------------------------------------------

    def list_notes(self) -> list[dict]:
        return self._request("GET", "/notes")

    def create_note(self, body: str) -> dict:
        return self._request("POST", "/notes", json={"body": body})

    def reset_notes(self) -> dict:
        return self._request("POST", "/admin/reset")

    # -- the demo endpoint ---------------------------------------------------

    def now(self) -> dict:
        return self._request("GET", "/now")

    def health(self) -> dict:
        return self._request("GET", "/health")
