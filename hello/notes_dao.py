"""Data Access Object for the `notes` table.

Encapsulates every SQL statement and Postgres detail so main.py can talk
about notes in terms of Python dicts instead of cursors and tuples.
Pulling this out has three payoffs:

  1. Routes stay thin. `main.py` reads like an HTTP contract, not a SQL
     script. As the app grows this matters — the alternative is one
     giant `main.py` where routing, validation, and data access all
     live in the same functions.
  2. Testing is easier. Tests can patch NotesDAO methods (e.g.
     `patch("main.notes_dao.list_all", return_value=[...])`) instead
     of mocking psycopg's connect / cursor / context-manager stack.
     Faster to write, less brittle when psycopg internals change.
  3. Swapping the storage backend is a one-file change. Want SQLite
     for tests? Point NotesDAO at a different URL. Want SQLAlchemy /
     an ORM? Replace this file, leave main.py alone.

For production traffic you'd hold a connection pool
(psycopg_pool.ConnectionPool) on the DAO instead of opening a new
connection per call — a class-level pool created once at startup, with
each method borrowing a connection from it. Skipped here to keep the
teaching surface small; upgrade when your load justifies it.
"""

import psycopg

CREATE_NOTES_SQL = """
CREATE TABLE IF NOT EXISTS notes (
    id         SERIAL       PRIMARY KEY,
    body       TEXT         NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
)
"""


class NotesDAO:
    """One-connection-per-call DAO backed by Postgres."""

    def __init__(self, database_url: str):
        self.database_url = database_url

    # -- schema management ----------------------------------------------------

    def ensure_schema(self) -> None:
        """Idempotently create the notes table. Called at app startup.

        Uses `CREATE TABLE IF NOT EXISTS`, so it's safe to run on every
        boot: no-op if the table exists, creates it if not. Handles both
        the fresh-volume case and the "existing volume with no schema"
        case (e.g. after a failed deploy that half-initialized the data
        directory).
        """
        with psycopg.connect(self.database_url) as conn, conn.cursor() as cur:
            cur.execute(CREATE_NOTES_SQL)

    def reset(self) -> None:
        """Drop and recreate the notes table.

        Destructive — loses every row. Only wired up to the env-gated
        admin endpoint in main.py. Useful when the schema needs to
        change in a non-additive way (rename column, change type, drop
        column) and you'd rather blow away the data than write a real
        migration. In production you'd write an Alembic migration
        instead; this is a class-project shortcut.
        """
        with psycopg.connect(self.database_url) as conn, conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS notes")
            cur.execute(CREATE_NOTES_SQL)

    # -- queries --------------------------------------------------------------

    def list_all(self) -> list[dict]:
        with psycopg.connect(self.database_url) as conn, conn.cursor() as cur:
            cur.execute("SELECT id, body, created_at FROM notes ORDER BY id")
            rows = cur.fetchall()
        return [
            {"id": r[0], "body": r[1], "created_at": r[2].isoformat()}
            for r in rows
        ]

    def insert(self, body: str) -> dict:
        with psycopg.connect(self.database_url) as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO notes (body) VALUES (%s) RETURNING id, created_at",
                (body,),
            )
            row = cur.fetchone()
        return {"id": row[0], "body": body, "created_at": row[1].isoformat()}
