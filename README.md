# NixOS Configuration
<!-- Add Flakes badge -->
[![Nix Flake](https://img.shields.io/badge/flake-supported-brightgreen)](https://nixos.wiki/wiki/Flakes)

本仓库是基于 Nix Flakes 和 Home Manager 的 NixOS 配置集合，支持多主机和多用户的模块化管理。

## Table of Contents
- [NixOS Configuration](#nixos-configuration)
  - [Table of Contents](#table-of-contents)
  - [项目结构](#项目结构)
  - [常用命令](#常用命令)
  - [开发指南](#开发指南)
  - [Contributing](#contributing)
  - [License](#license)

## 项目结构

```
.
├── flake.nix                # Flake 入口，定义 inputs/outputs
├── flake.lock               # Flake 锁定文件
├── hosts/                   # 各主机专属配置
│   └── <hostname>/          # 某主机的配置目录
│       ├── nixos.nix          # NixOS 系统配置
│       ├── home.nix           # Home Manager 用户配置
│       └── hardware-configuration.nix # 硬件配置（自动生成）
├── modules/                 # 可复用模块
│   ├── nixos/                 # NixOS 公共模块
│   ├── home-manager/          # Home Manager 公共模块
│   └── overlays.nix           # overlay 配置（如引入 unstable 包）
├── users/                   # 用户专属配置
│   └── <username>/            # 某用户的配置
│       └── default.nix
├── secrets/                 # 机密管理（如 agenix）
│   └── secrets.nix
├── justfile                 # 常用命令任务定义
└── README.md                # 项目说明文档
```

## 常用命令

本项目推荐使用 [`just`](https://github.com/casey/just) 作为任务运行器，常用命令如下：

- `just`                  # 显示所有可用命令
- `just check`            # 检查 flake 配置语法
- `just fmt`              # 格式化所有 nix 文件
- `just update`           # 更新 flake.lock 依赖
- `just switch`           # 构建并切换当前主机系统配置
- `just build`            # 仅构建当前主机系统配置
- `just vm`               # 构建并测试 VM
- `just gc`               # 清理 nix 存储
- `just gc-old`           # 清理旧 generations
- `just rollback`         # 回滚到上一个系统 generation
- `just encrypt <file> --host <h> --user <u> ...` # 加密文件
- `just edit-age <file.age> [--identity <key>]`       # 编辑加密文件
- `just rekey-age <file.age> --host <h> --user <u> ...` # 更改加密文件的接收者

更多命令请查看 `justfile`。

## 开发指南

1. **修改配置**：根据需要编辑 `hosts/`、`modules/`、`users/` 下的 `.nix` 文件。
2. **格式化代码**：执行 `just fmt` 保持代码风格统一。
3. **检查语法**：执行 `just check` 验证 flake 配置。
4. **测试变更**：
   - 系统配置：`just build` 或 `just vm`
5. **应用变更**：
   - 系统配置：`just switch`
6. **提交规范**：建议遵循 Conventional Commits 规范（VSCode 用户可参考 `.vscode/settings.json` 自动生成规范提交信息）。

---

如需自定义主机或用户，建议复制现有目录结构并按需调整。

## Contributing

We welcome contributions! Please:
- Fork the repo and create a feature branch.
- Follow Conventional Commits for commit messages.
- Run `just fmt` and `just check` before submitting a PR.

## License

This repository is licensed under [MIT](LICENSE).