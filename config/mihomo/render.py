#!/usr/bin/env python3
"""Render the mihomo runtime config from the checked-in template and secrets.

Arguments (in order):
  template, subscription-url-file, custom-proxies-file, custom-rules-file,
  override-url, controller-endpoint, state-dir

The subscription URL and any node credentials never enter the Nix store: the
URL is read from a runtime file and the rendered config is written with mode
0600 into the systemd StateDirectory.

The subscription only carries proxy nodes. Proxy groups, rule-providers and
rules come from an external Clash override document (the override-hub
ACL4SSR profile). That document is fetched at render time and cached in the
state directory; when the network is unavailable the last good copy is reused,
and when there is no copy at all the script falls back to a minimal
PROXY/DIRECT rule set so the unit still starts.

An optional runtime rules file is prepended to the merged rules, matching the
Clash Party `+rules` override semantics.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import secrets
import sys
import urllib.request

FETCH_TIMEOUT = 20

FALLBACK_RULES = """rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
  - DOMAIN-SUFFIX,ts.net,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
  - GEOSITE,category-ads-all,REJECT
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
"""


def read_optional(path: str) -> str:
    try:
        return pathlib.Path(path).read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""


def read_raw(path: str) -> str:
    try:
        return pathlib.Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def custom_proxies_block(path: str) -> str:
    """Return the runtime custom proxies as a top-level `proxies:` section.

    Custom nodes are top-level rather than a provider because mihomo cannot
    resolve a dialer-proxy target that lives in the same file provider.
    """
    text = read_raw(path).strip()
    if not text:
        return "proxies: []\n"
    if re.match(r"^proxies\s*:", text):
        return text + "\n"
    return "proxies:\n" + text + "\n"


def split_top_level(text: str) -> dict[str, str]:
    """Split a YAML document into its column-zero `key:` sections verbatim."""
    sections: dict[str, str] = {}
    key: str | None = None
    buffer: list[str] = []
    for line in text.splitlines():
        if line and not line[0].isspace() and line.endswith(":") and ":" in line:
            candidate = line[:-1].strip()
            if candidate and " " not in candidate:
                if key is not None:
                    sections[key] = "\n".join(buffer).rstrip() + "\n"
                key = candidate
                buffer = [line]
                continue
        if key is not None:
            buffer.append(line)
    if key is not None:
        sections[key] = "\n".join(buffer).rstrip() + "\n"
    return sections


def load_override(url: str, cache: pathlib.Path) -> tuple[dict[str, str], str]:
    """Return the override sections, preferring a fresh download over cache."""
    if url:
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "mihomo"})
            with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT) as response:
                body = response.read().decode("utf-8")
            sections = split_top_level(body)
            if {"proxy-groups", "rules"} <= sections.keys():
                cache.write_text(body, encoding="utf-8")
                os.chmod(cache, 0o600)
                return sections, "download"
            print(
                "mihomo-render: override missing proxy-groups/rules; ignoring download",
                file=sys.stderr,
            )
        except Exception as error:  # noqa: BLE001 - fall back to the cached copy
            print(f"mihomo-render: override download failed: {error}", file=sys.stderr)

    cached = read_optional(str(cache))
    if cached:
        sections = split_top_level(cached)
        if {"proxy-groups", "rules"} <= sections.keys():
            return sections, "cache"
        print(
            "mihomo-render: cached override missing proxy-groups/rules; ignoring",
            file=sys.stderr,
        )
    return {}, "fallback"


def force_direct_rule_providers(section: str) -> str:
    """Pin every rule-provider download to DIRECT.

    mihomo resolves provider downloads through the proxy rules, so a
    provider whose host is not matched to DIRECT would be fetched through a
    proxy node before any node is known to work. The override lists live on a
    China-reachable CDN, so fetching them directly breaks the bootstrap loop.
    """
    lines = section.splitlines()
    out: list[str] = []
    for index, line in enumerate(lines):
        out.append(line)
        match = re.match(r"^(\s{2,})url:\s*\S+", line)
        if not match:
            continue
        indent = match.group(1)
        parent = len(indent) - 2
        has_proxy = False
        for follower in lines[index + 1 :]:
            if follower and len(follower) - len(follower.lstrip()) <= parent:
                break
            if re.match(rf"^{re.escape(indent)}proxy:", follower):
                has_proxy = True
                break
        if not has_proxy:
            out.append(f"{indent}proxy: DIRECT")
    return "\n".join(out) + "\n"


def read_rule_lines(path: str) -> list[str]:
    """Read rule entries from a runtime YAML file with a `rules:` list."""
    text = read_optional(path)
    if not text:
        return []
    collected: list[str] = []
    started = False
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not started:
            if re.match(r"^rules:\s*$", stripped):
                started = True
                continue
            if stripped.startswith("-"):
                started = True
        if started:
            collected.append(line.rstrip())
    return collected


def prepend_rules(custom_lines: list[str], base_section: str) -> str:
    """Insert custom rules before the rules in an existing `rules:` section."""
    if not custom_lines:
        return base_section
    base_lines = base_section.splitlines()
    if base_lines and re.match(r"^rules:\s*$", base_lines[0].strip()):
        return "\n".join(["rules:", *custom_lines, *base_lines[1:]]) + "\n"
    return "rules:\n" + "\n".join(custom_lines) + "\n" + base_section


def fallback_groups() -> str:
    return (
        "proxy-groups:\n"
        "  - name: PROXY\n"
        "    type: select\n"
        "    include-all: true\n"
        "    proxies:\n"
        "      - AUTO\n"
        "      - DIRECT\n"
        "    url: https://www.gstatic.com/generate_204\n"
        "    interval: 300\n"
        "    lazy: true\n"
        "  - name: 节点选择\n"
        "    type: select\n"
        "    include-all: true\n"
        "    proxies:\n"
        "      - PROXY\n"
        "      - DIRECT\n"
        "  - name: AUTO\n"
        "    type: url-test\n"
        "    include-all: true\n"
        "    proxies:\n"
        "      - DIRECT\n"
        "    url: https://www.gstatic.com/generate_204\n"
        "    interval: 300\n"
        "    tolerance: 50\n"
        "    lazy: true\n"
    )


def main() -> int:
    (
        template_path,
        url_path,
        custom_src,
        custom_rules_path,
        override_url,
        controller_endpoint,
        state_dir,
    ) = sys.argv[1:8]
    template = pathlib.Path(template_path).read_text(encoding="utf-8")

    state = pathlib.Path(state_dir)
    state.mkdir(mode=0o700, parents=True, exist_ok=True)

    url = read_optional(url_path)
    if url:
        providers_block = (
            "proxy-providers:\n"
            "  sub:\n"
            "    type: http\n"
            f"    url: {json.dumps(url)}\n"
            "    path: ./providers/sub.yaml\n"
            "    proxy: DIRECT\n"
            "    interval: 21600\n"
            "    size-limit: 5242880\n"
            "    header:\n"
            '      User-Agent: ["mihomo"]\n'
            "    health-check:\n"
            "      enable: true\n"
            "      url: https://www.gstatic.com/generate_204\n"
            "      interval: 300\n"
            "      timeout: 5000\n"
            "      lazy: true\n"
            "      expected-status: 204\n"
            "    override:\n"
            "      udp: true\n"
            '      additional-prefix: "[sub] "\n'
            '    exclude-filter: "(?i)(官网|订阅|剩余|流量|到期|过期|expire|traffic|website|channel)"\n'
        )
    else:
        providers_block = ""
        print(
            "mihomo-render: no subscription URL file; starting with custom nodes and DIRECT only",
            file=sys.stderr,
        )

    custom_rules = read_rule_lines(custom_rules_path)
    sections, source = load_override(override_url, state / "override.yaml")

    if sections:
        groups = sections["proxy-groups"]
        rules = ""
        if "rule-providers" in sections:
            rules += force_direct_rule_providers(sections["rule-providers"])
        rules += prepend_rules(custom_rules, sections["rules"])
    else:
        groups = fallback_groups()
        rules = prepend_rules(custom_rules, FALLBACK_RULES)

    config = template.replace("# __PROXY_PROVIDERS__\n", providers_block)
    config = config.replace("# __CUSTOM_PROXIES__\n", custom_proxies_block(custom_src))
    config = config.replace("# __PROXY_GROUPS__\n", groups)
    config = config.replace("# __RULES__\n", rules)

    secret_file = state / "controller.secret"
    secret = read_optional(str(secret_file))
    if not secret:
        secret = secrets.token_urlsafe(32)
        secret_file.write_text(secret + "\n", encoding="utf-8")
        os.chmod(secret_file, 0o600)
    config = config.replace("__CONTROLLER_ENDPOINT__", controller_endpoint)
    config = config.replace("__CONTROLLER_SECRET__", secret)

    config_path = state / "config.yaml"
    config_path.write_text(config, encoding="utf-8")
    os.chmod(config_path, 0o600)

    providers = state / "providers"
    providers.mkdir(mode=0o700, parents=True, exist_ok=True)

    print(
        f"mihomo-render: wrote {config_path} (rules override: {source})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
