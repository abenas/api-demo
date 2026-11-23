"""Origem governada: chama o endpoint protegido assinando com SigV4 a role desta Lambda."""
import json
import os
import statistics
import time
import urllib.error
import urllib.request

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

URL = os.environ["PROTECTED_URL"]
REGION = os.environ["AWS_REGION"]
SESSION = boto3.Session()


def _call(body: bytes):
    creds = SESSION.get_credentials().get_frozen_credentials()
    req = AWSRequest(method="POST", url=URL, data=body,
                     headers={"Content-Type": "application/json", "User-Agent": "api-demo-caller/1.0"})
    SigV4Auth(creds, "execute-api", REGION).add_auth(req)

    start = time.perf_counter()
    http_req = urllib.request.Request(URL, data=body, headers=dict(req.headers), method="POST")
    try:
        with urllib.request.urlopen(http_req, timeout=10) as resp:
            status, text = resp.status, resp.read().decode()
    except urllib.error.HTTPError as err:
        status, text = err.code, err.read().decode()
    return status, text, (time.perf_counter() - start) * 1000


def lambda_handler(event, _context):
    event = event or {}
    iterations = max(1, min(int(event.get("iterations", 1)), 500))
    body = json.dumps({"a": event.get("a", 2), "b": event.get("b", 3)}).encode()

    latencies, statuses, last = [], {}, None
    for _ in range(iterations):
        status, text, ms = _call(body)
        latencies.append(ms)
        statuses[str(status)] = statuses.get(str(status), 0) + 1
        last = {"status": status, "body": text}

    ordered = sorted(latencies)
    return {
        "endpoint": URL,
        "iterations": iterations,
        "statuses": statuses,
        "latency_ms": {
            "min": round(ordered[0], 1),
            "p50": round(statistics.median(ordered), 1),
            "p95": round(ordered[max(0, int(len(ordered) * 0.95) - 1)], 1),
            "max": round(ordered[-1], 1),
        },
        "last_response": last,
    }
