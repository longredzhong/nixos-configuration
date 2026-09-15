# DeepSeek Harness 部署与使用

NUC 上的 `deepseek-harness.service` 以 Home Manager 用户级 systemd 服务运行 DeepSeek Harness Web UI。当前固定 npm 版本为 `@deepseek-ai/dsh@0.1.5-rc.2`，Node.js 使用 Nixpkgs 22；首次启动时把运行时安装到用户目录，之后由 systemd 持续管理。

## 访问方式

服务监听 NUC 的 Tailscale 地址 `100.100.10.1:3080`，只对 Tailscale 网络开放。DeepSeek Harness 官方 CLI 目前拒绝直接监听 `0.0.0.0`，因为 Web UI 包含本地文件和命令执行能力；这里使用 NUC 的 Tailscale 地址来保留网络边界。

在已加入同一 Tailscale 网络的设备上打开：

```bash
http://100.100.10.1:3080
```

Harness 启动时会在日志中打印带一次性认证 token 的 URL。可以直接取出启动 URL：

```bash
ssh nuc 'journalctl --user -u deepseek-harness -n 100 -o cat \
  | sed -n "s/^dsh web: //p" | tail -n 1'
```

在浏览器打开上一个命令输出的 URL；首次访问会建立认证 cookie，随后页面会跳转到 `/`。如果浏览器无法访问 Tailscale 地址，可改用 SSH 隧道：`ssh -N -L 3086:100.100.10.1:3080 nuc`，再把启动 URL 中的 `100.100.10.1:3080` 替换成 `127.0.0.1:3086`。

## 应用配置

首次打开页面后进入 **Settings → Models**，保存 DeepSeek API key。Harness 将凭据写到：

```text
~/.local/share/deepseek-harness/home/.credentials.yaml
```

会话、设置和 profile 也都在这个 `DSH_HOME` 下保存。不要把该目录复制到公开位置；服务单元使用 `UMask=0077`。

## 应用与验证

在仓库目录执行：

```bash
just hm-dry-run 'longred@nuc'
just hm-switch 'longred@nuc'
```

在 NUC 上确认：

```bash
systemctl --user is-active deepseek-harness
systemctl --user status deepseek-harness --no-pager
journalctl --user -u deepseek-harness -n 100 --no-pager
# 裸访问没有认证 cookie，返回 401 是预期行为；浏览器应使用日志中的 token URL。
curl -i http://100.100.10.1:3080/
```

首次启动需要从 npm 下载约 200 个运行时依赖，安装完成后服务会自动继续启动。升级时只修改模块中的 `dshVersion`，先运行 Home Manager dry-run，再观察安装日志和页面可用性。

## 边界与回滚

这个版本仍处于 DeepSeek Harness developer preview，运行时和配置接口可能发生不兼容变化。服务自身的 npm runtime 位于：

```text
~/.local/share/deepseek-harness/runtime
```

如果升级后需要回滚，恢复旧的 `dshVersion` 并重新执行 Home Manager；会话数据在单独的 `home` 目录中，不随 runtime 替换。

官方文档：

- <https://github.com/deepseek-ai/deepseek-harness>
- <https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart>
- <https://deepseek-harness.github.io/deepseek-harness/en/reference/subsystems/web-server>
