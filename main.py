import json
import urllib.error
import urllib.request

from fastapi import FastAPI
from pydantic import BaseModel

from greetings import APP_VERSION, GREETINGS, get_greeting

app = FastAPI(title="hello-world-app", version=APP_VERSION)

# URL of the internal `time` sidecar defined in docker-compose.yaml. `time`
# is the Compose service name — Docker's built-in DNS on the compose network
# resolves it to the sidecar container. Only THIS app is Traefik-routed and
# public; `time` is internal-only.
TIME_SERVICE_URL = "http://time:8001"


class HealthResponse(BaseModel):
    ok: bool
    version: str


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
