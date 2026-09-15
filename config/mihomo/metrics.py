#!/usr/bin/env python3
"""Sample the mihomo controller API and forward OTLP metrics to the collector.

Arguments (in order): controller-base-url, controller-secret-file, otlp-endpoint.

The script emits OTLP/HTTP JSON gauges for traffic, memory, and connection
count. The local OpenTelemetry Collector owns authentication, batching, and
export to OpenObserve, so this script needs no ingestion credentials.
"""

import json
import pathlib
import sys
import time
import urllib.request


def main() -> int:
    base, secret_file, otlp_endpoint = sys.argv[1:4]
    secret = pathlib.Path(secret_file).read_text(encoding="utf-8").strip()
    headers = {"Authorization": f"Bearer {secret}"}

    def first_json(path: str, timeout: float = 4.0):
        request = urllib.request.Request(base + path, headers=headers)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            for raw in response:
                text = raw.decode("utf-8").strip()
                if text:
                    return json.loads(text)
        return None

    def snapshot_json(path: str, timeout: float = 4.0):
        request = urllib.request.Request(base + path, headers=headers)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))

    now = str(time.time_ns())
    points: list[dict] = []

    def gauge(name: str, unit: str, value) -> None:
        points.append(
            {
                "name": name,
                "unit": unit,
                "gauge": {
                    "dataPoints": [
                        {"asInt": str(int(value)), "timeUnixNano": now}
                    ]
                },
            }
        )

    for sampler in (
        ("traffic", _traffic_point),
        ("memory", _memory_point),
        ("connections", _connections_point),
    ):
        name, sampler = sampler
        try:
            sampler(gauge, first_json, snapshot_json)
        except Exception as error:  # noqa: BLE001 - a failed sample must not abort the others
            print(f"mihomo-metrics: {name} sample failed: {error}", file=sys.stderr)

    if not points:
        return 0

    payload = {
        "resourceMetrics": [
            {
                "resource": {
                    "attributes": [
                        {"key": "service.name", "value": {"stringValue": "mihomo"}},
                        {"key": "service.namespace", "value": {"stringValue": "longred"}},
                        {"key": "deployment.environment", "value": {"stringValue": "home-lab"}},
                    ]
                },
                "scopeMetrics": [
                    {
                        "scope": {"name": "mihomo.metrics", "version": "1"},
                        "metrics": points,
                    }
                ],
            }
        ]
    }
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        otlp_endpoint,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        response.read()
    return 0


def _traffic_point(gauge, first_json, _snapshot_json) -> None:
    traffic = first_json("/traffic")
    if not traffic:
        return
    gauge("mihomo_traffic_up_bytes_per_second", "By/s", traffic.get("up", 0))
    gauge("mihomo_traffic_down_bytes_per_second", "By/s", traffic.get("down", 0))
    gauge("mihomo_traffic_up_total_bytes", "By", traffic.get("upTotal", 0))
    gauge("mihomo_traffic_down_total_bytes", "By", traffic.get("downTotal", 0))


def _memory_point(gauge, first_json, _snapshot_json) -> None:
    memory = first_json("/memory")
    if not memory:
        return
    gauge("mihomo_memory_inuse_bytes", "By", memory.get("inuse", 0))


def _connections_point(gauge, _first_json, snapshot_json) -> None:
    connections = snapshot_json("/connections")
    gauge("mihomo_connections", "1", len(connections.get("connections", [])))


if __name__ == "__main__":
    raise SystemExit(main())
