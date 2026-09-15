# AGENTS.md

## 适用范围

本文件适用于整个仓库。目录中没有更具体的 `AGENTS.md` 时，所有 Nix、脚本、配置和文档修改都遵守这里的约定。

## 项目边界

- `flake.nix` 定义 NixOS 和 standalone Home Manager 的目标。
- `hosts/` 是 NixOS 主机入口；`users/` 是用户和 standalone Home Manager 入口。
- `modules/host-services/` 保存用户级 systemd 服务及其运行时配置。
- `config/` 保存服务声明文件；`docs/` 只提供说明和模板。
- `secrets/*.age` 是加密机密。解密后的文件、运行时 env、token、密码和私钥不属于仓库内容。

## 修改流程

1. 先检查 `git status`、目标 Flake 输出、相关模块和文档索引。
2. 保持修改范围聚焦；只暂存本次任务涉及的文件，保留其他工作树改动。
3. 代码或配置修改至少运行：

   ```bash
   git diff --check
   just check-fast
   ```

4. Nix 模块涉及目标输出时，再运行对应的 `just eval-home`、`just eval-host` 或 `just hm-dry-run`。
5. 请求部署时，先完成静态检查，再切换目标并检查 systemd 状态、日志和健康接口。静态检查、远端部署和实际业务验证要分别报告。
6. 提交使用聚焦的本地 commit。除非用户明确要求，不推送、合并或修改远端分支。

## 机密和敏感信息

- 不读取、打印或复制明文机密到终端输出、补丁、文档、截图或提交信息。
- 不在文档中写真实 API key、Bearer/Basic token、密码、SSH 私钥、带 token 的 URL、内部 DNS、Tailnet 域名、设备 IP、真实账号邮箱或可定位部署的看板 ID。
- 示例使用 `<user>`、`<host>`、`<service-domain>`、`<tailnet-ip>`、`<data-root>`、`<token-file>` 等占位符。
- 新服务应通过 `config.age.secrets.<name>.path` 读取运行时机密；不要把机密插入 Nix 表达式或 Nix store。
- 提交前用 `rg` 扫描文档和脚本中的 `token`、`password`、`secret`、`Authorization`、内网地址和账号标识。

## 文档约定

- 文档链路是：根目录 `README.md` → `docs/README.md` → 主题文档或模板。
- 主题文档开头应链接回 `docs/README.md`，结尾提供权威源码和上游参考。
- 长期文档描述原则、来源和验证方法，不保存某次部署的临时状态。需要记录现场证据时，放在变更或发布记录中，并注明日期、目标和命令结果。
- 端口、路径、镜像、包版本和服务名称应尽量从模块引用；文档中的示例必须标明是示例。
- 本地链接使用相对路径；改名或移动文件时同步更新 README、文档索引和相关交叉链接。

## 服务部署边界

- NixOS 目标使用 `nixos-rebuild --flake`；Fedora 等非 NixOS 目标使用 Home Manager。
- 用户级服务的运行状态以 `systemctl --user` 和 `journalctl --user` 为准。
- Tailscale Service 的管理端定义和本地 endpoint 配置是两个边界；文档要分别说明审批、广告和本地转发。
- 服务健康返回只能证明接口可达；需要 provider、对象存储、Trace 或数据写入验证时，必须执行对应的业务检查。

## 推荐验证命令

```bash
git diff --check
just check-fast
just show-systems
just show-homes
```

不要为了通过检查而提交生成文件、解密文件、备份文件或临时日志。
