#!/usr/bin/env python3
"""写入 DeepSeek Harness 的 API 凭据。

这个脚本存在的理由：凭据的值不应该出现在命令行参数、shell 历史、补丁、文档或
终端输出里。值只通过**不回显的交互输入**进入进程，随后直接被管道送进 `age`，
全程不落明文文件、不打印、不进 argv。

它做三件事：

  list              列出托管凭据的密文状态（以及可选的本地凭据库里的值长度）
  set ENV           交互输入新值，按 secrets/recipients.txt 重新加密
  verify            用本地身份解密每个密文，确认能读回且长度一致

落盘结果只有一处：`secrets/<name>.age` 密文。调用方的 harness 运行时凭据库是可
选的（`--store`），因为部署模块走的是"启动环境优先"的路径，age 密文才是这台机器
上真正生效的来源。

用法示例：

  scripts/dsh-credentials.py list
  scripts/dsh-credentials.py set OPENCODE_API_KEY
  scripts/dsh-credentials.py set DEEPSEEK_API_KEY --store auto
  scripts/dsh-credentials.py verify
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

# 密文文件名 -> 读取它的环境变量名（一个密文可以服务多个变量名）。
#
# OpenCode Go 和 OpenCode Zen 接受同一个 key，所以两个变量名指向同一个密文：
# 存两份会让它们有分叉的可能，而它们本来就是同一个凭据。
CREDENTIALS = {
    "deepseek-api-key.age": ["DEEPSEEK_API_KEY"],
    "ten-rings-api-key.age": ["TEN_RINGS_API_KEY"],
    "opencode-api-key.age": ["OPENCODE_GO_API_KEY", "OPENCODE_API_KEY"],
}

# 值短于这个长度时要求二次确认：占位符和截断的值通常就长这样。
SHORT_VALUE_BYTES = 16


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]


def env_aliases() -> dict[str, str]:
    """环境变量名 -> 密文文件名。"""
    return {env: name for name, envs in CREDENTIALS.items() for env in envs}


def age_file_name(env: str) -> str:
    return env_aliases().get(env, env.lower().replace("_", "-") + ".age")


def load_recipients(path: pathlib.Path) -> list[str]:
    if not path.is_file():
        raise SystemExit(f"缺少接收者清单：{path}")
    keys = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if not keys:
        raise SystemExit(f"{path} 里没有接收者；拒绝加密一个谁都解不开的密文")
    bad = [k for k in keys if not k.startswith("ssh-")]
    if bad:
        raise SystemExit(
            f"{path} 含非 SSH 接收者（age 会用 SSH 私钥解密，必须是 ssh-ed25519）：{bad[0][:40]}"
        )
    return keys


def run_age(args: list[str], data: bytes | None = None) -> bytes:
    try:
        proc = subprocess.run(["age", *args], input=data, capture_output=True)
    except FileNotFoundError:
        raise SystemExit("找不到 age 可执行文件；先安装 age 再重试")
    if proc.returncode != 0:
        raise SystemExit(f"age 失败：{proc.stderr.decode(errors='replace').strip()}")
    return proc.stdout


def encrypt(value: str, recipients: list[str], out: pathlib.Path) -> None:
    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        handle.write("".join(k + "\n" for k in recipients))
        recipient_file = pathlib.Path(handle.name)
    os.chmod(recipient_file, 0o600)
    try:
        blob = run_age(["-e", "-R", str(recipient_file)], value.encode())
        out.write_bytes(blob)
        os.chmod(out, 0o644)
    finally:
        recipient_file.unlink(missing_ok=True)


def decrypt(path: pathlib.Path, identity: pathlib.Path) -> str:
    return run_age(["-d", "-i", str(identity), str(path)]).decode()


def local_identity() -> pathlib.Path:
    key = pathlib.Path.home() / ".ssh/id_ed25519"
    if not key.is_file():
        raise SystemExit(f"找不到本地身份：{key}（用 --identity 指定）")
    return key


def detect_store() -> pathlib.Path:
    candidates = []
    if os.environ.get("DSH_HOME"):
        candidates.append(pathlib.Path(os.environ["DSH_HOME"]) / ".credentials.yaml")
    candidates += [
        pathlib.Path.home() / ".dsh/.credentials.yaml",
        pathlib.Path.home() / ".local/share/deepseek-harness/home/.credentials.yaml",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise SystemExit("找不到 harness 运行时凭据库；用 --store <path> 指定")


def read_store_ref(path: pathlib.Path, env: str) -> str | None:
    """只读取长度信息需要的东西；调用方绝不打印返回的值。"""
    if not path.is_file():
        return None
    in_refs = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.rstrip() == "refs:":
            in_refs = True
            continue
        if in_refs:
            if line and not line.startswith((" ", "\t")):
                return None
            if line.startswith(f"  {env}:"):
                raw = line.split(":", 1)[1].strip()
                try:
                    return json.loads(raw)
                except json.JSONDecodeError:
                    return raw
            if line.strip() and not line.startswith("  "):
                return None
    return None


def write_store_ref(path: pathlib.Path, env: str, value: str) -> None:
    """就地改写 refs 段里的一个键，保留文件其余部分。

    只做单行值的行级替换（API key 就是单行）。这样不必用 YAML 库重排整个文件，
    也就不会碰坏 records 段的嵌套结构。
    """
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out: list[str] = []
    in_refs = False
    written = False

    for line in lines:
        stripped = line.rstrip("\n")
        if not in_refs:
            out.append(line)
            if stripped == "refs:":
                in_refs = True
            continue

        # refs 段结束：先把新值补在末尾，再交回控制权。
        if stripped and not stripped.startswith((" ", "\t")):
            if not written:
                out.append(f"  {env}: {json.dumps(value)}\n")
                written = True
            in_refs = False
            out.append(line)
            continue

        if stripped.startswith(f"  {env}:"):
            out.append(f"  {env}: {json.dumps(value)}\n")
            written = True
            continue

        out.append(line)

    if in_refs and not written:
        out.append(f"  {env}: {json.dumps(value)}\n")
        written = True

    if not written:
        raise SystemExit(f"{path}: 找不到 refs: 段，未改动")

    shutil.copy2(path, path.with_name(path.name + ".bak"))
    path.write_text("".join(out), encoding="utf-8")
    os.chmod(path, 0o600)


def cmd_list(args: argparse.Namespace) -> int:
    secrets_dir = args.repo / "secrets"
    store = detect_store() if args.store == "auto" else (pathlib.Path(args.store) if args.store else None)

    print(f"接收者清单：{secrets_dir / 'recipients.txt'}")
    for key in load_recipients(secrets_dir / "recipients.txt"):
        print(f"  {key.split()[-1]:<20} {key.split()[1][:24]}…")

    print(f"\n{'环境变量':<22} {'密文':<24} {'密文大小':>8}  {'运行时库值长度':>14}")
    for name, envs in sorted(CREDENTIALS.items()):
        path = secrets_dir / name
        size = f"{path.stat().st_size}B" if path.is_file() else "缺失"
        for index, env in enumerate(envs):
            length = "-"
            if store is not None:
                value = read_store_ref(store, env)
                length = "未设置" if value is None else f"{len(value)} 字节"
            print(
                f"{env:<22} {name if index == 0 else '':<24} "
                f"{size if index == 0 else '':>8}  {length:>14}"
            )

    if store is not None:
        print(f"\n运行时凭据库：{store}")
        print("提示：部署模块走启动环境优先，所以 age 密文才是生效来源；库里的值是回退路径。")
    return 0


def prompt_value(env: str, allow_skip: bool) -> str | None:
    """读一个不回显的值；allow_skip 时空输入表示跳过（返回 None）。"""
    hint = "（直接回车跳过）" if allow_skip else ""
    first = getpass.getpass(f"{env} 的新值（不回显）{hint}：")
    if not first.strip():
        if allow_skip:
            return None
        raise SystemExit("拒绝写入空值")
    if first != getpass.getpass("再输入一次确认："):
        raise SystemExit(f"{env}：两次输入不一致，未改动任何文件")
    if len(first) < SHORT_VALUE_BYTES:
        print(f"警告：{env} 只有 {len(first)} 字节，看起来像占位符或被截断。")
        if input("仍然写入？输入 yes 继续：").strip() != "yes":
            return None
    return first


def write_credential(args: argparse.Namespace, env: str) -> pathlib.Path | None:
    """加密、往返校验并落盘一个凭据；未写入时返回 None。"""
    secrets_dir = args.repo / "secrets"
    recipients = load_recipients(secrets_dir / "recipients.txt")
    identity = pathlib.Path(args.identity) if args.identity else local_identity()
    out = secrets_dir / age_file_name(env)

    if env not in env_aliases():
        print(f"注意：{env} 不在已知清单里，将写入 {out.name}")
    else:
        shared = [e for e, n in env_aliases().items() if n == out.name]
        if len(shared) > 1:
            print(f"{out.name} 是一个凭据、服务于 {'、'.join(shared)}。")

    value = prompt_value(env, allow_skip=args.command == "set-all")
    if value is None:
        print(f"{env}：跳过")
        return None

    target = pathlib.Path(tempfile.mkdtemp()) / out.name if args.dry_run else out
    encrypt(value, recipients, target)

    if decrypt(target, identity) != value:
        shutil.rmtree(target.parent, ignore_errors=True) if args.dry_run else target.unlink(missing_ok=True)
        raise SystemExit(f"{env}：往返校验失败，未改动任何文件")

    if args.dry_run:
        print(f"{env}：加密与往返校验通过（--dry-run，未写入仓库）")
        shutil.rmtree(target.parent, ignore_errors=True)
        return None

    print(f"{env}：已写入 secrets/{out.name}（{out.stat().st_size} 字节，往返校验通过）")
    if args.store:
        store = detect_store() if args.store == "auto" else pathlib.Path(args.store)
        write_store_ref(store, env, value)
    return out


def finish(args: argparse.Namespace, written: list[pathlib.Path]) -> int:
    if not written:
        print("\n没有写入任何凭据。")
        return 0

    if args.store:
        store = detect_store() if args.store == "auto" else pathlib.Path(args.store)
        print(f"已更新运行时凭据库 {store}（原文件备份为 {store.name}.bak）")

    if args.push:
        for path in written:
            subprocess.run(
                ["scp", str(path), f"{args.push}:{args.remote_repo}/secrets/"],
                check=True,
            )
            print(f"已复制到 {args.push}:{args.remote_repo}/secrets/{path.name}")

    print(
        "\n下一步：让目标主机重新解密并生效\n"
        f"  ssh {args.push or '<host>'} 'cd {args.remote_repo} && \\\n"
        f"    home-manager switch --flake \".#{args.remote_target}\" -b backup'\n"
        "  # 然后重启该主机的 agent 进程（acp profile 是 patchReload: startup）"
    )
    return 0


def cmd_set(args: argparse.Namespace) -> int:
    if not args.env.replace("_", "").isalnum():
        raise SystemExit(f"{args.env} 不是合法的环境变量名")
    path = write_credential(args, args.env)
    return finish(args, [path] if path else [])


def cmd_set_all(args: argparse.Namespace) -> int:
    """一键把全部托管凭据写一遍；不打算改的直接回车跳过。"""
    if args.only:
        wanted = {age_file_name(n.strip()) for n in args.only.split(",") if n.strip()}
        names = [name for name in CREDENTIALS if name in wanted]
    else:
        names = sorted(CREDENTIALS)

    print("逐个输入；不打算修改的直接回车跳过。值不回显，也不会进入 argv。\n")
    written = []
    for name in names:
        path = write_credential(args, CREDENTIALS[name][0])
        if path:
            written.append(path)
        print()
    print(f"本次写入 {len(written)} / {len(names)} 个凭据。")
    return finish(args, written)


def cmd_verify(args: argparse.Namespace) -> int:
    secrets_dir = args.repo / "secrets"
    identity = pathlib.Path(args.identity) if args.identity else local_identity()
    failed = 0
    for name, envs in sorted(CREDENTIALS.items()):
        path = secrets_dir / name
        label = "/".join(envs)
        if not path.is_file():
            print(f"{label:<44} {name:<24} 缺失")
            failed += 1
            continue
        try:
            value = decrypt(path, identity)
        except SystemExit as error:
            print(f"{label:<44} {name:<24} 解密失败：{error}")
            failed += 1
            continue
        print(f"{label:<44} {name:<24} OK（{len(value)} 字节）")
    if failed:
        print(f"\n{failed} 个凭据不可用", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="写入 DeepSeek Harness 的 API 凭据（值不回显、不落明文、不进 argv）",
    )
    parser.add_argument("--repo", type=pathlib.Path, default=repo_root(), help="仓库根目录")
    sub = parser.add_subparsers(dest="command", required=True)

    p_list = sub.add_parser("list", help="列出凭据状态")
    p_list.add_argument(
        "--store",
        nargs="?",
        const="auto",
        help="同时显示某个 harness 运行时凭据库里的值长度；省略路径时自动探测",
    )
    p_list.set_defaults(func=cmd_list)

    def add_write_flags(target: argparse.ArgumentParser) -> None:
        target.add_argument("--identity", help="用于往返校验的 SSH 私钥（默认 ~/.ssh/id_ed25519）")
        target.add_argument(
            "--store",
            nargs="?",
            const="auto",
            help="同时写入 harness 运行时凭据库（回退路径）；省略路径时自动探测",
        )
        target.add_argument("--dry-run", action="store_true", help="只验证加解密，不写仓库")
        target.add_argument("--push", metavar="HOST", help="把新密文 scp 到另一台主机")
        target.add_argument(
            "--remote-repo",
            default="~/nixos-configuration",
            help="--push 目标主机上的仓库路径",
        )
        target.add_argument(
            "--remote-target",
            default="longred@fedora-thinkbook",
            help="--push 目标主机的 Home Manager 目标名",
        )

    p_set = sub.add_parser("set", help="交互输入并重新加密一个凭据")
    p_set.add_argument("env", help="环境变量名，例如 OPENCODE_API_KEY")
    add_write_flags(p_set)
    p_set.set_defaults(func=cmd_set)

    p_all = sub.add_parser("set-all", help="一键写入全部托管凭据；不打算改的直接回车跳过")
    p_all.add_argument(
        "--only",
        help="只处理这些（逗号分隔），例如 DEEPSEEK_API_KEY,TEN_RINGS_API_KEY",
    )
    add_write_flags(p_all)
    p_all.set_defaults(func=cmd_set_all)

    p_verify = sub.add_parser("verify", help="用本地身份解密每个密文")
    p_verify.add_argument("--identity", help="SSH 私钥（默认 ~/.ssh/id_ed25519）")
    p_verify.set_defaults(func=cmd_verify)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
