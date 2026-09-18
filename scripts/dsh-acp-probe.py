#!/usr/bin/env python3
"""Minimal ACP client used to verify the DeepSeek Harness `acp` profile.

It drives the harness exactly the way Zed does — same stdio JSON-RPC transport,
same `initialize` capabilities — so that a failure here is reproducible without
opening the editor. It reports three things the handshake alone cannot show:

* the selectors the agent advertises (`modes`, and `configOptions` by category);
* that assistant text actually arrives (`agent_message_chunk`, not just a
  settled prompt with non-zero output tokens);
* that stdout stays pure JSON, which the ACP transport requires.

Usage:

    scripts/dsh-acp-probe.py                       # default prompt, default model
    scripts/dsh-acp-probe.py --model '["<route>","<model>"]'
    scripts/dsh-acp-probe.py --prompt 'Reply with exactly: OK' --wait 8
    scripts/dsh-acp-probe.py --permission-mode workspace-write

Exit status is 0 only when the turn produced assistant text; every other
outcome (no session, no text, dirty stdout, timeout) exits non-zero, so this is
usable as a smoke test after a deployment or a dsh upgrade.

Only the Python standard library is used, and no secret is involved: the
launched `dsh` wrapper resolves credentials itself.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import time

PURITY_ERRORS: list[str] = []


def build_command(args: argparse.Namespace) -> list[str]:
    exe = args.command
    resolved = shutil.which(exe) if os.sep not in exe else exe
    if not resolved:
        sys.exit(f"cannot find {exe!r}; pass --command with an absolute path")
    return [resolved, "--profile", args.profile]


class Probe:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.proc = subprocess.Popen(  # noqa: S603 - fixed argv, no shell
            build_command(args),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env={**os.environ, **({"DSH_PERMISSION_MODE": args.permission_mode} if args.permission_mode else {})},
        )
        self.write_lock = threading.Lock()
        self.done = threading.Event()
        self.text: list[str] = []
        self.update_kinds: list[str] = []
        self.session_id: str | None = None
        self.modes: object = None
        self.config_options: list[dict] = []

    # ---------------------------------------------------------------- transport

    def send(self, message: dict) -> None:
        with self.write_lock:
            if self.proc.stdin is None:
                return
            self.proc.stdin.write(json.dumps(message) + "\n")
            self.proc.stdin.flush()

    def stdout_pump(self) -> None:
        assert self.proc.stdout is not None
        for raw in self.proc.stdout:
            line = raw.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                # Non-JSON on stdout corrupts the ACP stream; record it loudly.
                PURITY_ERRORS.append(line[:200])
                print(f"DIRTY_STDOUT: {line[:200]}", flush=True)
                continue
            try:
                self.handle(message)
            except Exception as exc:  # noqa: BLE001 - report, never crash mid-stream
                print(f"HANDLER_ERROR: {exc!r} on {line[:200]}", flush=True)
            if self.done.is_set():
                return

    def stderr_pump(self) -> None:
        assert self.proc.stderr is not None
        for raw in self.proc.stderr:
            line = raw.strip()
            if line:
                print(f"STDERR: {line[:400]}", flush=True)

    def ask(self) -> None:
        self.send(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "session/prompt",
                "params": {
                    "sessionId": self.session_id,
                    "prompt": [{"type": "text", "text": self.args.prompt}],
                },
            }
        )

    # ------------------------------------------------------------ agent -> client

    def handle_client_request(self, message: dict) -> None:
        method = message["method"]
        params = message.get("params", {})
        rid = message["id"]
        if method == "fs/read_text_file":
            try:
                with open(params["path"], errors="replace") as handle:
                    content = handle.read()
                self.send({"jsonrpc": "2.0", "id": rid, "result": {"content": content}})
            except OSError as exc:
                self.send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32000, "message": str(exc)}})
        elif method == "fs/write_text_file":
            self.send({"jsonrpc": "2.0", "id": rid, "result": None})
        elif method == "session/request_permission":
            # The official bridge emits this per tool call; approving here stands
            # in for the user clicking "allow" in the editor.
            options = params.get("options", [])
            print(f"PERMISSION: {json.dumps(params.get('toolCall', {}))[:200]}", flush=True)
            chosen = next((o for o in options if o.get("optionId") == "allow-once"), None)
            if chosen is None:
                self.send(
                    {"jsonrpc": "2.0", "id": rid, "result": {"outcome": {"outcome": "cancelled"}}}
                )
            else:
                self.send(
                    {
                        "jsonrpc": "2.0",
                        "id": rid,
                        "result": {"outcome": {"outcome": "selected", "optionId": chosen["optionId"]}},
                    }
                )
        elif method == "terminal/create":
            self.send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": method}})
        else:
            self.send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": method}})

    def handle_notification(self, message: dict) -> None:
        if message.get("method") != "session/update":
            return
        update = message.get("params", {}).get("update", {})
        kind = update.get("sessionUpdate")
        self.update_kinds.append(kind)
        if kind == "agent_message_chunk":
            content = update.get("content", {})
            if content.get("type") == "text":
                self.text.append(content["text"])
                print(f"CHUNK: {content['text'][:200]}", flush=True)
        elif kind in ("tool_call", "tool_call_update"):
            print(f"TOOL: {json.dumps(update)[:200]}", flush=True)

    # ------------------------------------------------------------------ dispatch

    def handle(self, message: dict) -> None:
        if "method" in message and "id" in message:
            self.handle_client_request(message)
            return
        if "method" in message:
            self.handle_notification(message)
            return

        rid = message.get("id")
        if rid == 1:
            result = message.get("result", {})
            agent = result.get("agentInfo", {})
            print(f"AGENT: {agent.get('name')} {agent.get('version')}", flush=True)
            print(f"CAPABILITIES: {json.dumps(result.get('agentCapabilities', {}))[:400]}", flush=True)
            self.send(
                {
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "session/new",
                    "params": {"cwd": os.path.expanduser("~"), "mcpServers": []},
                }
            )
        elif rid == 2:
            result = message.get("result", {})
            self.session_id = result.get("sessionId")
            self.modes = result.get("modes")
            self.config_options = result.get("configOptions") or []
            print(f"MODES: {json.dumps(self.modes)[:600]}", flush=True)
            for option in self.config_options:
                print(f"CONFIG_OPTION: {option.get('id')} category={option.get('category')}", flush=True)
            if not self.session_id:
                print(f"NO_SESSION: {json.dumps(message)[:300]}", flush=True)
                self.done.set()
            elif self.args.model is not None:
                self.send(
                    {
                        "jsonrpc": "2.0",
                        "id": 4,
                        "method": "session/set_config_option",
                        "params": {
                            "sessionId": self.session_id,
                            "configId": "model",
                            "value": self.args.model,
                        },
                    }
                )
            else:
                self.ask()
        elif rid == 4:
            print(f"SET_MODEL: {json.dumps(message.get('result', message.get('error')))[:200]}", flush=True)
            self.ask()
        elif rid == 3:
            print(f"SETTLE: {json.dumps(message.get('result', message.get('error')))[:200]}", flush=True)
            # A settled prompt is not proof of delivery: under the buggy bridge it
            # returns end_turn with output tokens and no chunk. Give late chunks a
            # chance to arrive before declaring the turn empty.
            time.sleep(self.args.wait)
            self.done.set()

    # ---------------------------------------------------------------------- run

    def run(self) -> int:
        for target in (self.stdout_pump, self.stderr_pump):
            threading.Thread(target=target, daemon=True).start()

        self.send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": 1,
                    # Zed's capabilities, verbatim: the agent picks its behaviour
                    # from these, so a mismatch can hide or expose code paths.
                    "clientCapabilities": {
                        "fs": {"readTextFile": True, "writeTextFile": True},
                        "terminal": True,
                    },
                    "clientInfo": {"name": "zed", "version": "0.1.0"},
                },
            }
        )

        self.done.wait(timeout=self.args.timeout)
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except OSError:
            pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()

        text = "".join(self.text)
        print("=" * 62)
        print(f"TEXT_LEN: {len(text)}")
        print(f"TEXT: {text[:400]}")
        print(f"UPDATE_KINDS: {sorted(set(self.update_kinds))}")
        print(f"MODES: {self.modes is not None}  "
              f"CONFIG_CATEGORIES: {[o.get('category') for o in self.config_options]}")
        print(f"DIRTY_STDOUT_LINES: {len(PURITY_ERRORS)}")

        if PURITY_ERRORS:
            print("FAIL: stdout carried non-JSON lines")
            return 2
        if not text:
            print("FAIL: the turn settled without assistant text")
            return 1
        print("OK: assistant text received")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--command", default="dsh", help="dsh executable (default: %(default)s from PATH)")
    parser.add_argument("--profile", default="acp", help="profile to launch (default: %(default)s)")
    parser.add_argument("--prompt", default="Reply with exactly: PROBE-OK", help="prompt text")
    parser.add_argument(
        "--model",
        default=None,
        help='value for session/set_config_option, e.g. \'["<route>","<model>"]\'',
    )
    parser.add_argument("--wait", type=float, default=5.0, help="seconds to keep reading after end_turn")
    parser.add_argument("--timeout", type=float, default=180.0, help="overall seconds before giving up")
    parser.add_argument(
        "--permission-mode",
        default=None,
        choices=["read-only", "workspace-write", "danger-full-access"],
        help="export DSH_PERMISSION_MODE for the child process",
    )
    return Probe(parser.parse_args()).run()


if __name__ == "__main__":
    sys.exit(main())
