-- Runs ONCE on the first startup of the postgres container.
--
-- The official `postgres` image auto-executes any *.sql or *.sh files placed
-- in /docker-entrypoint-initdb.d/ ONLY when the data directory is empty
-- (i.e., a fresh install). On subsequent restarts, the entrypoint sees the
-- existing data directory and skips this file entirely — that's exactly why
-- the `db-data` volume in docker-compose.yaml makes rows persist across
-- `docker compose down` + `docker compose up` cycles.
--
-- If you change this schema after the volume has data, this file will NOT
-- re-run. To pick up schema changes you either (a) blow the volume away
-- with `docker compose down -v` and start over (dev only!), or (b) write
-- a proper migration (Alembic, sqlx, plain SQL over psql) and run it
-- separately.

CREATE TABLE IF NOT EXISTS notes (
    id         SERIAL       PRIMARY KEY,
    body       TEXT         NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
