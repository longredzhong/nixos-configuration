# DeepSeek Harness

[返回文档索引](README.md) · [返回项目 README](../README.md)

## 作用范围

`modules/host-services/deepseek-harness.nix` 在 standalone Home Manager 目标上创建用户级 `deepseek-harness.service`。服务从 npm 安装固定版本的 `@deepseek-ai/dsh`，运行时和 Harness 数据分别保存在用户目录；实际版本、端口和路径以 Nix 模块为准。

## 访问

服务端使用 loopback 启动 DSH，再由本地 TCP 转发器接入受控的 Tailscale Service。浏览器应使用已批准的 HTTPS Service 域名：

```text
https://<service-domain>/
```

启动日志会打印带一次性 token 的 URL。安全地取得并转换 URL 时，不要把 token 写入文档或提交记录：

```bash
ssh <ssh-target> \
  'journalctl --user -u deepseek-harness -n 100 -o cat --no-pager \
   | sed -n "s#^dsh web: ##p" | tail -n 1' \
  | sed -E 's#http://127\.0\.0\.1:[0-9]+#https://<service-domain>#'
```

首次打开 token URL 后会建立认证 cookie，随后页面会跳转到不带 token 的根路径。没有认证 cookie 时根路径返回 `401` 是预期行为。

## Settings 和 Provider

当前 DSH 上游客户端默认只允许 loopback 页面使用持久化 Settings。部署模块对固定的 Settings bundle 应用版本敏感的运行时补丁，仅对模块中声明的受信任 Service hostname 启用 Host settings mirror；补丁匹配失败会让服务启动失败，避免升级后静默失去 Settings。

因此应通过 HTTPS Service 域名打开 **Settings → Models**。直接访问后端 IP 不会获得这条远程 Settings 放行；如果补丁因上游 bundle 变化而停止服务，先使用 loopback SSH 隧道完成配置，再更新补丁：

```bash
# 终端一：保持隧道运行
ssh -N -L <local-port>:127.0.0.1:<dsh-port> <ssh-target>

# 终端二：把启动 URL 中的 loopback authority 改成
# http://127.0.0.1:<local-port>
```

API key 通过 Settings 页面写入运行时凭据文件。不要在 Shell 历史、Nix 表达式、日志或文档中保存 key。

## OpenCode Go 会话标识

`web` profile 会加载仓库中的
`@longred/deepseek-harness-opencode-session` 自定义插件。它监听 DSH 的
`llm/stream` 扩展点，只对 provider 为 `opencode-go` 的请求建立异步会话作用域，
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
journalctl --user -u deepseek-harness -n 100 --no-pager
curl --fail-with-body -i https://<service-domain>/
```

无认证的 `curl` 预期返回 `401`。浏览器验证必须继续使用 token URL，并检查 Models 页面、`settings/describe` 和 provider directory 请求。

## 状态和回滚

- npm runtime：模块定义的用户运行时目录。
- Harness 数据：模块定义的 `DSH_HOME` 目录；其中包括会话、Settings 和 credentials。
- 升级：只修改模块中的 `dshVersion`，先 dry-run，再观察安装日志和页面。
- 回滚：恢复旧版本并重新执行 Home Manager；不要删除保存会话和 credentials 的数据目录。

## 参考资料

- [DeepSeek Harness 仓库](https://github.com/deepseek-ai/deepseek-harness)
- [Quickstart](https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart)
- [Web server reference](https://deepseek-harness.github.io/deepseek-harness/en/reference/subsystems/web-server)
- [远程 Settings 限制](https://github.com/deepseek-ai/deepseek-harness/discussions/5829)
- [OpenCode Go session header discussion](https://github.com/deepseek-ai/deepseek-harness/discussions/6467)
