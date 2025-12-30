# NixOS Configuration

[![Nix Flake](https://img.shields.io/badge/flake-supported-brightgreen)](https://nixos.wiki/wiki/Flakes)

基于 Nix Flakes 和 Home Manager 的模块化 NixOS 配置。

## 项目结构

```text
.
├── flake.nix              # Flake 入口
├── hosts/                 # 主机配置
│   └── <hostname>/
│       ├── configuration.nix  # 系统配置
│       ├── home.nix           # Home Manager 配置
│       └── hardware-configuration.nix
├── modules/
│   ├── system/            # NixOS 公共模块
│   ├── home-manager/
│   │   ├── profiles/      # 配置组合 (desktop/wsl/minimal)
│   │   ├── desktop/       # 桌面环境模块
│   │   └── shell/         # Shell 工具模块
│   ├── services/          # 自定义服务
│   └── overlays.nix       # Overlay 配置
├── users/                 # 用户配置
├── secrets/               # 机密管理 (agenix)
└── justfile               # 任务命令
```

## 快速开始

```bash
# 查看所有命令
just

# 检查配置
just check-fast

# 切换系统 (NixOS)
just switch

# 切换 Home Manager (非 NixOS)
just hm-switch
```

## 添加新主机

### NixOS 主机

1. 创建 `hosts/<hostname>/` 目录，包含 `configuration.nix` 和 `home.nix`
2. 在 `flake.nix` 添加：
   ```nix
   nixosConfigurations.<hostname> = mkHost { hostname = "<hostname>"; };
   ```
3. 运行 `just switch host=<hostname>`

### Home Manager (非 NixOS)

1. 创建 `users/<username>/<hostname>.nix`
2. 在 `flake.nix` 的 `homeConfigurations` 添加配置
3. 运行 `just hm-switch target='<user>@<host>'`

## 常用命令

| 命令 | 说明 |
|------|------|
| `just check-fast` | 快速检查配置 |
| `just switch` | 切换 NixOS 系统 |
| `just hm-switch` | 切换 Home Manager |
| `just build` | 构建系统 |
| `just vm` | VM 测试 |
| `just update` | 更新依赖 |
| `just fmt` | 格式化代码 |
| `just gc` | 清理存储 |

## Profiles (配置组合)

| Profile | 用途 | 包含模块 |
|---------|------|----------|
| `desktop` | 桌面环境 | common + cli + desktop |
| `wsl` | WSL 环境 | common + cli + wsl |
| `minimal` | 最小化 | common + cli |

在 `hosts/<hostname>/home.nix` 中使用：
```nix
imports = [ ../../modules/home-manager/profiles/desktop.nix ];
```

## License

[MIT](LICENSE)
