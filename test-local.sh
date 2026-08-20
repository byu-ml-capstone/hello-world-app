#!/usr/bin/env bash
# Quick local check via Docker Compose: build + start ALL services (hello,
# time sidecar, and db), curl a few endpoints — including /time which
# exercises the hello -> time call and /notes which round-trips through
# the Postgres db. Leaves everything running so you can keep poking at
# it; stop with the command printed at the end.
set -euo pipefail
cd "$(dirname "$0")"

# Provide a value for the ${SERVICE_FQDN_HELLO} interpolation in
# docker-compose.yaml so compose doesn't warn about an undefined var. In
# production Coolify populates this with the real domain.
export SERVICE_FQDN_HELLO="http://localhost:8000"

echo "=== building + starting (docker compose, detached) ==="
docker compose down --remove-orphans >/dev/null 2>&1 || true
docker compose up -d --build

# Wait for hello's /health. Its `depends_on` requires time + db both
# healthy first, so once hello answers /health everything is up.
echo -n "waiting for /health "
for _ in $(seq 1 60); do
    if curl -sSf http://127.0.0.1:8000/health >/dev/null 2>&1; then
        echo " ready"
        break
    fi
    echo -n "."
    sleep 1
done

echo
echo "=== GET / ==="
curl -sS http://127.0.0.1:8000/
echo
echo "=== GET /health ==="
curl -sS http://127.0.0.1:8000/health
echo
echo "=== GET /time (proves hello -> time sidecar comms) ==="
curl -sS http://127.0.0.1:8000/time
echo
echo "=== POST /notes (proves hello -> db round-trip; data now persists) ==="
curl -sS -X POST http://127.0.0.1:8000/notes \
    -H 'Content-Type: application/json' \
    -d '{"body":"smoke-test note from test-local.sh"}'
echo
echo "=== GET /notes (reads back everything in the notes table) ==="
curl -sS http://127.0.0.1:8000/notes
echo
echo
echo "All three services are running:"
echo "  hello → http://localhost:8000 (public API — Traefik-routed in prod)"
echo "  time  → internal only         (reachable from hello at http://time:8001)"
echo "  db    → internal Postgres     (reachable from hello at postgres://...@db:5432)"
echo
echo "Proof of persistence: POST another /notes row, run 'docker compose down',"
echo "then 'docker compose up -d' — GET /notes shows every row you inserted."
echo "Only 'docker compose down -v' (the -v drops volumes) wipes the data."
echo
echo "Hit more endpoints, tail logs (docker compose logs -f),"
echo "or stop everything with:  docker compose down"
