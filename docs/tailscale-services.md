# Tailscale Services

[返回文档索引](README.md) · [返回项目 README](../README.md)

## 配置链路

Tailscale Service 有两个配置边界：

1. 管理端定义 Service、endpoint 和允许的 host，并完成审批。
2. 本仓库在主机上配置本地转发目标、加载 Serve 配置并广告 Service。

每个主机有自己的本地源文件，模块用 `hostServices.tailscaleServices.serviceConfigFile` 指向它：NUC 是 [`config/tailscale/nuc-services.hujson`](../config/tailscale/nuc-services.hujson)，ThinkBook 是 [`config/tailscale/thinkbook-services.hujson`](../config/tailscale/thinkbook-services.hujson)。`hostServices.tailscaleServices.enable` 打开该主机的应用单元，源文件按原文件名安装到 Tailscale 配置目录。模块在应用前生成 CLI 需要的 raw ServeConfig，并在应用后广告源文件声明的 Service。`tailscale serve set-config --all` 替换本机整份 Serve 配置，所以一个主机的源文件必须完整列出该主机要暴露的全部 Service。实际服务名、端口和后端地址以源文件为准。

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

Service 定义可以额外声明 `appCaps`，把指定 capability 通过 `Tailscale-App-Capabilities` 转发给后端：

```json
{
  "version": "0.0.1",
  "services": {
    "svc:example": {
      "endpoints": {
        "tcp:443": "http://127.0.0.1:8080"
      },
      "appCaps": ["example.com/cap/example"]
    }
  }
}
```

与身份头不同，app capability **对 tagged 对端也会转发**，因此 tagged 设备可以用被授予的 capability 代替用户登录身份。`appCaps` 只能加在 `http://`/`https://` endpoint 上；后端需要显式读取该头，且管理端必须同时存在授予该 capability 的 grant，否则后端的 tagged 请求仍然未认证。注意 Tailscale 当前用服务宿主机自身的地址匹配 capability，所以 grant 的 `dst` 里除 `svc:<name>` 外还要带上服务宿主机的 tag 或 IP。

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

第一行的 `--operator` 是**一次性前置条件**，不做的话该单元必然失败：tailscaled 只允许 root 或
operator 写 serve 配置，而单元跑在用户级。症状是日志里出现

```text
Access denied: prefs write access denied
To not require root, use 'sudo tailscale set --operator=$USER' once.
```

设过 operator 的主机（例如 NUC）不会有这个报错，所以同一份配置在一台机器上 `active`、在另一台上
`failed`——先查这一条，再查管理端审批。

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
| 经 Service 访问返回 401 | 对端是 tagged 设备、走了 Funnel，或 endpoint target 不是 `http://`；确认 HTTP 反代生效；tagged 设备还需确认 Service 声明了 `appCaps` 且管理端 grant 的 `dst` 含服务宿主机 tag/IP |
| Web 页面能开但 Settings 不可用 | 应用自己的 loopback/远程设置策略；查看对应主题文档的 tunnel 或受信域名配置 |
| raw TCP 可连但数据失败 | 确认 endpoint 没有误用 TLS 终止，检查后端协议和端口 |

## 权限边界

不要把 Garage 管理 API、RPC、OpenObserve 内部管理端口、Collector 调试端口或其他控制面加入普通客户端使用的 Service。新增 endpoint 前先确认认证、访问范围和回滚方式。

`svc:deepseek-harness` 使用 `http://` 反代，应用身份只来自 Tailscale 身份头或 app capability。必须在管理端用 grants 把该 Service 限制到指定用户或设备；否则同 tailnet 的任意用户设备都会被应用视为已认证。用户设备用身份头认证，tagged 设备用 capability 认证。Funnel 不注入这两类头，不能替代 grants。

暴露 DeepSeek Harness 的每个主机用独立的 Service 名和 capability 名：NUC 是 `svc:deepseek-harness` + `example.com/cap/deepseek-harness`，ThinkBook 是 `svc:deepseek-harness-thinkbook` + `example.com/cap/deepseek-harness-thinkbook`。capability 名在源文件的 `appCaps`、管理端的 grant 和应用的 `hostServices.deepseekHarness.appCapability` 三处必须一致；不要在多台主机间复用同一个 capability，否则一份授权会让另一台主机的 Service 也被应用认作已认证。

用户设备只需网络访问：

```jsonc
{
  "src": ["<user>@<idp-domain>"],
  "dst": ["svc:deepseek-harness"],
  "ip": ["443"]
}
```

tagged 设备除网络访问外还要授予 capability，且 `dst` 要带上服务宿主机的 tag（见上文 capability 匹配说明）：

```jsonc
{
  "src": ["tag:<client-tag>"],
  "dst": ["svc:deepseek-harness", "tag:<service-host-tag>"],
  "ip": ["443"],
  "app": { "example.com/cap/deepseek-harness": [{}] }
}
```

追加主机时再写一组同样的 grant，把 `dst` 换成 `svc:deepseek-harness-thinkbook` 和该主机的 tag/IP，`app` 换成 `example.com/cap/deepseek-harness-thinkbook`。

## 参考资料

- [Tailscale Services](https://tailscale.com/docs/features/tailscale-services)
- [Services configuration file](https://tailscale.com/docs/reference/tailscale-services-configuration-file)
- [tailscale serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve)
