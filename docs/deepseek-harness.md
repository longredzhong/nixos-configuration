# DeepSeek Harness

[返回文档索引](README.md) · [返回项目 README](../README.md)

## 作用范围

`modules/host-services/deepseek-harness.nix` 在 standalone Home Manager 目标上创建用户级 `deepseek-harness.service`。服务从 npm 安装固定版本的 `@deepseek-ai/dsh`，运行时和 Harness 数据分别保存在用户目录；实际版本、端口和路径以 Nix 模块为准。

## 访问

服务端只监听 loopback，由受控的 Tailscale Service 以 **HTTP 反向代理**方式接入（`http://127.0.0.1:<dsh-port>` target）：

```text
浏览器 ──HTTPS──> svc:<service-name> ──HTTP──> 127.0.0.1:<dsh-port>
```

Tailscale 反代时注入 `Tailscale-User-Login` / `Tailscale-User-Name` 身份头，并先删除客户端自带的同名头；tagged 对端不会收到身份头。部署模块对固定的 connection bundle 应用版本敏感的运行时补丁：只在回环连接且没有 `Tailscale-Funnel-Request` 时接受该身份头。因此浏览器直接使用不带 token 的 HTTPS 域名：

```text
https://<service-domain>/
```

认证与授权边界：

- 应用身份来自 Tailscale 用户身份，授权范围完全由 tailnet 策略决定。必须在管理端用 grants/ACL 把 `svc:<service-name>`（`tcp:443`）限制到指定用户或设备，否则同 tailnet 的任意用户设备都会被应用视为已认证。
- 不使用 Funnel；Funnel 流量没有身份头，补丁也会拒绝 `Tailscale-Funnel-Request`。
- 服务单元不再保留额外的 TCP 转发器或尾部 IP 监听，避免绕过身份注入直连回环后端。

### 回退：启动 token

DSH 每个进程仍生成一次性 launch token 并打印到标准输出。模块把服务 stdout/stderr 追加到 `${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness/web.log`（`0600`），因此 token 不再进入 journald。仅在身份头不可用的场景（SSH 隧道直连 loopback、tagged 设备等）使用；不要把结果写入文档或提交记录：

```bash
ssh <ssh-target> \
  'sed -n "s#^dsh web: ##p" \
     "${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness/web.log" \
   | tail -n 1' \
  | sed -E 's#http://127\.0\.0\.1:[0-9]+#https://<service-domain>#'
```

首次打开 token URL 或直接打开已注入身份头的域名后，浏览器会得到签名 cookie，随后页面跳转到不带 token 的根路径。connection 补丁把 `cookieMaxAgeDays` 固定为 365 天，且 cookie 跨 DSH 重启有效；删除 `client-connection/browser-session` 凭据记录并重启可全局撤销。

## Settings 和 Provider

当前 DSH 上游客户端默认只允许 loopback 页面使用持久化 Settings。部署模块对固定的 Settings bundle 应用版本敏感的运行时补丁，仅对模块中声明的受信任 Service hostname 启用 Host settings mirror；补丁匹配失败会让服务启动失败，避免升级后静默失去 Settings。

因此应通过 HTTPS Service 域名打开 **Settings → Models**。回环直连没有身份头，`location.hostname` 也不会匹配模块声明的受信任 Service hostname，因此不会启用 Host settings mirror；如果补丁因上游 bundle 变化而停止服务，先使用 loopback SSH 隧道完成配置，再更新补丁：

```bash
# 终端一：保持隧道运行
ssh -N -L <local-port>:127.0.0.1:<dsh-port> <ssh-target>

# 终端二：从 web.log 取当前进程的 token URL，把 loopback authority 换成
# http://127.0.0.1:<local-port> 后打开（没有身份头时的回退路径）
```

API key 通过 Settings 页面写入运行时凭据文件。不要在 Shell 历史、Nix 表达式、日志或文档中保存 key。

## OpenCode Go 会话标识

`web` profile 会加载仓库中的
`@longred/deepseek-harness-opencode-session` 自定义插件。它监听 DSH 的
`llm/stream` 扩展点，只对 provider 为 `opencode-go` 或 `opencode-go-live-*` 的请求建立异步会话作用域，
并把当前 Harness `sessionId` 作为 `x-opencode-session` 发给 OpenCode Go。
不同 Harness 会话会得到不同的 header；没有 `sessionId` 时不会生成或复用固定值。

该插件解决 OpenCode Go 在 Chat Completions 路径要求会话 header、而当前 pi-ai
provider 没有把 DSH 会话 ID映射到该 provider 专用 header 的兼容问题。背景和
上游讨论见 [DeepSeek Harness discussion #6467](https://github.com/deepseek-ai/deepseek-harness/discussions/6467)。
插件只在消费模型流的异步作用域内包装 Node fetch，其他 provider 请求不添加该 header。

## OpenCode Go 动态模型目录

同一个 OpenCode Go 套餐同时提供 Chat Completions、Responses 和 Anthropic
Messages 三种协议。OpenCode 官方文档说明模型列表会随服务端变化，并提供完整的
模型接口；仅读取 `/zen/go/v1/models` 只能得到模型 ID，不能得到每个模型应使用的
协议。插件使用公开的
[`pi.dev/api/models/providers/opencode-go`](https://pi.dev/api/models/providers/opencode-go)
目录获取模型 ID、协议、endpoint、上下文长度、输入模态和兼容参数。

DSH `0.1.6-alpha.1` 的 Settings provider route 在 route 层保存 `api` 和
`baseURL`，所以插件把目录按协议写入三个受管理的 route：

| Provider route | 协议 | Base URL |
| --- | --- | --- |
| `opencode-go-live-chat` | `openai-completions` | `https://opencode.ai/zen/go/v1` |
| `opencode-go-live-responses` | `openai-responses` | `https://opencode.ai/zen/go/v1` |
| `opencode-go-live-messages` | `anthropic-messages` | `https://opencode.ai/zen/go` |

插件在服务启动约 5 秒后同步一次，此后每 4 小时刷新；刷新失败时保留上一次成功的
动态目录，静态的 `opencode-go` route 继续作为回退。动态 route 使用
`OPENCODE_GO_API_KEY` 凭据引用，目录请求不携带或保存 API key。上述三个 route
由插件管理，不要在 Settings 中为它们手工保存自定义配置；原有 `opencode-go`
route 保留用于兼容已有会话和默认模型。

更新后的模型会出现在 **Settings → Models**。选择模型时使用相应的
`opencode-go-live-*` route，模型会通过插件的同一套 `x-opencode-session` header
修复发送请求。模型协议和 OpenCode Go 的 endpoint 约束以
[OpenCode Go provider 文档](https://dev.opencode.ai/docs/go/)
以及 [DSH live discovery discussion #5681](https://github.com/deepseek-ai/deepseek-harness/discussions/5681)
为依据。

## 部署和验证

```bash
just check-fast
just hm-dry-run '<user>@<host>'
just hm-switch '<user>@<host>'
```

在目标主机上：

```bash
systemctl --user is-active deepseek-harness
systemctl --user --no-pager status deepseek-harness
# 服务 stdout/stderr 写入手册指定的 0600 文件，不在 journald
tail -n 100 "${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness/web.log"
# loopback 直连没有身份头，预期 401
curl --fail-with-body -i http://127.0.0.1:<dsh-port>/
```

在 tailnet 用户设备上验证 Service 反代与身份注入：

```bash
# 预期 200：请求经 Tailscale HTTP 反代携带身份头
curl -i https://<service-domain>/
```

浏览器验证应直接打开不带 token 的 HTTPS 域名，并检查 Models 页面、`settings/describe` 和 provider directory 请求。tagged 设备或被 tailnet 策略拒绝的设备预期返回 `401`。

## 状态和回滚

- npm runtime：模块定义的用户运行时目录。
- 服务日志：`%L/deepseek-harness/web.log`（`0600`），不写入 journald。
- Harness 数据：模块定义的 `DSH_HOME` 目录；其中包括会话、Settings 和 credentials。
- 升级：只修改模块中的 `dshVersion`，先 dry-run，再观察安装日志和页面。
- 回滚：恢复旧版本并重新执行 Home Manager；不要删除保存会话和 credentials 的数据目录。

## 参考资料

- [DeepSeek Harness 仓库](https://github.com/deepseek-ai/deepseek-harness)
- [Quickstart](https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart)
- [Web server reference](https://deepseek-harness.github.io/deepseek-harness/en/reference/subsystems/web-server)
- [远程 Settings 限制](https://github.com/deepseek-ai/deepseek-harness/discussions/5829)
- [OpenCode Go session header discussion](https://github.com/deepseek-ai/deepseek-harness/discussions/6467)
