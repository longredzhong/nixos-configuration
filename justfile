# 获取默认用户与主机名
DEFAULT_USER := `whoami`
DEFAULT_HOST := `hostname`
# 计算 user@host 作为默认 Home Manager 目标
DEFAULT_TARGET := `printf '%s@%s' "$(whoami)" "$(hostname)"`

# 常用命令前缀（启用 flakes 与 nix-command）
NIXCMD := "nix --extra-experimental-features 'nix-command flakes'"
HM := "github:nix-community/home-manager"

# 默认显示所有可用命令列表
default:
    @just --list

# 检查flake.nix语法
check:
    {{NIXCMD}} flake check --option eval-cache true --accept-flake-config

# 更快的仅评估（推荐在开发时使用）
check-fast:
    nix flake check --no-build --no-update-lock-file --option eval-cache true --accept-flake-config

# 仅评估单个主机（最快速的健康检查）
eval-host host=DEFAULT_HOST:
    nix eval .#nixosConfigurations.{{host}}.config.system.build.toplevel.drvPath

# 仅评估单个 Home Manager 目标
eval-home target=DEFAULT_TARGET:
    nix eval .#homeConfigurations."{{target}}".activationPackage.drvPath

# 更新flake.lock中的依赖
update:
    nix flake update

# 更新特定输入源
update-input input:
    nix flake lock --update-input {{input}}

# 构建指定主机的系统配置
build host=DEFAULT_HOST:
    nixos-rebuild build --flake .#{{host}}

# 构建并切换到指定主机的系统配置
switch host=DEFAULT_HOST:
    sudo -E nixos-rebuild switch --flake .#{{host}}

# 构建并切换到指定主机的系统配置(以boot方式)
boot host=DEFAULT_HOST:
    sudo -E nixos-rebuild boot --flake .#{{host}}

# 清理nix存储
gc:
    sudo nix-collect-garbage -d

# 清理旧代(older generations)
gc-old:
    sudo nix-collect-garbage --delete-old

# 输出系统配置的flake输出
show-systems:
    nix flake show --json | jq '.nixosConfigurations'

# 虚拟机测试指定主机的配置
vm host=DEFAULT_HOST:
    nixos-rebuild build-vm --flake .#{{host}}

# 列出系统中所有的generations（世代）
list-generations:
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# 回滚到上一个系统generation
rollback:
    sudo nixos-rebuild --rollback switch

# 格式化所有的nix文件
fmt:
    nixfmt .
# --- Agenix Secret Management (Python based, user-friendly) ---

# 列出密钥或机密文件
# Usage: just secret-list keys [--filter users|hosts|groups]
# Usage: just secret-list secrets
# Usage: just secret-list all
secret-list type="all" filter="all":
    ./scripts/secretctl.py list {{type}} --filter {{filter}}

# 添加新密钥
# Usage: just secret-add-key user <name> <ssh-pubkey> [--path <private-key-path>]
# Usage: just secret-add-key host <name> <ssh-pubkey> [--path <private-key-path>]
secret-add-key type name key path="":
    ./scripts/secretctl.py add-key {{type}} {{name}} {{key}} --path {{path}}

# 移除密钥
# Usage: just secret-remove-key user <name>
# Usage: just secret-remove-key host <name>
secret-remove-key type name:
    ./scripts/secretctl.py remove-key {{type}} {{name}}

# 生成新密钥对 (age 格式)
# Usage: just secret-generate user <name>
# Usage: just secret-generate host <name>
secret-generate type name:
    ./scripts/secretctl.py generate {{type}} {{name}}

# 添加新的机密映射到 secrets.nix
# Usage: just secret-add-mapping <file.age> <recipients> <target-path> <owner> <group> [--mode <mode>]
# Example: just secret-add-mapping api-key.age "keyGroups.nuc ++ keyGroups.longred" /etc/secrets/api-key root root --mode 600
secret-add-mapping name recipients target owner group mode="600":
    ./scripts/secretctl.py add-mapping {{name}} {{recipients}} {{target}} {{owner}} {{group}} --mode {{mode}}

# 加密文件（支持密钥组名，自动展开）
# Usage: just secret-encrypt <file> --recipients <key1> <keyGroup.name> ... [--output <outfile.age>]
# Example: just secret-encrypt secrets/db-pass --recipients keyGroups.nuc keyGroups.longred
secret-encrypt file *args:
    ./scripts/secretctl.py encrypt {{file}} {{args}}

# 编辑机密文件
# Usage: just secret-edit <file.age> [--identity <private-key-path>]
secret-edit file identity="":
    #!/usr/bin/env bash
    if [ -z "{{identity}}" ]; then
        ./scripts/secretctl.py edit {{file}}
    else
        ./scripts/secretctl.py edit {{file}} --identity {{identity}}
    fi

# 更改机密文件的接收者（支持密钥组名）
# Usage: just secret-rekey <file.age> --recipients <key1> <keyGroup.name> ... [--identity <private-key-path>]
secret-rekey file *args:
    ./scripts/secretctl.py rekey {{file}} {{args}}

# 检查密钥和机密文件一致性
# Checks if all .age files have mappings and vice versa
secret-check:
    ./scripts/secretctl.py check

# 安全切换 - 在切换前检查密钥一致性
switch-safe host=DEFAULT_HOST:
    just secret-check && just switch {{host}}

# --- Home Manager: Standalone (非 NixOS 主机) ---

# 展示 flake 中的 Home Manager 配置
hm-show:
    {{NIXCMD}} flake show --json | jq '.homeConfigurations'

# 构建 Home Manager 激活包（不应用）
hm-build target=DEFAULT_TARGET:
    {{NIXCMD}} build .#homeConfigurations."{{target}}".activationPackage -L

# 干跑切换（仅预览变更）
hm-dry-run target=DEFAULT_TARGET:
    {{NIXCMD}} run {{HM}} -- switch --flake .#{{target}} --dry-run

# 切换并自动备份 HOME 中冲突文件
hm-switch target=DEFAULT_TARGET:
    {{NIXCMD}} run {{HM}} -- switch --flake .#{{target}} -b backup

# 无备份直接切换（谨慎使用）
hm-switch-no-backup target=DEFAULT_TARGET:
    {{NIXCMD}} run {{HM}} -- switch --flake .#{{target}}

# 查看 Home Manager news 提示
hm-news:
    {{NIXCMD}} run {{HM}} -- news

# 列出 Home Manager generations
hm-generations:
    {{NIXCMD}} run {{HM}} -- generations

# 回滚到上一个 Home Manager generation
hm-rollback:
    {{NIXCMD}} run {{HM}} -- rollback

# 安装 home-manager CLI（可选）
hm-install-cli:
    {{NIXCMD}} profile install {{HM}}#home-manager

# 查看 home-manager 版本（通过一次性运行）
hm-version:
    {{NIXCMD}} run {{HM}} -- --version
