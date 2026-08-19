#!/usr/bin/env bash
# Quick local check: build, run detached, curl a couple endpoints.
# Leaves the container running so you can keep poking at it — stop
# it yourself with the command printed at the end.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=hello-world-app:local
CONTAINER=hello-world-local

echo "=== building ==="
docker build -t "$IMAGE" .

echo
echo "=== running (detached, --rm) ==="
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --rm --name "$CONTAINER" -p 8000:8000 "$IMAGE" >/dev/null

# Wait for /health to come up
for _ in $(seq 1 15); do
    if curl -sSf http://127.0.0.1:8000/health >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

echo
echo "=== GET / ==="
curl -sS http://127.0.0.1:8000/
echo
echo "=== GET /health ==="
curl -sS http://127.0.0.1:8000/health
echo
echo
echo "Container '$CONTAINER' is running on http://127.0.0.1:8000."
echo "Hit it with more curls, tail logs (docker logs -f $CONTAINER),"
echo "or stop it with:  docker stop $CONTAINER"
