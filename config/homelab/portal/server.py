#!/usr/bin/env python3
"""Home Lab Portal: read-only status and inventory API for the home lab.

The service is deliberately dependency free (Python standard library only) so
that it can be built by a Home Manager module without a JavaScript toolchain.

Data sources, in order of authority:

* ``INVENTORY_PATH``  the checked-in declarative service inventory
* ``systemctl --user``  the actual state of the user-level units
* HTTP/TCP health probes against loopback and tailnet addresses
* ``tailscale status``/``tailscale serve status``  the access boundary
* OpenObserve  cross-host metrics for machines with no local probe here

Nothing in this service mutates system state: every endpoint is read-only.
Credentials are read at runtime from paths supplied by the module and are never
logged, echoed, or included in a response.
"""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

INVENTORY_PATH = os.environ["INVENTORY_PATH"]
STATIC_DIR = os.environ["STATIC_DIR"]
DOCS_DIR = os.environ.get("DOCS_DIR", "")
BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("BIND_PORT", "8090"))
SYSTEMCTL = os.environ.get("SYSTEMCTL_BIN", "/usr/bin/systemctl")
TAILSCALE = os.environ.get("TAILSCALE_BIN", "/usr/bin/tailscale")
OPENOBSERVE_ENV_FILE = os.environ.get("OPENOBSERVE_ENV_FILE", "")
OPENOBSERVE_BASE = os.environ.get("OPENOBSERVE_BASE", "")
OPENOBSERVE_ORG = os.environ.get("OPENOBSERVE_ORG", "default")

PROBE_TIMEOUT = float(os.environ.get("PROBE_TIMEOUT_SECONDS", "4"))
STATUS_CACHE_SECONDS = float(os.environ.get("STATUS_CACHE_SECONDS", "5"))
TAILSCALE_CACHE_SECONDS = 60.0

# Probes and CLI calls always talk to loopback or the tailnet. Ignore ambient
# proxy settings so an http_proxy in the unit environment cannot reroute them.
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

_STATIC_WHITELIST = {"index.html", "styles.css", "app.js", "markdown.js"}
_CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".md": "text/plain; charset=utf-8",
}
_DOC_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*\.md$")

_cache_lock = threading.Lock()
_status_cache: tuple[float, dict] | None = None
_tailscale_cache: tuple[float, dict] | None = None
_dns_cache: dict[str, tuple[float, bool]] = {}


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------


def run(cmd: list[str], timeout: float = 8.0) -> tuple[int, str, str]:
    """Run a command, never raising, and never echoing its arguments back."""
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError:
        return 127, "", "command not found"
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except Exception as exc:  # pragma: no cover - defensive
        return 1, "", type(exc).__name__


def load_inventory() -> dict:
    with open(INVENTORY_PATH, "r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_timestamp(value: str) -> str | None:
    """Keep systemd timestamps as opaque strings; the UI only displays them."""
    value = (value or "").strip()
    if not value or value in {"n/a", "[not set]"}:
        return None
    return value


# --------------------------------------------------------------------------
# Tailnet identity and access boundary
# --------------------------------------------------------------------------


def parse_serve_config(raw: str) -> dict:
    """Map locally configured Tailscale Service endpoints by short name.

    ``tailscale serve status`` reports the Serve config this machine holds. It
    proves the endpoint is configured locally; it does not prove that the
    service is defined or approved in the Tailscale admin console. That
    distinction is reported to the page instead of being guessed at.
    """
    try:
        data = json.loads(raw)
    except ValueError:
        return {}

    result: dict[str, dict] = {}
    for name, spec in (data.get("Services") or {}).items():
        endpoints = []
        for port, tcp in (spec.get("TCP") or {}).items():
            # `HTTPS: true` is a marker that a Web handler owns this port; the
            # handler itself is described by the Web block below, so emitting
            # it here too would double-count the endpoint.
            if not tcp.get("TCPForward"):
                continue
            endpoints.append(
                {
                    "port": int(port) if str(port).isdigit() else port,
                    "forward": tcp.get("TCPForward") or "",
                    "https_proxy": False,
                }
            )
        for web_name, web in (spec.get("Web") or {}).items():
            handler = ((web.get("Handlers") or {}).get("/") or {})
            endpoints.append(
                {
                    "port": 443,
                    "forward": handler.get("Proxy") or "",
                    "https_proxy": True,
                    "web": web_name,
                }
            )
        result[str(name).removeprefix("svc:")] = {
            "name": name,
            "endpoints": endpoints,
        }
    return result


def tailscale_info() -> dict:
    global _tailscale_cache
    now = time.monotonic()
    with _cache_lock:
        if _tailscale_cache and now - _tailscale_cache[0] < TAILSCALE_CACHE_SECONDS:
            return _tailscale_cache[1]

    info = {
        "available": False,
        "backend_state": "",
        "hostname": socket.gethostname(),
        "dns_name": "",
        "tailnet_suffix": "",
        "tailnet_ip": "",
        "online": False,
        "peer_count": 0,
        "peers_online": 0,
        "configured_services": [],
        "serve_config": {},
        "error": "",
    }

    rc, out, _ = run([TAILSCALE, "status", "--json"], timeout=10)
    if rc != 0:
        info["error"] = "tailscale status 不可用"
    else:
        try:
            data = json.loads(out)
        except ValueError:
            data = {}
            info["error"] = "tailscale status 返回了无法解析的数据"
        self_node = data.get("Self") or {}
        dns_name = (self_node.get("DNSName") or "").rstrip(".")
        ips = self_node.get("TailscaleIPs") or []
        ipv4 = next((ip for ip in ips if ":" not in ip), "")
        peers = list((data.get("Peer") or {}).values())
        info.update(
            available=bool(self_node),
            backend_state=data.get("BackendState") or "",
            hostname=self_node.get("HostName") or socket.gethostname(),
            dns_name=dns_name,
            tailnet_suffix=dns_name.split(".", 1)[1] if "." in dns_name else "",
            tailnet_ip=ipv4,
            online=(data.get("BackendState") == "Running"),
            peer_count=len(peers),
            peers_online=sum(1 for peer in peers if peer.get("Online")),
        )

    rc, out, _ = run([TAILSCALE, "serve", "status", "--json"], timeout=10)
    if rc == 0:
        serve_config = parse_serve_config(out)
        info["serve_config"] = serve_config
        info["configured_services"] = sorted(serve_config)

    with _cache_lock:
        _tailscale_cache = (now, info)
    return info


def substitute(value, placeholders: dict):
    """Replace {token} placeholders recursively over the inventory."""
    if isinstance(value, str):
        for token, replacement in placeholders.items():
            value = value.replace("{" + token + "}", replacement)
        return value
    if isinstance(value, list):
        return [substitute(item, placeholders) for item in value]
    if isinstance(value, dict):
        return {key: substitute(item, placeholders) for key, item in value.items()}
    return value


def placeholders_from(tailnet: dict) -> dict:
    return {
        "tailnet_ip": tailnet.get("tailnet_ip") or "127.0.0.1",
        "tailnet_suffix": tailnet.get("tailnet_suffix") or "<tailnet>.ts.net",
        "hostname": tailnet.get("hostname") or socket.gethostname(),
    }


def resolves(host: str) -> bool:
    """Whether a MagicDNS name resolves.

    A Tailscale Service name only resolves once the service is defined and the
    serving host approved in the Tailscale admin console. The local Serve
    config can exist before that, which is why this is reported separately
    from the local endpoint state instead of being inferred from it.
    """
    now = time.monotonic()
    cached = _dns_cache.get(host)
    if cached and now - cached[0] < TAILSCALE_CACHE_SECONDS:
        return cached[1]
    try:
        socket.getaddrinfo(host, None)
        result = True
    except OSError:
        result = False
    _dns_cache[host] = (now, result)
    return result


# --------------------------------------------------------------------------
# systemd and probes
# --------------------------------------------------------------------------


def systemd_states(units: list[str]) -> dict:
    if not units:
        return {}
    properties = (
        "Id,ActiveState,SubState,NRestarts,MemoryCurrent,ActiveEnterTimestamp,"
        "ExecMainStartTimestamp,UnitFileState"
    )
    rc, out, _ = run([SYSTEMCTL, "--user", "show", *units, "-p", properties], timeout=10)
    if rc != 0 and not out:
        return {unit: {"error": "systemctl 不可用"} for unit in units}

    states: dict[str, dict] = {}
    current: dict | None = None
    for line in out.splitlines():
        if not line.strip():
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key == "Id":
            if current and current.get("Id"):
                states[current["Id"]] = current
            current = {"Id": value}
        elif current is not None:
            current[key] = value
    if current and current.get("Id"):
        states[current["Id"]] = current
    return states


def summarize_unit(state: dict | None) -> dict:
    if not state:
        return {"known": False, "active": False, "state": "unknown"}
    if state.get("error"):
        return {"known": False, "active": False, "state": "unknown", "error": state["error"]}

    active_state = state.get("ActiveState", "unknown")
    sub_state = state.get("SubState", "")
    memory_raw = state.get("MemoryCurrent", "")
    memory_bytes = int(memory_raw) if memory_raw.isdigit() else None
    restarts_raw = state.get("NRestarts", "0")
    return {
        "known": True,
        "active": active_state == "active",
        "state": f"{active_state} ({sub_state})" if sub_state else active_state,
        "active_state": active_state,
        "sub_state": sub_state,
        "memory_bytes": memory_bytes,
        "restarts": int(restarts_raw) if restarts_raw.isdigit() else None,
        "since": parse_timestamp(state.get("ActiveEnterTimestamp", "")),
        "unit_file_state": state.get("UnitFileState", ""),
    }


def http_probe(url: str, expect: list[int] | None) -> dict:
    started = time.monotonic()
    request = urllib.request.Request(
        url, method="GET", headers={"User-Agent": "homelab-portal/1"}
    )
    try:
        with _OPENER.open(request, timeout=PROBE_TIMEOUT) as response:
            code = response.status
    except urllib.error.HTTPError as exc:
        code = exc.code
    except Exception as exc:
        return {
            "type": "http",
            "target": url,
            "ok": False,
            "error": type(exc).__name__,
            "latency_ms": round((time.monotonic() - started) * 1000),
        }

    latency = round((time.monotonic() - started) * 1000)
    ok = code in expect if expect else 200 <= code < 500
    return {
        "type": "http",
        "target": url,
        "ok": ok,
        "http_status": code,
        "latency_ms": latency,
    }


def tcp_probe(host: str, port: int) -> dict:
    started = time.monotonic()
    try:
        with socket.create_connection((host, int(port)), timeout=PROBE_TIMEOUT):
            pass
    except Exception as exc:
        return {
            "type": "tcp",
            "target": f"{host}:{port}",
            "ok": False,
            "error": type(exc).__name__,
            "latency_ms": round((time.monotonic() - started) * 1000),
        }
    return {
        "type": "tcp",
        "target": f"{host}:{port}",
        "ok": True,
        "latency_ms": round((time.monotonic() - started) * 1000),
    }


def run_probe(probe: dict, placeholders: dict) -> dict:
    probe = substitute(probe, placeholders)
    kind = probe.get("type")
    if kind == "http":
        return http_probe(probe["url"], probe.get("expect"))
    if kind == "tcp":
        return tcp_probe(probe["host"], probe["port"])
    return {"type": str(kind), "ok": False, "error": "不支持的探针类型"}


# --------------------------------------------------------------------------
# Host metrics
# --------------------------------------------------------------------------


def read_first_line(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.readline().strip()
    except OSError:
        return ""


def host_status(inventory: dict) -> dict:
    load1 = load5 = load15 = None
    running = total = None
    raw_load = read_first_line("/proc/loadavg")
    if raw_load:
        parts = raw_load.split()
        try:
            load1, load5, load15 = (float(parts[0]), float(parts[1]), float(parts[2]))
            running, total = (int(parts[3].split("/")[0]), int(parts[3].split("/")[1]))
        except (ValueError, IndexError):
            pass

    uptime_seconds = None
    raw_uptime = read_first_line("/proc/uptime")
    if raw_uptime:
        try:
            uptime_seconds = float(raw_uptime.split()[0])
        except (ValueError, IndexError):
            pass

    meminfo: dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as handle:
            for line in handle:
                key, _, rest = line.partition(":")
                value = rest.strip().split()
                if value and value[0].isdigit():
                    meminfo[key.strip()] = int(value[0]) * 1024
    except OSError:
        pass

    memory = None
    if meminfo.get("MemTotal"):
        total_bytes = meminfo["MemTotal"]
        available = meminfo.get("MemAvailable", meminfo.get("MemFree", 0))
        memory = {
            "total_bytes": total_bytes,
            "available_bytes": available,
            "used_bytes": max(total_bytes - available, 0),
            "used_percent": round(max(total_bytes - available, 0) / total_bytes * 100, 1),
            "swap_total_bytes": meminfo.get("SwapTotal", 0),
            "swap_free_bytes": meminfo.get("SwapFree", 0),
        }

    disks = []
    for entry in (inventory.get("hosts") or [{}])[0].get("dataPaths", []):
        path = entry.get("path")
        if not path:
            continue
        try:
            usage = shutil.disk_usage(path)
        except OSError:
            continue
        disks.append(
            {
                "path": path,
                "label": entry.get("label", path),
                "total_bytes": usage.total,
                "used_bytes": usage.used,
                "free_bytes": usage.free,
                "used_percent": round(usage.used / usage.total * 100, 1) if usage.total else 0.0,
            }
        )

    return {
        "hostname": socket.gethostname(),
        "kernel": platform.release(),
        "cpu_count": os.cpu_count(),
        "load1": load1,
        "load5": load5,
        "load15": load15,
        "load_percent": round(load1 / os.cpu_count() * 100, 1) if load1 and os.cpu_count() else None,
        "processes_running": running,
        "processes_total": total,
        "uptime_seconds": uptime_seconds,
        "memory": memory,
        "disks": disks,
    }


# --------------------------------------------------------------------------
# Cross-host view via OpenObserve
# --------------------------------------------------------------------------


def openobserve_auth() -> tuple[str, str] | None:
    if not OPENOBSERVE_ENV_FILE:
        return None
    try:
        with open(OPENOBSERVE_ENV_FILE, "r", encoding="utf-8") as handle:
            values = {}
            for line in handle:
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip()
    except OSError:
        return None
    email = values.get("ZO_ROOT_USER_EMAIL")
    password = values.get("ZO_ROOT_USER_PASSWORD")
    if not email or not password:
        return None
    return email, password


def openobserve_query(sql: str, stream_type: str = "metrics") -> list[dict]:
    auth = openobserve_auth()
    if auth is None or not OPENOBSERVE_BASE:
        raise RuntimeError("observability 凭据或端点未配置")

    now = int(time.time() * 1_000_000)
    window = int(os.environ.get("OPENOBSERVE_WINDOW_SECONDS", "900"))
    body = json.dumps(
        {
            "query": {
                "sql": sql,
                "start_time": now - window * 1_000_000,
                "end_time": now,
                "size": 50,
            }
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        f"{OPENOBSERVE_BASE}/api/{OPENOBSERVE_ORG}/_search?type={stream_type}",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": "Basic "
            + __import__("base64").b64encode(
                f"{auth[0]}:{auth[1]}".encode("utf-8")
            ).decode("ascii"),
        },
    )
    try:
        with _OPENER.open(request, timeout=PROBE_TIMEOUT + 4) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"observability 查询被拒绝 (HTTP {exc.code})") from exc
    except Exception as exc:
        raise RuntimeError(f"observability 查询失败 ({type(exc).__name__})") from exc
    return payload.get("hits") or []


def _index_hits(hits: list[dict], key: str, field: str) -> dict:
    result = {}
    for hit in hits:
        name = hit.get("host_name")
        if name:
            result[name] = hit.get(field)
    return result


def fleet_status(inventory: dict) -> dict:
    config = inventory.get("fleet") or {}
    result = {
        "enabled": bool(config.get("enabled")),
        "available": False,
        "reason": "",
        "window_seconds": int(os.environ.get("OPENOBSERVE_WINDOW_SECONDS", "900")),
        "hosts": [],
    }
    if not result["enabled"]:
        return result

    streams = config.get("streams") or {}
    load_stream = streams.get("load", "system_cpu_load_average_1m")
    memory_stream = streams.get("memory", "system_memory_usage")

    try:
        load_hits = openobserve_query(
            f'SELECT host_name, max(value) AS load1, max(_timestamp) AS last_seen '
            f'FROM "{load_stream}" GROUP BY host_name'
        )
        memory_hits = openobserve_query(
            f"SELECT host_name, max(value) AS used FROM \"{memory_stream}\" "
            f"WHERE state = 'used' GROUP BY host_name"
        )
    except RuntimeError as exc:
        result["reason"] = str(exc)
        return result

    loads = _index_hits(load_hits, "load1", "load1")
    seen = _index_hits(load_hits, "last_seen", "last_seen")
    memories = _index_hits(memory_hits, "used", "used")

    now_us = time.time() * 1_000_000
    local_name = socket.gethostname()
    hosts = []
    for name in sorted(set(loads) | set(seen)):
        last_seen = seen.get(name)
        age = round((now_us - last_seen) / 1_000_000) if last_seen else None
        hosts.append(
            {
                "host_name": name,
                "local": name == local_name,
                "load1": loads.get(name),
                "memory_used_bytes": memories.get(name),
                "last_seen_age_seconds": age,
                "reporting": age is not None and age <= result["window_seconds"],
            }
        )

    result["hosts"] = hosts
    result["available"] = True
    return result


# --------------------------------------------------------------------------
# Status assembly
# --------------------------------------------------------------------------


def build_service_status(inventory: dict, tailnet: dict, placeholders: dict) -> list[dict]:
    services = inventory.get("services") or []
    all_units: list[str] = []
    for service in services:
        for unit in (service.get("units") or []) + (service.get("extraUnits") or []):
            if unit not in all_units:
                all_units.append(unit)

    units = systemd_states(all_units)
    serve_config = tailnet.get("serve_config") or {}

    def evaluate(service: dict) -> dict:
        primary_units = service.get("units") or []
        extra_units = service.get("extraUnits") or []

        unit_details = [
            {"unit": unit, **summarize_unit(units.get(unit))} for unit in primary_units
        ]
        extra_details = [
            {"unit": unit, **summarize_unit(units.get(unit))} for unit in extra_units
        ]

        reasons: list[str] = []
        probe_result = None
        if service.get("health"):
            probe_result = run_probe(service["health"], placeholders)

        tailscale_name = (service.get("tailscale") or {}).get("service")
        serve_entry = serve_config.get(tailscale_name) if tailscale_name else None
        tailscale_ok = True
        tailscale_dns = None
        if tailscale_name:
            tailscale_ok = serve_entry is not None
            if not tailscale_ok:
                reasons.append(
                    f"本机未配置 Tailscale Service 端点 svc:{tailscale_name}"
                    "（tailscale-services 单元尚未成功应用）"
                )
            suffix = tailnet.get("tailnet_suffix") or ""
            if suffix:
                tailscale_dns = resolves(f"{tailscale_name}.{suffix}")

        if primary_units:
            inactive = [d["unit"] for d in unit_details if not d.get("active")]
            if inactive and len(inactive) == len(unit_details):
                state = "down"
                reasons.append("systemd 单元未运行: " + ", ".join(inactive))
            elif inactive:
                state = "degraded"
                reasons.append("部分单元未运行: " + ", ".join(inactive))
            else:
                state = "up"
        elif probe_result is not None:
            state = "up" if probe_result.get("ok") else "down"
        else:
            state = "unknown"

        if state != "down" and probe_result is not None and not probe_result.get("ok"):
            state = "degraded"
            reasons.append(f"健康探针失败: {probe_result.get('target')}")

        if state == "up" and not tailscale_ok:
            state = "degraded"

        return {
            "id": service.get("id"),
            "state": state,
            "reasons": reasons,
            "units": unit_details,
            "extra_units": extra_details,
            "probe": probe_result,
            "tailscale_served": tailscale_ok if tailscale_name else None,
            "tailscale_dns": tailscale_dns,
            "tailscale_endpoints": (serve_entry or {}).get("endpoints", []),
        }

    workers = min(8, max(1, len(services)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(evaluate, services))

    by_id = {r["id"]: r for r in results}
    for service in services:
        service["status"] = by_id.get(service.get("id"), {"state": "unknown", "reasons": []})
    return services


def compute_status() -> dict:
    inventory = load_inventory()
    tailnet = tailscale_info()
    placeholders = placeholders_from(tailnet)

    started = time.monotonic()
    services = build_service_status(inventory, tailnet, placeholders)
    host = host_status(inventory)
    fleet = fleet_status(inventory)
    elapsed = round((time.monotonic() - started) * 1000)

    counts = {"up": 0, "degraded": 0, "down": 0, "unknown": 0}
    for service in services:
        counts[service["status"].get("state", "unknown")] = (
            counts.get(service["status"].get("state", "unknown"), 0) + 1
        )

    return {
        "generated_at": time.time(),
        "generated_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "duration_ms": elapsed,
        "tailnet": tailnet,
        "host": host,
        "services": [
            {
                "id": service.get("id"),
                "name": service.get("name"),
                "category": service.get("category"),
                **service["status"],
            }
            for service in services
        ],
        "counts": counts,
        "fleet": fleet,
    }


def cached_status() -> dict:
    global _status_cache
    now = time.monotonic()
    with _cache_lock:
        if _status_cache and now - _status_cache[0] < STATUS_CACHE_SECONDS:
            return _status_cache[1]
    status = compute_status()
    with _cache_lock:
        _status_cache = (now, status)
    return status


# --------------------------------------------------------------------------
# Docs
# --------------------------------------------------------------------------


def list_docs() -> list[dict]:
    if not DOCS_DIR or not os.path.isdir(DOCS_DIR):
        return []
    docs = []
    for name in sorted(os.listdir(DOCS_DIR)):
        if not _DOC_NAME_RE.match(name):
            continue
        title = name
        try:
            with open(os.path.join(DOCS_DIR, name), "r", encoding="utf-8") as handle:
                for line in handle:
                    if line.startswith("# "):
                        title = line[2:].strip()
                        break
        except OSError:
            continue
        docs.append({"name": name, "title": title})
    return docs


def read_doc(name: str) -> str | None:
    if not DOCS_DIR or not _DOC_NAME_RE.match(name):
        return None
    path = os.path.join(DOCS_DIR, name)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return None


# --------------------------------------------------------------------------
# HTTP layer
# --------------------------------------------------------------------------


class Handler(BaseHTTPRequestHandler):
    server_version = "homelab-portal/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep journald output small and secret-free
        if os.environ.get("PORTAL_ACCESS_LOG") == "1":
            super().log_message(fmt, *args)

    # -- helpers ---------------------------------------------------------
    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_json(self, payload, code: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send(code, body, "application/json; charset=utf-8")

    def _send_static(self, name: str) -> None:
        if name not in _STATIC_WHITELIST:
            self._send_json({"error": "not found"}, 404)
            return
        path = os.path.join(STATIC_DIR, name)
        try:
            with open(path, "rb") as handle:
                body = handle.read()
        except OSError:
            self._send_json({"error": "not found"}, 404)
            return
        extension = os.path.splitext(name)[1]
        self._send(200, body, _CONTENT_TYPES.get(extension, "application/octet-stream"))

    # -- routing ---------------------------------------------------------
    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path

        try:
            if route in ("/", "/index.html"):
                self._send_static("index.html")
            elif route in ("/styles.css", "/app.js", "/markdown.js"):
                self._send_static(route.lstrip("/"))
            elif route == "/api/health":
                self._send_json({"ok": True, "service": "homelab-portal"})
            elif route == "/api/inventory":
                inventory = load_inventory()
                placeholders = placeholders_from(tailscale_info())
                self._send_json(
                    {
                        "inventory": substitute(inventory, placeholders),
                        "docs": list_docs(),
                    }
                )
            elif route == "/api/status":
                self._send_json(cached_status())
            elif route == "/api/docs":
                self._send_json({"docs": list_docs()})
            elif route.startswith("/api/docs/"):
                name = urllib.parse.unquote(route[len("/api/docs/") :])
                content = read_doc(name)
                if content is None:
                    self._send_json({"error": "not found"}, 404)
                else:
                    self._send(200, content.encode("utf-8"), _CONTENT_TYPES[".md"])
            else:
                self._send_json({"error": "not found"}, 404)
        except Exception as exc:  # pragma: no cover - defensive
            self._send_json({"error": type(exc).__name__}, 500)


def main() -> None:
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler)
    server.daemon_threads = True
    print(
        f"homelab-portal: listening on http://{BIND_HOST}:{BIND_PORT} "
        f"(inventory={INVENTORY_PATH})",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
