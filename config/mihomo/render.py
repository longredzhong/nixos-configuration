#!/usr/bin/env python3
"""Render the mihomo runtime config from the checked-in template and secrets.

Arguments (in order): template, subscription-url-file, custom-proxies-file, state-dir.

The subscription URL and any node credentials never enter the Nix store: the
URL is read from a runtime file and the rendered config is written with mode
0600 into the systemd StateDirectory. Missing inputs degrade to a working
"custom nodes + DIRECT" configuration instead of failing the unit.
"""

import json
import os
import pathlib
import secrets
import sys


def read_optional(path: str) -> str:
    try:
        return pathlib.Path(path).read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""


def main() -> int:
    template_path, url_path, custom_src, state_dir = sys.argv[1:5]
    template = pathlib.Path(template_path).read_text(encoding="utf-8")

    url = read_optional(url_path)
    if url:
        sub_block = (
            "  sub:\n"
            "    type: http\n"
            f"    url: {json.dumps(url)}\n"
            "    path: ./providers/sub.yaml\n"
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
            "      skip-cert-verify: false\n"
            '      additional-prefix: "[sub] "\n'
            '    exclude-filter: "(?i)(官网|订阅|剩余|流量|到期|过期|expire|traffic|website|channel)"\n'
        )
        sub_use = "sub, "
    else:
        sub_block = ""
        sub_use = ""
        print(
            "mihomo-render: no subscription URL file; starting with custom nodes and DIRECT only",
            file=sys.stderr,
        )

    config = template.replace("  # __SUBSCRIPTION_PROVIDER__\n", sub_block)
    config = config.replace("__SUBSCRIPTION_USE__", sub_use)

    state = pathlib.Path(state_dir)
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    secret_file = state / "controller.secret"
    secret = read_optional(str(secret_file))
    if not secret:
        secret = secrets.token_urlsafe(32)
        secret_file.write_text(secret + "\n", encoding="utf-8")
        os.chmod(secret_file, 0o600)
    config = config.replace("__CONTROLLER_SECRET__", secret)

    config_path = state / "config.yaml"
    config_path.write_text(config, encoding="utf-8")
    os.chmod(config_path, 0o600)

    providers = state / "providers"
    providers.mkdir(mode=0o700, parents=True, exist_ok=True)
    custom_target = providers / "custom.yaml"
    if os.path.isfile(custom_src) and os.path.getsize(custom_src) > 0:
        data = pathlib.Path(custom_src).read_bytes()
    else:
        data = b"proxies: []\n"
    custom_target.write_bytes(data)
    os.chmod(custom_target, 0o600)

    print(f"mihomo-render: wrote {config_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
