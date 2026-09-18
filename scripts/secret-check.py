#!/usr/bin/env python3
"""校验 secrets/ 密文与模块声明的一致性。

这个脚本按当前仓库真实的机密模型工作：机密在各服务模块里通过
`age.secrets.<name>.file = ../../secrets/<name>.age` 声明，接收者本身就是访问控制。
仓库不提交清单文件（`secrets/secrets.nix` 已在 059d0c2 中删除），所以这里不做任何
清单导入，也不解出任何明文。

它检查四件事：

  1. 声明与文件对齐。模块引用但仓库里没有的 .age 是错误；仓库里有但没有任何模块
     引用的 .age 是警告（可能忘了声明，也可能是残留）。
  2. 密文格式可用。必须是 age v1，且至少有一个 `ssh-ed25519` 接收者 stanza。用
     `age -r age1...` 或 `ssh-to-age` 生成的 X25519 接收者会让 agenix 用 SSH 私钥
     解密失败，这个坑在 secrets/README.md 里有记录。
  3. 接收者清单有效。secrets/recipients.txt 至少有一个接收者，且只含 SSH 公钥。
  4. 本机可达的机密必须能解密。从当前主机入口文件跟随 `imports` 收集可达的 .age，
     这些必须能用本机身份读回；只在其他目标上使用的机密解密失败只是提示。

解密结果直接丢弃（stdout 到 /dev/null），不落盘、不打印，错误信息只保留 age 的首行
诊断。用法：

  scripts/secret-check.py
  scripts/secret-check.py --host fedora-thinkbook --identity ~/.ssh/id_ed25519
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys

DEFAULT_IDENTITY = "~/.ssh/id_ed25519"
RECIPIENTS_FILE = "secrets/recipients.txt"

# 模块里对密文的引用，例如 ../../secrets/deepseek-api-key.age
REFERENCE_RE = re.compile(r"secrets/([A-Za-z0-9._-]+\.age)")
# 跟随 imports 列表里的相对路径（./x.nix、../../modules/y/default.nix）
IMPORTS_RE = re.compile(r"imports\s*=\s*\[(.*?)\]", re.DOTALL)
IMPORT_PATH_RE = re.compile(r"\.{1,2}/[A-Za-z0-9._/-]+\.nix")

AGE_HEADER = b"age-encryption.org/v1"
SSH_STANZA = b"-> ssh-ed25519 "
X25519_STANZA = b"-> X25519 "

ERROR, WARN, INFO, OK = "ERROR", "WARN", "INFO", "OK"


class Finding:
    def __init__(self, level: str, message: str):
        self.level = level
        self.message = message


class SecretCheck:
    def __init__(self, root: pathlib.Path, host: str, identity: pathlib.Path):
        self.root = root
        self.secrets_dir = root / "secrets"
        self.host = host
        self.identity = identity
        self.findings: list[Finding] = []
        self.age_binary = shutil.which("age")
        self.identity_usable = True
        self.identity_note = ""
        # 密文名 -> [(文件, 行号)]
        self.references: dict[str, list[tuple[str, int]]] = {}
        # 从当前主机入口可达的密文名
        self.reachable: set[str] = set()
        self.reach_note = ""
        # 当前主机是 NixOS 目标时为真：那类机密由主机密钥解密，不由本机用户身份负责
        self.nixos_entry = False

    # ------------------------------------------------------------------ 收集

    def collect_references(self) -> None:
        """扫描所有 .nix 文件，记录每个密文被谁引用。"""
        for path in sorted(self.root.rglob("*.nix")):
            if ".git" in path.parts:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                self.findings.append(Finding(WARN, f"无法读取 {self.relative(path)}：{exc}"))
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                for match in REFERENCE_RE.finditer(line):
                    name = match.group(1)
                    self.references.setdefault(name, []).append(
                        (self.relative(path), lineno)
                    )

    def entry_files(self) -> list[pathlib.Path]:
        """当前主机的入口文件：Home Manager 用户入口优先，其次 NixOS 主机入口。"""
        entries = sorted((self.root / "users").glob(f"*/{self.host}.nix"))
        if entries:
            return entries
        nixos = self.root / "hosts" / self.host / "configuration.nix"
        return [nixos] if nixos.is_file() else []

    def collect_reachable(self) -> None:
        """从入口文件跟随 imports，收集这条链上声明的密文。"""
        entries = self.entry_files()
        if not entries:
            self.reach_note = f"没有找到主机 {self.host} 的入口文件，跳过本机可达性检查"
            return

        seen: set[pathlib.Path] = set()
        queue = list(entries)
        styles = set()
        while queue:
            path = queue.pop()
            path = path.resolve()
            if path in seen or not path.is_file():
                continue
            seen.add(path)
            if not self.is_inside_repo(path):
                continue
            rel = self.relative(path)
            if rel.startswith("hosts/"):
                styles.add("nixos")
            elif rel.startswith("users/"):
                styles.add("home-manager")
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in REFERENCE_RE.finditer(text):
                self.reachable.add(match.group(1))
            for block in IMPORTS_RE.finditer(text):
                for token in IMPORT_PATH_RE.finditer(block.group(1)):
                    candidate = pathlib.Path(os.path.normpath(path.parent / token.group(0)))
                    if self.is_inside_repo(candidate):
                        queue.append(candidate)

        if "nixos" in styles and "home-manager" not in styles:
            self.nixos_entry = True
            self.reach_note = (
                f"主机 {self.host} 是 NixOS 目标，其机密由主机密钥解密；"
                "本机用户身份的可解密性只作提示"
            )

    def is_inside_repo(self, path: pathlib.Path) -> bool:
        try:
            path.resolve().relative_to(self.root)
        except ValueError:
            return False
        return True

    def relative(self, path: pathlib.Path) -> str:
        try:
            return str(path.resolve().relative_to(self.root))
        except ValueError:
            return str(path)

    # ------------------------------------------------------------------ 检查

    def check_alignment(self, on_disk: set[str]) -> None:
        for name, sites in sorted(self.references.items()):
            if name not in on_disk:
                where = "、".join(f"{f}:{l}" for f, l in sites[:3])
                self.findings.append(
                    Finding(ERROR, f"{name} 被引用但仓库中不存在（{where}）")
                )
        for name in sorted(on_disk):
            if name not in self.references:
                self.findings.append(
                    Finding(WARN, f"{name} 存在于 secrets/ 但没有任何模块引用")
                )

    def check_format(self, path: pathlib.Path) -> list[Finding]:
        findings: list[Finding] = []
        data = path.read_bytes()
        name = path.name
        if not data.startswith(AGE_HEADER):
            findings.append(
                Finding(ERROR, f"{name} 不是 age v1 密文（缺少 {AGE_HEADER.decode()} 头）")
            )
            return findings
        if SSH_STANZA not in data:
            findings.append(
                Finding(
                    ERROR,
                    f"{name} 没有 ssh-ed25519 接收者；用 age -r age1... 生成的密文 agenix 解不开",
                )
            )
        elif X25519_STANZA in data:
            findings.append(
                Finding(WARN, f"{name} 同时含 X25519 接收者，确认它不是唯一可用的接收者")
            )
        return findings

    def check_recipients(self) -> None:
        path = self.root / RECIPIENTS_FILE
        if not path.is_file():
            self.findings.append(Finding(ERROR, f"缺少接收者清单 {RECIPIENTS_FILE}"))
            return
        keys = [
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        if not keys:
            self.findings.append(Finding(ERROR, f"{RECIPIENTS_FILE} 里没有接收者"))
            return
        bad = [k for k in keys if not k.startswith("ssh-")]
        if bad:
            self.findings.append(
                Finding(
                    ERROR,
                    f"{RECIPIENTS_FILE} 含非 SSH 接收者（首行 {bad[0][:32]}...）",
                )
            )
        else:
            self.findings.append(
                Finding(OK, f"{RECIPIENTS_FILE} 含 {len(keys)} 个 SSH 接收者")
            )

    def try_decrypt(self, path: pathlib.Path) -> tuple[str, str]:
        """返回 (状态, 说明)。状态: ok / nomatch / skip / fail。"""
        if not self.age_binary:
            return "skip", "找不到 age 可执行文件"
        if not self.identity.is_file():
            return "skip", f"本机身份不存在：{self.identity}"
        if not self.identity_usable:
            return "skip", self.identity_note
        try:
            proc = subprocess.run(
                [self.age_binary, "-d", "-i", str(self.identity), str(path)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,  # 明文只进 /dev/null
                stderr=subprocess.PIPE,
                timeout=20,
            )
        except subprocess.TimeoutExpired:
            self.identity_usable = False
            self.identity_note = "age 解密超时，后续跳过"
            return "skip", self.identity_note
        except OSError as exc:
            return "skip", f"无法执行 age：{exc}"

        if proc.returncode == 0:
            return "ok", ""

        message = proc.stderr.decode(errors="replace").strip()
        first_line = message.splitlines()[0] if message else "age 解密失败"
        if "no identity matched" in message:
            return "nomatch", "本机身份不在接收者中"
        if "passphrase" in message.lower() or "terminal" in message.lower():
            self.identity_usable = False
            self.identity_note = "本机身份需要口令，非交互环境下跳过解密校验"
            return "skip", self.identity_note
        return "fail", first_line[:140]

    # ------------------------------------------------------------------ 输出

    def run(self) -> int:
        if not self.secrets_dir.is_dir():
            print(f"错误：找不到目录 {self.secrets_dir}", file=sys.stderr)
            return 1

        self.collect_references()
        self.collect_reachable()
        on_disk = {p.name for p in self.secrets_dir.glob("*.age")}

        self.check_alignment(on_disk)
        format_findings: dict[str, list[Finding]] = {}
        for name in sorted(on_disk):
            findings = self.check_format(self.secrets_dir / name)
            format_findings[name] = findings
            self.findings.extend(findings)
        self.check_recipients()

        print(f"机密校验：{self.root}（主机 {self.host}）")
        if self.reach_note:
            print(f"  {self.reach_note}")
        print()

        for name in sorted(on_disk):
            refs = len(self.references.get(name, []))
            broken = any(f.level == ERROR for f in format_findings[name])
            fmt = "格式错误" if broken else "age v1"
            status, detail = self.try_decrypt(self.secrets_dir / name)
            if status == "ok":
                decrypt = "本机可解密"
            elif status == "nomatch":
                decrypt = "本机身份不匹配"
            elif status == "skip":
                decrypt = f"跳过（{detail}）"
            else:
                decrypt = f"解密失败（{detail}）"
            mark = "!" if broken else " "
            if status == "nomatch" and name in self.reachable:
                if self.nixos_entry:
                    # NixOS 目标用 /etc/ssh/ssh_host_ed25519_key 解密，用户身份不匹配是正常的
                    self.findings.append(
                        Finding(
                            INFO,
                            f"{name} 需要主机密钥解密，本机用户身份校验不适用",
                        )
                    )
                else:
                    mark = "!"
                    self.findings.append(
                        Finding(
                            ERROR,
                            f"{name} 是本机可达的机密，但本机身份不能解密它",
                        )
                    )
            print(f"  {mark} {name:44} 引用 {refs:>2} 处  {fmt:9} {decrypt}")

        for level in (ERROR, WARN, INFO):
            items = [f for f in self.findings if f.level == level]
            if not items:
                continue
            print()
            print(f"{level}（{len(items)}）：")
            for finding in items:
                print(f"  - {finding.message}")

        notes = [f for f in self.findings if f.level == OK]
        errors = len([f for f in self.findings if f.level == ERROR])
        warns = len([f for f in self.findings if f.level == WARN])
        print()
        for note in notes:
            print(f"  {note.message}")
        print(
            f"结果：{len(on_disk)} 个密文，{len(self.references)} 处引用，"
            f"{errors} 个错误，{warns} 个警告"
        )
        if errors:
            print("机密校验失败。")
            return 1
        print("机密校验通过。")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="校验 secrets/*.age 与模块声明的一致性")
    parser.add_argument(
        "--root",
        default=str(pathlib.Path(__file__).resolve().parents[1]),
        help="仓库根目录（默认脚本所在仓库）",
    )
    parser.add_argument(
        "--host",
        default=socket.gethostname().split(".")[0],
        help="当前主机名，用于定位入口文件（默认本机 hostname）",
    )
    parser.add_argument(
        "--identity",
        default=DEFAULT_IDENTITY,
        help=f"本机身份私钥（默认 {DEFAULT_IDENTITY}）",
    )
    args = parser.parse_args()

    checker = SecretCheck(
        root=pathlib.Path(args.root).resolve(),
        host=args.host,
        identity=pathlib.Path(os.path.expanduser(args.identity)),
    )
    return checker.run()


if __name__ == "__main__":
    sys.exit(main())
