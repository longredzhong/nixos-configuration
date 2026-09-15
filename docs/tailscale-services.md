# Tailscale Services 家庭实验室配置

本仓库把 NUC 上的 Tailscale Services endpoint 集中放在
[`config/tailscale/nuc-services.hujson`](../config/tailscale/nuc-services.hujson)。
Home Manager 将它安装到 `~/.config/tailscale/nuc-services.hujson`，然后由
`tailscale-services.service` 执行 `tailscale serve set-config --all` 并重新广告
文件中列出的 Service。

## 当前服务

当前 NUC 上已经运行并验证过监听端口的家庭实验室服务如下。每个 Service 都
使用自己的 TailVIP，因此多个 Service 可以同时使用 `tcp:80`；客户端通过
Service 的 MagicDNS 名称区分它们。

| Service | Service endpoint | NUC 本地目标 | 访问示例 |
| --- | --- | --- | --- |
| `svc:opencode` | `tcp:80` | `127.0.0.1:4096` | `http://opencode.tail388af.ts.net/` |
| `svc:deepseek-harness` | `tcp:80` | `127.0.0.1:3080` | `http://deepseek-harness.tail388af.ts.net/` |
| `svc:openobserve` | `tcp:80`, `tcp:5081` | `100.100.10.1:5080`, `100.100.10.1:5081` | `http://openobserve.tail388af.ts.net/` |
| `svc:garage` | `tcp:80`, `tcp:3902` | `127.0.0.1:3900`, `127.0.0.1:3902` | `http://garage.tail388af.ts.net/` |
| `svc:garage-ui` | `tcp:80` | `100.100.10.1:8080` | `http://garage-ui.tail388af.ts.net/` |
| `svc:dufs` | `tcp:80` | `127.0.0.1:5000` | `http://dufs.tail388af.ts.net/` |
| `svc:affine` | `tcp:80` | `100.100.10.1:3010` | `http://affine.tail388af.ts.net/` |

这里使用 raw TCP 转发，保留 Web、S3 和 OTLP 的原始协议。Tailnet 内的链路仍
由 Tailscale 加密，访问控制由 tailnet policy 和 Service 的访问规则负责。
需要由 Tailscale 终止 HTTPS 时，应使用 `tailscale serve --service=... --https=443`
单独配置对应 Service；不要把当前 huJSON 文件误当成 HTTPS 配置。

Garage 的 RPC、admin API 和 OpenObserve 的本地管理端口没有加入 Service，避免
把内部控制面提供给普通客户端。Anytype 也暂不加入：当前服务没有确认一个可用
的对外 TCP listener。

## 首次在 Tailscale 管理端创建 Service

Tailscale Services 的 Service 定义不属于本地 `tailscale serve` 配置文件，必须
由 Owner、Admin 或 Network admin 在管理端建立。对每一行 Service 至少创建同名
资源，并加入表中的 endpoint；创建后在该 Service 的 pending host 列表中批准
NUC。NUC 当前使用 `tag:longred-server` 等 tag 身份，满足 Service host 的要求。

管理端完成定义和审批后，在 NUC 上运行：

```bash
systemctl --user restart tailscale-services.service
systemctl --user status tailscale-services.service
tailscale serve status --json
```

如果 unit 先于管理端定义启动，它会失败并每五分钟重试；这不会停止现有的
OpenCode、DeepSeek Harness、OpenObserve、Garage、DUFS 或 AFFiNE 服务。

验证 Service 已批准后，从同一 tailnet 的客户端测试：

```bash
curl -i http://opencode.tail388af.ts.net/
curl -i http://deepseek-harness.tail388af.ts.net/
curl -i http://openobserve.tail388af.ts.net/
```

DeepSeek Harness 的 Provider/Models 设置仍建议使用现有的 loopback SSH tunnel，
因为 Harness 的浏览器设置 API 会限制非 loopback authority。详见
[`docs/deepseek-harness.md`](deepseek-harness.md)。

## 配置来源

- [Tailscale Services](https://tailscale.com/docs/features/tailscale-services)：Service 定义、tag-based host、广告和审批流程。
- [Tailscale Services configuration file](https://tailscale.com/docs/reference/tailscale-services-configuration-file)：`version`、`services`、`endpoints` 和 `tcp://` target 格式。
- [tailscale serve](https://tailscale.com/docs/reference/tailscale-cli/serve)：`set-config`、`advertise`、`status` 和 HTTPS/TCP 转发命令。
