# Nix 配置仓库

这个仓库使用 Nix Flakes 和 Home Manager 管理 NixOS、WSL 以及非 NixOS 主机上的用户环境。服务模块以用户级 systemd 单元为主，机密使用 Agenix 加密文件保存。

## 从哪里开始

- [项目文档索引](docs/README.md)：部署、服务、观测、Tailscale 和机密管理的入口。
- [AGENTS.md](AGENTS.md)：修改代码和文档时必须遵守的仓库约定。
- [justfile](justfile)：可执行任务和验证命令。

## 仓库结构

```text
.
├── flake.nix                         # Flake 输入和输出
├── hosts/                            # NixOS 主机入口
├── users/                            # 用户及 standalone Home Manager 入口
├── modules/
│   ├── home-manager/                 # 通用、桌面、Shell 和 WSL 模块
│   ├── host-services/                # 用户级服务及其运行时配置
│   └── overlays.nix                  # nixpkgs overlay
├── config/                           # 非 Nix 的声明式配置
├── pkgs/                             # 本地 Nix 包
├── scripts/                          # 辅助脚本
├── secrets/*.age                     # 仅提交加密后的机密
└── docs/                             # 运维文档和可导入模板
```

Flake 当前提供两类输出：`nixosConfigurations` 用于 NixOS/WSL，`homeConfigurations` 用于 standalone Home Manager。具体目标名称以 `just show-systems` 和 `just show-homes` 的输出为准，不要把某台机器的名称或地址写进通用文档。

## 常用命令

```bash
# 查看任务
just

# 快速检查 Flake
just check-fast

# 完整检查
just check

# 格式化 Nix
just fmt

# 预览或切换 standalone Home Manager
just hm-dry-run '<user>@<host>'
just hm-switch '<user>@<host>'

# 构建或切换 NixOS
just build '<host>'
just switch-nixos '<host>'
```

修改前先确认目标属于 NixOS 还是 standalone Home Manager。部署后应检查对应的 systemd 单元和健康接口；只通过静态评估不能证明远端服务已经生效。

## 配置原则

- Nix 模块和 `config/` 中的声明文件是运行时配置的来源；文档只解释它们，不复制一份容易过期的完整配置。
- `secrets/*.age` 可以提交，明文机密、解密结果、API token、密码、私钥和带 token 的 URL 不能提交、粘贴到文档或写入日志。
- 文档示例使用 `<user>`、`<host>`、`<service-domain>`、`<tailnet-ip>`、`<data-root>` 等占位符。
- 版本、状态、已验证主机和看板 ID 都属于容易过时的信息；除非记录了验证日期和证据，否则不要写进长期文档。

## 许可

仓库当前没有提交许可证文件。若需要对外发布，请先补充许可证并同步更新文档。
