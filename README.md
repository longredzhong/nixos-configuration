# Nix Configuration

This repository is home to the nix code that builds my systems.

## 项目结构

```bash
.
├── README.md
├── flake.lock
├── flake.nix
├── home/
│   ├── atuin.nix
│   ├── fish.nix
│   ├── git.nix
│   └── starship.nix
├── hosts/
│   ├── metacube-wsl/
│   ├── nuc/
│   └── thinkbook-wsl/
├── justfile
├── modules/
│   ├── common.nix
│   └── services/
│       └── deeplx.nix
└── users/
```

## 使用方法

### 系统安装

```bash
# 使用nixos-rebuild切换到此配置
sudo nixos-rebuild switch --flake .#<hostname>
```

### Home Manager配置应用

```bash
# 应用home-manager配置
home-manager switch --flake .#<username>@<hostname>
```

## 文件说明

- `flake.nix`: 项目入口，定义了系统配置和输出
- `home/`: 包含所有用户环境配置
  - `fish.nix`: Fish shell配置
  - `atuin.nix`: Atuin shell历史同步工具配置
  - `git.nix`: Git配置
  - `starship.nix`: Starship提示符配置
- `hosts/`: 包含各主机特定配置
  - `metacube-wsl/`: MetaCube WSL配置
  - `nuc/`: NUC设备配置
  - `thinkbook-wsl/`: ThinkBook WSL配置
- `modules/`: 包含可重用的配置模块
  - `common.nix`: 通用配置
  - `services/`: 服务配置
    - `deeplx.nix`: DeepLX翻译服务配置
- `users/`: 用户配置
- `justfile`: Just任务运行器配置文件
