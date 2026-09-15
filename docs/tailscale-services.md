# Tailscale Services

[返回文档索引](README.md) · [返回项目 README](../README.md)

## 配置链路

Tailscale Service 有两个配置边界：

1. 管理端定义 Service、endpoint 和允许的 host，并完成审批。
2. 本仓库在主机上配置本地转发目标、加载 Serve 配置并广告 Service。

本地源文件是 [`config/tailscale/nuc-services.hujson`](../config/tailscale/nuc-services.hujson)，Home Manager 将它安装到 Tailscale 配置目录。模块在应用前生成 CLI 需要的 raw ServeConfig，并在应用后广告源文件声明的 Service。实际服务名、端口和后端地址以源文件为准。

## Endpoint 语义

源文件中的 endpoint 是 Service 对外监听的端口，例如：

```json
{
  "version": "0.0.1",
  "services": {
    "svc:example": {
      "endpoints": {
        "tcp:443": "tls-terminated-tcp://127.0.0.1:8080"
      }
    }
  }
}
```

- `tls-terminated-tcp://<host>:<port>`：Tailscale 在 Service 入口终止 TLS，再把明文 TCP 转发给后端。适合后端只提供 HTTP 的 Web 服务，客户端使用 `https://<service>.<tailnet-domain>/`。
- `tcp://<host>:<port>`：原始 TCP 转发，适合 S3、OTLP/gRPC 或其他需要保留协议的端口。
- `http://<host>:<port>`：Tailscale 终止 TLS 并把 HTTP 请求**反向代理**到后端，反代时注入 `Tailscale-User-Login`、`Tailscale-User-Name`、`Tailscale-User-Profile-Pic`，并先删除客户端自带的同名头。身份头只对用户设备注入，tagged 对端没有；后端应只监听 loopback，且不要再额外暴露尾部 IP，否则身份头可被伪造。
- `https://` 要求后端本身提供 HTTPS；它不会替代 TLS 终止配置。

如果当前 Tailscale CLI 不能从 versioned config 直接保留 TLS 终止字段，`modules/host-services/tailscale-services.nix` 的 raw 配置转换会为 `tcp://`/`tls-terminated-tcp://` 生成 `TCPForward`（必要时加 `TerminateTLS`），为 `http://`/`https://` 生成 `HTTPS` + `Web.Handlers`。这层兼容逻辑不应手工改写生成文件。

## 管理端首次配置

由 Tailscale 管理员在管理端：

1. 为每个 `svc:<name>` 创建同名 Service。
2. 添加源文件中声明的 endpoint。
3. 将目标主机加入 Service 的 pending host 列表并批准。
4. 确认 tailnet 已启用对应 HTTPS certificates；需要浏览器 HTTPS 时还要确认客户端信任该域名。

主机本地只负责应用和广告配置，不能代替管理端定义或审批。

## 本地应用和验证

```bash
sudo tailscale set --operator=<user>
systemctl --user restart tailscale-services.service
systemctl --user --no-pager status tailscale-services.service
tailscale serve get-config --all
tailscale serve status --json
```

验证时使用已批准 Service 的域名：

```bash
curl -i https://<service>.<tailnet-domain>/
```

Web 服务通常应返回应用响应或应用自己的认证状态；原始协议端口应使用对应客户端检查。Service 配置成功不等于后端应用健康，仍需检查后端 systemd 单元和健康接口。

## 故障排查

| 现象 | 优先检查 |
| --- | --- |
| `tailscale-services.service` 失败 | `journalctl --user -u tailscale-services.service`、Tailscale CLI 版本和源文件格式 |
| 域名无法解析 | 管理端 Service 是否已创建、host 是否已批准、客户端是否在同一 tailnet |
| TLS 成功但应用拒绝请求 | 后端监听地址/端口、Host/Origin 受信配置和应用认证 |
| 经 Service 访问返回 401 | 对端是 tagged 设备、走了 Funnel，或 endpoint target 不是 `http://`；确认 HTTP 反代生效且客户端是用户设备 |
| Web 页面能开但 Settings 不可用 | 应用自己的 loopback/远程设置策略；查看对应主题文档的 tunnel 或受信域名配置 |
| raw TCP 可连但数据失败 | 确认 endpoint 没有误用 TLS 终止，检查后端协议和端口 |

## 权限边界

不要把 Garage 管理 API、RPC、OpenObserve 内部管理端口、Collector 调试端口或其他控制面加入普通客户端使用的 Service。新增 endpoint 前先确认认证、访问范围和回滚方式。

`svc:deepseek-harness` 使用 `http://` 反代，应用身份取自 Tailscale 身份头。必须在管理端用 grants/ACL 把该 Service 限制到指定用户或设备；否则同 tailnet 的任意用户设备都会被应用视为已认证。Funnel 不注入身份头，不能替代 grants。

## 参考资料

- [Tailscale Services](https://tailscale.com/docs/features/tailscale-services)
- [Services configuration file](https://tailscale.com/docs/reference/tailscale-services-configuration-file)
- [tailscale serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve)
