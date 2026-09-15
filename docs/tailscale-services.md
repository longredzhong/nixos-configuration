# Tailscale Services 家庭实验室配置

本仓库把 NUC 上的 Tailscale Services endpoint 集中放在
[`config/tailscale/nuc-services.hujson`](../config/tailscale/nuc-services.hujson)。
Home Manager 将它安装到 `~/.config/tailscale/nuc-services.hujson`。由于当前
NUC 使用的 Tailscale 1.102.x 在 versioned `set-config` 中不能直接应用
`tls-terminated-tcp` target，Home Manager 会从这个源文件生成 raw ServeConfig，
由 `tailscale-services.service` 清理同名旧 endpoint、执行
`tailscale serve set-config --all`，然后重新广告文件中列出的 Service。生成的 raw 配置保留
`TerminateTLS` 和 `TCPForward` 两个字段。

## 当前服务

当前 NUC 上已经运行并验证过监听端口的家庭实验室服务如下。每个 Service 都
使用自己的 TailVIP，因此多个 Service 可以同时使用 `tcp:443`；客户端通过
Service 的 MagicDNS 名称区分它们。

| Service | Service endpoint | NUC 本地目标 | 访问示例 |
| --- | --- | --- | --- |
| `svc:opencode` | `tcp:443` | `tls-terminated-tcp://127.0.0.1:4096` | `https://opencode.tail388af.ts.net/` |
| `svc:deepseek-harness` | `tcp:443` | `tls-terminated-tcp://127.0.0.1:3080` | `https://deepseek-harness.tail388af.ts.net/` |
| `svc:openobserve` | `tcp:443`, `tcp:5081` | `tls-terminated-tcp://100.100.10.1:5080`, `tcp://100.100.10.1:5081` | `https://openobserve.tail388af.ts.net/` |
| `svc:garage` | `tcp:443`, `tcp:3902` | `tls-terminated-tcp://127.0.0.1:3900`, `tls-terminated-tcp://127.0.0.1:3902` | `https://garage.tail388af.ts.net/` |
| `svc:garage-ui` | `tcp:443` | `tls-terminated-tcp://100.100.10.1:8080` | `https://garage-ui.tail388af.ts.net/` |
| `svc:dufs` | `tcp:443` | `tls-terminated-tcp://127.0.0.1:5000` | `https://dufs.tail388af.ts.net/` |
| `svc:affine` | `tcp:443` | `tls-terminated-tcp://100.100.10.1:3010` | `https://affine.tail388af.ts.net/` |

Web、S3 和 Garage Web 端点使用 `tls-terminated-tcp://`：Tailscale 在 Service
入口终止 TLS，再把解密后的 TCP 流转发到 NUC 上的明文服务。浏览器和 HTTP
客户端使用 `https://<service>.tail388af.ts.net/`；后端服务无需自行配置证书。
OpenObserve 的 `5081` 保留 raw TCP，因为它是 OTLP/gRPC 端口，不是浏览器 Web
入口。需要原始协议透传的端口继续使用 `tcp://`。

这里不能把 target 改成 `http://` 来表达“入口 HTTPS、后端 HTTP”：在
`tailscale serve set-config` 的 versioned 服务配置中，target 的协议同时决定
Serve 模式，`http://` 会生成 HTTP 入口。源文件使用
`tls-terminated-tcp://` 明确表示 TLS 终止后继续转发原始明文流；Home Manager
负责把它转换成当前客户端能应用的 `TerminateTLS`/`TCPForward` 结构。
Tailscale 客户端必须启用 tailnet 的 HTTPS certificates，才能为 Service
MagicDNS 名称提供证书。

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
# 只需首次执行一次；用户级 systemd unit 需要通过本机 Tailscale CLI 写配置
sudo tailscale set --operator=longred

systemctl --user restart tailscale-services.service
systemctl --user status tailscale-services.service
tailscale serve status --json
```

如果 unit 先于管理端定义启动，它会失败并每五分钟重试；这不会停止现有的
OpenCode、DeepSeek Harness、OpenObserve、Garage、DUFS 或 AFFiNE 服务。

验证 Service 已批准后，从同一 tailnet 的客户端测试：

```bash
curl -i https://opencode.tail388af.ts.net/
curl -i https://deepseek-harness.tail388af.ts.net/
curl -i https://openobserve.tail388af.ts.net/
```

在 NUC 上确认入口已经是 TLS-terminated TCP：

```bash
tailscale serve get-config --all
tailscale serve status --json
```

DeepSeek Harness 当前通过 `deepseek-harness.nix` 的版本敏感运行时补丁允许已
声明 trusted host 且已通过 DSH token 认证的 HTTPS 浏览器会话加载并保存
Provider/Models 设置。若 Harness 升级后补丁匹配失败，服务会拒绝启动；此时可
先使用现有的 loopback SSH tunnel 访问设置，详见
[`docs/deepseek-harness.md`](deepseek-harness.md)。

## 配置来源

- [Tailscale Services](https://tailscale.com/docs/features/tailscale-services)：Service 定义、tag-based host、广告和审批流程。
- [Tailscale Services configuration file](https://tailscale.com/docs/reference/tailscale-services-configuration-file)：`version`、`services`、`endpoints` 和 target 格式。
- [tailscale serve](https://tailscale.com/docs/reference/tailscale-cli/serve)：HTTPS、raw TCP 和 `tls-terminated-tcp` 转发命令。
