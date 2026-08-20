#!/usr/bin/env bash
# Quick local check via Docker Compose: build + start BOTH services (app +
# time sidecar), curl a few endpoints including /time which exercises the
# app -> time inter-service call. Leaves both containers running so you can
# keep poking at them — stop them yourself with the command printed at the
# end.
set -euo pipefail
cd "$(dirname "$0")"

# Provide a value for the ${SERVICE_FQDN_HELLO} interpolation in
# docker-compose.yaml so compose doesn't warn about an undefined var. In
# production Coolify populates this with the real domain.
export SERVICE_FQDN_HELLO="http://localhost:8000"

echo "=== building + starting (docker compose, detached) ==="
docker compose down --remove-orphans >/dev/null 2>&1 || true
docker compose up -d --build

# Wait for the app's /health to come up (time sidecar has its own healthcheck
# and is a `depends_on: service_healthy` for app, so if app is up, time is too)
echo -n "waiting for /health "
for _ in $(seq 1 30); do
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
echo "=== GET /time (proves app -> time sidecar comms) ==="
curl -sS http://127.0.0.1:8000/time
echo
echo
echo "Both services are running:"
echo "  hello → http://localhost:8000 (public API — Traefik-routed in prod)"
echo "  time  → internal only         (reachable from hello at http://time:8001)"
echo
echo "Hit them with more curls, tail logs (docker compose logs -f),"
echo "or stop everything with:  docker compose down"
