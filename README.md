# NixOS Configuration

这个仓库包含了我的NixOS系统配置代码。

## 项目结构

```bash
.
├── README.md
├── flake.lock
├── flake.nix          # 项目主入口，定义系统配置和输出
├── home/              # 用户环境配置
│   ├── cli-environment.nix # CLI环境聚合配置
│   ├── shell/         # Shell相关配置
│   │   ├── fish.nix   # Fish shell配置
│   │   ├── atuin.nix  # Shell历史同步工具
│   │   ├── starship.nix # 终端提示符
│   │   ├── git.nix    # Git配置
│   │   └── tmux.nix   # Tmux配置
│   ├── editors/       # 编辑器配置
│   ├── wsl.nix        # WSL特定配置
│   └── monitoring.nix # 系统监控工具配置
├── hosts/             # 主机特定配置
│   ├── metacube-wsl/  # MetaCube WSL配置
│   ├── nuc/           # NUC设备配置
│   └── thinkbook-wsl/ # ThinkBook WSL配置
├── justfile           # Just任务运行器配置
├── modules/           # 可重用的配置模块
│   ├── common.nix     # 通用配置
│   ├── overlays.nix   # 软件包覆盖配置
│   └── services/      # 服务配置
│       └── deeplx.nix # DeepLX翻译服务
└── users/             # 用户配置
    └── longred.nix    # 用户longred的配置
```

## 系统概览

这个NixOS配置项目管理了三个环境：

- 两个WSL实例：`metacube-wsl` 和 `thinkbook-wsl`
- 一个物理机：`nuc`

所有环境都使用统一的配置管理方式，通过Nix Flakes实现可重现的系统构建。

### 主要功能

- **模块化设计**：通过模块化设计实现配置复用
- **多环境支持**：同时管理WSL和物理机环境
- **Home Manager集成**：使用Home Manager管理用户环境
- **增强的CLI体验**：配置了Fish shell、Starship提示符、Git等工具
- **WSL特定优化**：为WSL环境提供了特定优化和Windows集成

## 使用方法

### 系统安装/更新

```bash
# 使用nixos-rebuild切换到此配置
sudo nixos-rebuild switch --flake .#hostname
```

其中`hostname`可以是：

- `metacube-wsl`：MetaCube WSL环境
- `thinkbook-wsl`：ThinkBook WSL环境
- `nuc`：NUC物理机

## 定制指南

### 添加新软件包

在`users/longred.nix`中的`packages`列表中添加软件包：

```nix
home.packages = with pkgs; [
  # 添加新软件包
  neofetch
  btop
];
```

### 修改现有配置

大多数用户级配置位于`home/`目录中，按功能分类整理。
