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

# 应用home-manager配置
home host=DEFAULT_HOST user="longred":
    home-manager switch --flake .#{{user}}@{{host}}

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

# 创建新主机配置
create-host host:
    @mkdir -p hosts/{{host}}
    @echo "{ config, pkgs, lib, ... }:\n\n{\n  imports = [\n    ./hardware-configuration.nix\n  ];\n\n  # 在此处添加特定于主机的配置\n\n}" > hosts/{{host}}/default.nix
    @echo "{ config, pkgs, lib, ... }:\n\n{\n  # 硬件配置\n  boot.initrd.availableKernelModules = [ ];\n  boot.initrd.kernelModules = [ ];\n  boot.kernelModules = [ ];\n  boot.extraModulePackages = [ ];\n\n  # 在此处添加硬件特定配置\n\n}" > hosts/{{host}}/hardware-configuration.nix
    @echo "已创建 hosts/{{host}} 目录和基本配置文件"