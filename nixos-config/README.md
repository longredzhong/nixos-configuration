# NixOS 配置

这是我的个人 NixOS 配置仓库，用于管理多个系统的 NixOS 配置。

## 概述

这个仓库包含了我的 NixOS 系统配置和 Home Manager 配置，支持多种环境，包括 WSL 和物理机器。

## 支持的系统

- **thinkbook-wsl**: ThinkBook 笔记本上的 WSL 环境
- **metacube-wsl**: Metacube 主机上的 WSL 环境
- **nuc**: Intel NUC 物理机器
- **vm**: 虚拟机环境

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
│   ├── modules/         # NixOS 模块
│   │   ├── core/        # 核心模块，包含通用配置
│   │   │   └── default.nix
│   │   └── services/    # 服务模块，包含各种服务的配置
│   │       ├── dufs.nix
│   │       ├── k3s.nix
│   │       └── cloudflared.nix
├── hosts/               # 主机特定配置
│   ├── wsl/           # WSL 特定配置
│   │   └── default.nix
│   ├── nuc/           # NUC 特定配置
│   │   └── default.nix
│   └── vm/            # 虚拟机特定配置
│       └── default.nix
```

## 特性

- 使用 Nix Flake 管理依赖和配置
- 通过 Home Manager 管理用户环境
- 支持 WSL 环境 (通过 [nixos-wsl](https://github.com/nix-community/NixOS-WSL))
- 集成了 [NUR](https://github.com/nix-community/NUR)
- 集成了 [nix-index-database](https://github.com/Mic92/nix-index-database) 用于命令查找
- 包含了 [JeezyVim](https://github.com/LGUG2Z/JeezyVim) 配置
- 模块化配置，易于维护和扩展
- 通用配置和主机特定配置分离

## 使用方法

### 构建并激活配置

```bash
# 针对特定主机构建，例如构建 thinkbook-wsl 配置
sudo nixos-rebuild switch --flake .#thinkbook-wsl
```

### 更新系统

```bash
# 更新 flake 输入并重建系统
sudo nixos-rebuild switch --flake .#主机名 --update-input nixpkgs
```

### 测试配置

使用以下命令对 flake 进行检查和测试，确保配置无误：

```bash
nix flake check
```

### 虚拟机模式

针对虚拟机环境（例如 `vm-test` 配置），可以使用以下命令构建和运行虚拟机：

```bash
nixos-rebuild build-vm --flake .#vm-test
./result/bin/run-nixos-vm
```

另外，可以构建带持久存储的虚拟机：

```bash
nixos-rebuild build-vm-with-bootloader --flake .#vm-test
```

## 自定义

要添加新的系统配置，请按照以下步骤操作：

1.  在 `flake.nix` 中添加新的 `nixosConfigurations` 条目  
2.  创建系统特定的配置目录，例如 `hosts/new-host/`  
3.  在 `hosts/new-host/default.nix` 中导入 `core` 模块和任何其他需要的模块  
4.  根据需要自定义 `home-manager` 配置

## 依赖

- nixpkgs (24.11 稳定版)
- nixpkgs-unstable (用于特定的软件包)
- home-manager
- nixos-wsl (WSL 支持)
- nix-index-database
- JeezyVim

## 安全注意事项

- 请勿公开分享 `secrets.json` 文件，该文件包含敏感信息。
- 在生产环境中，请使用更安全的 SSH 配置，例如禁用密码登录，使用密钥登录。
- 定期更新系统和软件包，以修复安全漏洞。