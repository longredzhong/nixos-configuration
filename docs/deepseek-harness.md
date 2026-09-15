# DeepSeek Harness 部署与使用

NUC 上的 `deepseek-harness.service` 以 Home Manager 用户级 systemd 服务运行 DeepSeek Harness Web UI。当前固定 npm 版本为 `@deepseek-ai/dsh@0.1.5-rc.2`，Node.js 使用 Nixpkgs 22；首次启动时把运行时安装到用户目录，之后由 systemd 持续管理。

## 访问方式

服务实际监听 NUC 的 Tailscale 地址 `100.100.10.1:3080`，只对 Tailscale 网络开放。当前 DSH Web Server 配置只接受 `127.0.0.1` 或 `0.0.0.0`，因此 `deepseek-harness.service` 让 DSH 绑定 loopback，再由同一服务中的 TCP 转发器绑定精确的 Tailscale 地址。这样不会把 DSH 直接暴露到所有网卡。

在已加入同一 Tailscale 网络的设备上打开：

```bash
https://deepseek-harness.tail388af.ts.net/
```

上游 DSH 版本默认把 Settings/Models 的浏览器持久化限制为 loopback 页面。
本模块在 NUC 的运行时安装阶段对固定的 `@deepseek-ai/dsh-client-ui-settings`
bundle 应用一个版本敏感的补丁：只要服务端已经通过 `--trusted-host`
声明了 Tailscale Service 域名，已通过 DSH token 认证的 HTTPS 浏览器会话也能
使用 Host settings mirror。补丁匹配失败会让服务启动失败，避免升级后静默回到
`settings are unavailable in this browser`。该设置把完整的 Harness settings
和 credentials 管理面暴露给拥有 Tailscale Service 访问权及 DSH token 的用户；
不要把同一服务暴露给不受信任的网络。[上游限制与配置讨论](https://github.com/deepseek-ai/deepseek-harness/discussions/5829)

Harness 启动时会在日志中打印带一次性认证 token 的本地 URL。把它的
`127.0.0.1:3080` 替换为 Service 域名，协议改为 `https`，然后在浏览器打开：

```bash
ssh nuc 'journalctl --user -u deepseek-harness -n 100 -o cat \
  | sed -n "s/^dsh web: //p" | tail -n 1' \
  | sed -e 's#http://127.0.0.1:3080#https://deepseek-harness.tail388af.ts.net#' \
        -e 's#http://127.0.0.1#https://deepseek-harness.tail388af.ts.net#'
```

在浏览器打开上一个命令输出的 URL；首次访问会建立认证 cookie，随后页面会跳转到 `/`。裸访问根路径没有认证 cookie 时返回 401 是预期行为。
如果浏览器无法访问 Tailscale Service，可改用 SSH 隧道：`ssh -N -L 3086:100.100.10.1:3080 nuc`，再把启动 URL 中的 `127.0.0.1:3080` 替换成 `127.0.0.1:3086`。

需要配置 Provider 或 DeepSeek API key 时，推荐使用 loopback 隧道：

```bash
# 终端一：保持隧道运行
ssh -N -L 3086:100.100.10.1:3080 nuc

# 终端二：取得可用于 Settings/Models 的 URL
ssh nuc 'journalctl --user -u deepseek-harness -n 100 -o cat \
  | sed -n "s/^dsh web: //p" | tail -n 1' \
  | sed 's#127.0.0.1:3080#127.0.0.1:3086#'
```

打开第二个命令输出的 URL 后，Settings → Models 会正常加载并保存配置。

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
curl -i https://deepseek-harness.tail388af.ts.net/
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
