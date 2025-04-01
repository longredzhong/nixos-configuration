# NixOS 配置

这是我的个人 NixOS 配置仓库，用于管理多个系统的 NixOS 配置。

## 概述

这个仓库包含了我的 NixOS 系统配置和 Home Manager 配置，支持多种环境，包括 WSL 和物理机器。

## 支持的系统

- **thinkbook-wsl**: ThinkBook 笔记本上的 WSL 环境
- **metacube-wsl**: Metacube 主机上的 WSL 环境
- **nuc**: Intel NUC 物理机器

## 目录结构

```
.
├── flake.nix            # Nix Flake 配置入口
├── secrets.json         # 敏感配置信息（不要公开分享）
├── nixos-config/        # NixOS 系统配置
│   ├── home-manager/    # Home Manager 用户环境配置
│   │   ├── default.nix  # 基本配置
│   │   ├── cli.nix      # 命令行工具配置
│   │   └── editors.nix  # 编辑器配置
├── wsl/                 # WSL 特定配置
└── nuc/                 # NUC 特定配置
```

## 特性

- 使用 Nix Flake 管理依赖和配置
- 通过 Home Manager 管理用户环境
- 支持 WSL 环境 (通过 nixos-wsl)
- 集成了 NUR (Nix User Repository)
- 集成了 nix-index-database 用于命令查找
- 包含了 JeezyVim 配置

## 使用方法

### 构建并激活配置

```bash
# 针对特定主机构建
sudo nixos-rebuild switch --flake .#主机名

# 示例：构建 thinkbook-wsl 配置
sudo nixos-rebuild switch --flake .#thinkbook-wsl
```

### 更新系统

```bash
# 更新 flake 输入并重建系统
sudo nixos-rebuild switch --flake .#主机名 --update-input nixpkgs
```

## 自定义

要添加新的系统配置，请按照以下步骤操作：

1. 在 flake.nix 中添加新的 nixosConfigurations 条目
2. 创建系统特定的配置目录
3. 根据需要自定义 home-manager 配置

## 依赖

- nixpkgs (24.11 稳定版)
- nixpkgs-unstable (用于特定的软件包)
- home-manager
- nixos-wsl (WSL 支持)
- nix-index-database
- JeezyVim
