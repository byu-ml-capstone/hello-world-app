import json
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


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


def test_time_endpoint_wraps_response_from_time_sidecar():
    # The /time endpoint calls http://time:8001/now, which only resolves
    # when docker compose is running. For unit tests we mock the network
    # call — this is the standard pattern for testing code that depends
    # on a service boundary without spinning up the other side.
    fake_body = json.dumps({"utc": "2026-08-20T12:34:56+00:00"}).encode()
    fake_response = MagicMock()
    fake_response.read.return_value = fake_body
    fake_response.__enter__.return_value = fake_response
    fake_response.__exit__.return_value = False

    with patch("main.urllib.request.urlopen", return_value=fake_response):
        r = client.get("/time")

    assert r.status_code == 200
    assert r.json() == {"from_time_service": {"utc": "2026-08-20T12:34:56+00:00"}}
