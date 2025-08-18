# NixOS Configuration
<!-- Add Flakes badge -->
[![Nix Flake](https://img.shields.io/badge/flake-supported-brightgreen)](https://nixos.wiki/wiki/Flakes)

本仓库是基于 Nix Flakes 和 Home Manager 的 NixOS 配置集合，支持多主机和多用户的模块化管理。

## Table of Contents

- [NixOS Configuration](#nixos-configuration)
  - [Table of Contents](#table-of-contents)
  - [项目结构](#项目结构)
    - [迁移说明（Breaking changes）](#迁移说明breaking-changes)
  - [如何添加新系统](#如何添加新系统)
    - [1) 新增 NixOS 主机（物理机/VM）](#1-新增-nixos-主机物理机vm)
    - [2) 新增 WSL 主机（Windows 子系统）](#2-新增-wsl-主机windows-子系统)
    - [3) 新增 Home Manager（非 NixOS 主机）](#3-新增-home-manager非-nixos-主机)
    - [机密与密钥（可选）](#机密与密钥可选)
  - [常用命令](#常用命令)
    - [评估/检查](#评估检查)
    - [NixOS 系统](#nixos-系统)
    - [Home Manager（可用于非 NixOS）](#home-manager可用于非-nixos)
    - [机密（agenix + scripts/secretctl.py）](#机密agenix--scriptssecretctlpy)
    - [维护](#维护)
  - [开发指南](#开发指南)
  - [Contributing](#contributing)
  - [License](#license)

## 项目结构

```text
.
├── flake.nix                # Flake 入口，定义 inputs/outputs
├── flake.lock               # Flake 锁定文件
├── hosts/                   # 各主机专属配置
│   └── <hostname>/          # 某主机的配置目录
│       ├── configuration.nix # NixOS 系统配置（原 nixos.nix）
│       ├── home.nix           # Home Manager 用户配置
│       └── hardware-configuration.nix # 硬件配置（自动生成）
├── modules/                 # 可复用模块
│   ├── system/                # NixOS 公共模块（原 modules/nixos）
│   ├── home-manager/          # Home Manager 公共模块
│   ├── services/              # 自定义服务模块（如 dufs、deeplx 等）
│   └── overlays.nix           # overlay 配置（如引入 unstable 包）
├── users/                   # 用户专属配置
│   └── <username>/            # 某用户的配置
│       └── default.nix
├── secrets/                 # 机密管理（如 agenix）
│   └── secrets.nix
├── justfile                 # 常用命令任务定义
└── README.md                # 项目说明文档
```

### 迁移说明（Breaking changes）

- 主机入口文件从 `hosts/<name>/nixos.nix` 重命名为 `hosts/<name>/configuration.nix`。
- 系统公共模块从 `modules/nixos/*` 迁移到 `modules/system/*`。
- `flake.nix` 中每台主机的 `modules = [...]` 已指向新路径，无需额外操作。

## 如何添加新系统

下面示例展示三种新增方式：NixOS 主机、WSL 主机和仅使用 Home Manager 的非 NixOS 主机。

提示：本仓库的 `justfile` 已提供快速评估与切换命令，默认目标为当前 `hostname` 与 `whoami`，可通过 `host=` 或 `target=` 参数覆盖。

### 1) 新增 NixOS 主机（物理机/VM）

1. 新建目录与文件：
   - `hosts/<hostname>/configuration.nix`
   - `hosts/<hostname>/home.nix`
   - 安装后复制系统生成的 `hardware-configuration.nix` 到 `hosts/<hostname>/`（首次部署于目标机器上完成）。
2. 在 `configuration.nix` 导入公共模块（按需取用）：
   - `./../../modules/system/common.nix`
   - 桌面：`./../../modules/system/desktop/kde.nix`、`./../../modules/system/wayland.nix`
   - 音频：`./../../modules/system/audio/pipewire.nix`
   - 硬件：`./../../modules/system/hardware/intel.nix`
   - 其他：`./../../modules/system/apps/flatpak.nix`
   - 以及 `inputs.home-manager.nixosModules.home-manager`、`inputs.nix-index-database.nixosModules.nix-index`
3. 在 `hosts/<hostname>/home.nix` 里按需引入 `modules/home-manager/*` 共享模块与用户个性化配置。
4. 在 `flake.nix` 的 `nixosConfigurations` 中复制一段现有主机条目，改为你的 `hostname` 和 `username`，并指向新的目录：
   - `./modules/overlays.nix`
   - `./hosts/<hostname>/configuration.nix`
   - `./hosts/<hostname>/home.nix`
   - `./users/<username>`
5. 评估与切换：
   - 评估：`just eval-host host=<hostname>`
   - 切换：`just switch host=<hostname>`（在目标 NixOS 机器上执行）

常见问题：

- 缺少 `hardware-configuration.nix`：需要在目标机上先执行一次 `nixos-generate-config` 并复制生成文件。
- Unfree 包报错：仓库已在 overlays 中全局开启 `allowUnfree`，若你新增了独立的 `nixpkgs` 导入，请确保同步配置。

### 2) 新增 WSL 主机（Windows 子系统）

WSL 与 NixOS 主机步骤类似，但需要导入 WSL 专属模块：

1. 在 `hosts/<hostname>/configuration.nix` 的 `imports` 中加入：
   - `inputs.nixos-wsl.nixosModules.wsl`
   - `./../../modules/system/wsl.nix`
   - 以及第 1) 步骤中的通用导入（如 `common.nix`、`home-manager` 模块等）。
2. 其余步骤与 NixOS 主机相同，仍需在 `flake.nix` 中添加主机条目。
3. 评估与应用：
   - 评估：`just eval-host host=<hostname>`
   - 切换：在该 WSL 实例中执行 `just switch host=<hostname>`

提示：WSL 图形/音频通常依赖宿主机，已在 `modules/system/wsl.nix` 与示例主机中提供基础设置，按需覆盖即可。

### 3) 新增 Home Manager（非 NixOS 主机）

适用于 macOS、Ubuntu/Fedora 等通过 nix 安装 Home Manager 的场景。

1. 新建用户配置模块，例如：`users/<username>/home-<host>.nix`。
   - 复用 `modules/home-manager/common.nix`、`shell/*`、`desktop/*` 等共享模块。
2. 在 `flake.nix` 的 `homeConfigurations` 中复制现有条目（例如 `"longred@thinkbook-fedora"`），修改：
   - `pkgs`：保留 `pkgsFor nixpkgs overlays`（已包含 overlays 与 `allowUnfree`）。
   - `extraSpecialArgs`：设置你的 `username`、`hostname`。
   - `modules`：指向你在第 1 步创建的文件。
3. 评估与切换（在该非 NixOS 主机上执行）：
   - 评估：`just eval-home target='<username>@<host>'`
   - 预览：`just hm-dry-run target='<username>@<host>'`
   - 切换：`just hm-switch target='<username>@<host>'`

备注：Home Manager-only 场景请勿在个人模块里再次导入/覆盖 `nixpkgs` 或 overlays，flake 已统一注入。

### 机密与密钥（可选）

若新主机需要机密文件（agenix）：

1. 为主机/用户添加密钥：`just secret-generate host <hostname>` 或 `just secret-generate user <username>`。
2. 将 `.age` 文件映射到 `secrets/secrets.nix`：
   - 使用 `just secret-add-mapping <file.age> <recipients> <target> <owner> <group> [--mode <mode>]`
3. 加密或编辑机密文件：`just secret-encrypt` / `just secret-edit`。
4. 切换前可执行 `just switch-safe host=<hostname>` 做一致性检查。

## 常用命令

本项目使用 [`just`](https://github.com/casey/just) 作为任务运行器。未显式指定时，`host` 与 `target` 默认取当前 `hostname` 与 `whoami`。

### 评估/检查

- `just`                        # 列出所有可用任务
- `just check`                  # 完整检查 flake 配置
- `just check-fast`             # 更快的仅评估（不构建）
- `just eval-host host=<h>`     # 评估某 NixOS 主机 toplevel
- `just eval-home target='<u@h>'` # 评估某 Home Manager 目标
- `just show-systems`           # 查看 flake 中的 nixosConfigurations

### NixOS 系统

- `just build host=<h>`         # 构建系统
- `just switch host=<h>`        # 构建并切换系统
- `just boot host=<h>`          # 构建并切换为下次启动生效
- `just vm host=<h>`            # 以 VM 测试该主机配置
- `just list-generations`       # 列出系统 generations
- `just rollback`               # 回滚到上一个系统 generation

### Home Manager（可用于非 NixOS）

- `just hm-show`                        # 展示 flake 中的 HM 配置
- `just hm-build target='<u@h>'`        # 构建 HM 激活包
- `just hm-dry-run target='<u@h>'`      # 干跑预览变更
- `just hm-switch target='<u@h>'`       # 切换并备份冲突文件
- `just hm-switch-no-backup target='<u@h>'` # 无备份直接切换
- `just hm-generations`                 # 列出 HM generations
- `just hm-rollback`                    # 回滚到上一个 HM generation
- `just hm-news`                        # 查看 HM 提示/新闻
- `just hm-install-cli`                 # 安装 home-manager CLI（可选）
- `just hm-version`                     # 查看 home-manager 版本

### 机密（agenix + scripts/secretctl.py）

- `just secret-list type="all|keys|secrets" [filter="all|users|hosts|groups"]`
- `just secret-add-key type [user|host] name <ssh-pubkey> [path="..."]`
- `just secret-remove-key type [user|host] name`
- `just secret-generate type [user|host] name`
- `just secret-add-mapping <file.age> <recipients> <target> <owner> <group> [mode="600"]`
- `just secret-encrypt <file> --recipients <k1> <kGroup.name> ... [--output <out.age>]`
- `just secret-edit <file.age> [identity="/path/to/private.key"]`
- `just secret-rekey <file.age> --recipients <...>`
- `just secret-check`                     # 校验密钥与机密映射的一致性
- `just switch-safe host=<h>`             # 校验通过后切换系统

### 维护

- `just fmt`               # 格式化所有 nix 文件
- `just update`            # 更新 flake.lock
- `just update-input <in>` # 更新特定 flake 输入
- `just gc`                # 清理 nix 存储
- `just gc-old`            # 清理旧 generations

更多命令与参数细节请查看根目录 `justfile`。

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
