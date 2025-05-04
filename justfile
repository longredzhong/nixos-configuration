# 获取当前主机名作为默认值
DEFAULT_HOST := `hostname`

# 默认显示所有可用命令列表
default:
    @just --list

# 检查flake.nix语法
check:
    nix flake check

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
    nixpkgs-fmt $(find . -name "*.nix")

# --- Agenix Secret Management ---

# Encrypt a file using age for specified hosts/users/keys
# Usage: just encrypt <file> --host <h1> --user <u1> --key <age_key> ...
# Example: just encrypt secrets/db-pass --host nuc --user longred
# Example: just encrypt secrets/api-token --key age1...
encrypt file *args:
    #!/usr/bin/env bash
    set -euo pipefail
    input_file="{{file}}"
    # Ensure the input file exists
    if [[ ! -f "$input_file" ]]; then
        echo "Error: Input file '$input_file' not found."
        exit 1
    fi

    # Default output file path (e.g., secrets/db-pass -> secrets/db-pass.age)
    output_file="${input_file}.age"

    # Check if output file already exists
    if [[ -e "$output_file" ]]; then
        read -p "Output file '$output_file' already exists. Overwrite? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    # 直接拿到一行带引号的 -r 参数
    recipient_flags=$(./scripts/get-age-keys.sh {{args}})
    if [[ -z "$recipient_flags" ]]; then
        echo "Error: Failed to get recipient keys. No flags generated."
        exit 1
    fi

    echo "Encrypting '$input_file' to '$output_file'..."
    # 用 eval 让 shell 保留双引号
    # Debug: print the age command before executing
    echo "Debug: age $recipient_flags -o $output_file $input_file"
    eval age $recipient_flags -o "$output_file" "$input_file"

    echo "Encryption complete: $output_file"
    echo ""
    echo "IMPORTANT:"
    echo "1. Add the definition for '$output_file' to 'secrets/secrets.nix'."
    echo "2. Update the 'secretRecipients' map in 'secrets/secrets.nix' for '$output_file'."
    echo "3. Delete the plaintext file '$input_file'."
    echo "4. Commit '$output_file' and the changes to 'secrets.nix'."

# Decrypt, edit-age, and re‑encrypt an existing .age file
# Usage: just edit-age <file.age> [--identity <keyfile>]
edit-age file_age *args:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/edit-age.sh "{{file_age}}" {{args}}

# Rekey (change recipients) of an existing .age file
# Usage: just rekey <file.age> [--identity <keyfile>] --host <h> --user <u> ...
rekey-age file_age *args:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/rekey-age.sh "{{file_age}}" {{args}}
