# DeepSeek Harness

[返回文档索引](README.md) · [返回项目 README](../README.md) · 开发机上的 ACP 接入见 [DeepSeek Harness ACP（Zed）](deepseek-harness-acp.md)

## 作用范围

`modules/host-services/deepseek-harness.nix` 在 standalone Home Manager 目标上创建用户级 `deepseek-harness.service`，由 `hostServices.deepseekHarness.enable` 按主机打开。服务从 npm 安装固定版本的 `@deepseek-ai/dsh`，运行时和 Harness 数据分别保存在用户目录；实际版本、端口和路径以 Nix 模块为准。

所有与部署绑定的名字都是 `hostServices.deepseekHarness` 的选项，默认值描述参考部署（NUC），主机配置只覆盖差异：

| 主机 | `serviceHost` / `appCapability` | web `runtimeDir` / `dshHome` |
| --- | --- | --- |
| NUC（`users/longred/nuc.nix`） | `deepseek-harness.<tailnet-domain>` / `example.com/cap/deepseek-harness`（模块默认值） | `~/.local/share/deepseek-harness/web-runtime` / `~/.local/share/deepseek-harness/home` |
| ThinkBook（`users/longred/fedora-thinkbook.nix`） | `deepseek-harness-thinkbook.<tailnet-domain>` / `example.com/cap/deepseek-harness-thinkbook` | `~/.local/share/deepseek-harness/web-runtime` / `~/.local/share/deepseek-harness/home` |

两台主机同时运行 ACP profile（`hostServices.deepseekHarnessAcp`），web 与 ACP 各自使用独立的运行时目录和 `$DSH_HOME`：两个模块安装并补丁同一批 bundle 文件，且 `storages/` 没有跨进程写锁。ACP 占用模块默认的 `~/.local/share/deepseek-harness/runtime`，其 `$DSH_HOME` 是 NUC 的 `.../acp-home` 和 ThinkBook 的 `~/.dsh`。遥测 stream 默认按主机名生成（`<hostname>_dsh_ledger`、`<hostname>_dsh_ops`、`<hostname>_dsh_llm`），OTEL 的 `host.name` 也取主机名。

## 访问

服务端只监听 loopback，由受控的 Tailscale Service 以 **HTTP 反向代理**方式接入（`http://127.0.0.1:<dsh-port>` target）。每个主机用自己源文件里的 Service：

```text
浏览器 ──HTTPS──> svc:<service-name> ──HTTP──> 127.0.0.1:<dsh-port>
```

Tailscale 反代时注入 `Tailscale-User-Login` / `Tailscale-User-Name` 身份头，并先删除客户端自带的同名头；tagged 对端不会收到身份头，但会在管理端授予 capability 后收到 `Tailscale-App-Capabilities`。部署模块对固定的 connection bundle 应用版本敏感的运行时补丁：只在回环连接且没有 `Tailscale-Funnel-Request` 时接受登录身份头，或接受携带本主机 capability（模块选项 `appCapability`）的 capability 头。因此浏览器直接使用不带 token 的 HTTPS 域名：

```text
https://<service-domain>/
```

认证与授权边界：

- 应用身份来自 Tailscale 用户身份，或用户设备之外的 tagged 设备被授予的 app capability。授权范围完全由 tailnet 策略决定。必须在管理端用 grants 把 `svc:<service-name>`（`tcp:443`）限制到指定用户或设备，否则同 tailnet 的任意用户设备都会被应用视为已认证。每台主机用自己的 `svc:` 名和 capability（NUC：`svc:deepseek-harness`；ThinkBook：`svc:deepseek-harness-thinkbook`，capability 同名加 `-thinkbook` 后缀）。
- tagged 设备需要在管理端 grant 中授予该主机的 capability（NUC：`example.com/cap/deepseek-harness`；ThinkBook：`example.com/cap/deepseek-harness-thinkbook`）；对应源文件的 `appCaps` 让 Serve 转发该 capability。grant 的 `dst` 必须同时包含服务宿主机的 tag/IP，因为 Tailscale 用宿主机自身地址匹配 capability。
- 不使用 Funnel；Funnel 流量没有身份头，补丁也会拒绝 `Tailscale-Funnel-Request`。
- 服务单元不再保留额外的 TCP 转发器或尾部 IP 监听，避免绕过身份注入直连回环后端。

### 回退：启动 token

DSH 每个进程仍生成一次性 launch token 并打印到标准输出。模块把服务 stdout/stderr 追加到 `${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness/web.log`（`0600`），因此 token 不再进入 journald。仅在身份头与 capability 都不可用的场景（SSH 隧道直连 loopback、未授予 capability 的 tagged 设备等）使用；不要把结果写入文档或提交记录：

```bash
ssh <ssh-target> \
  'sed -n "s#^dsh web: ##p" \
     "${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness/web.log" \
   | tail -n 1' \
  | sed -E 's#http://127\.0\.0\.1:[0-9]+#https://<service-domain>#'
```

首次打开 token URL 或直接打开已注入身份头/capability 的域名后，浏览器会得到签名 cookie，随后页面跳转到不带 token 的根路径。connection 补丁把 `cookieMaxAgeDays` 固定为 365 天，且 cookie 跨 DSH 重启有效；删除 `client-connection/browser-session` 凭据记录并重启可全局撤销。

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

## 会话遥测（OpenObserve）

`web` profile 还会加载仓库中的 `@longred/deepseek-harness-observability`
自定义插件，把 Harness 自身的会话遥测写入 OpenObserve。它和 OpenCode Go
插件是两个独立的 bundle，都由 `ensureRuntime` 以 `file:` 依赖加软链接的方式
注册到 profile 清单里。

### 为什么需要自建 backend

上游 `@deepseek-ai/dsh-session-telemetry-otel` 的模式枚举只有 `FEEDBACK_ONLY`
和 `DISABLED`，构造时把 coordinator 固定在按需捕获，并且只对 `feedback/record`
事件触发上传：它能送出的只有用户反馈，没有 token、工具或错误信号。要取得这些
信号必须由部署提供自己的 backend。

单元里的 `DSH_TELEMETRY_DISABLED=1` 保留不变，作用有两点：

1. 关闭上游那一行，避免和自建行争用同一个 `sessionTelemetry` 单例服务（cordis
   对重复注册直接抛错）；
2. 阻止反馈被送到上游的默认端点 `https://harness-telemetry.deepseeksvc.com/v1/logs`。

自建行的 id 是 `deepseek-harness-observability`，与上游行不同名。

### 传输与依赖约束

插件**不依赖任何 npm 包**。profile loader 只为 profile 目录内的导入者安装解析
路由，而插件是从 Nix store 软链接进来的，Node 的原生解析看不到 dsh 安装的
`node_modules`；因此插件只能使用 Node 内置能力和 Node 22 的全局 `fetch`。上报
走 OpenObserve 的原生 JSON ingestion 接口，不需要 OTLP SDK，也不需要额外的
依赖树。插件不能读取 profile 之外的 npm 包——扩展它时要保持这条约束。

### 数据流

单元通过 `DSH_OBSERVABILITY_*` 环境变量提供配置，凭据只以文件路径形式传入：

| 变量 | 作用 |
| --- | --- |
| `DSH_OBSERVABILITY_URL` | OpenObserve 组织级 base URL，模块中定义 |
| `DSH_OBSERVABILITY_TOKEN_FILE` | 运行时解密出的 ingestion 凭据路径 |
| `DSH_OBSERVABILITY_LEDGER_STREAM` | 会话事件 stream，模块中定义为 `<hostname>_dsh_ledger` |
| `DSH_OBSERVABILITY_OPS_STREAM` | 运维信号 stream，模块中定义为 `<hostname>_dsh_ops` |

凭据文件在 `startHarness` 中展开 `XDG_RUNTIME_DIR` 后导出：agenix 给出的路径
本身带该变量，放在单元的 `Environment=` 里会依赖 systemd 自己的变量展开，因此
与仓库其他服务模块一样在 shell 里解析。

插件监听 `session/event` 和 `agent/error`：

- **ledger stream**：只投影白名单内的事件类型（`user/message`、
  `assistant/message`、`assistant/attempt`、`tool/call`、`tool/result`）；
  `assistant/message` 上的 `usage` 是会话日志里唯一的 token 记账来源，没有单独的
  用量记录；
- **ops stream**：`agent/error` 的 session、turn、step 和错误名。

### OTLP Trace 与指标

profile 还挂载 `dsh-otel`（`pkgs/dsh-otel`），把 agent loop 映射成 OpenTelemetry
GenAI 语义约定的 trace 和指标：

- trace：`invoke_agent`（turn，trace 根）、`dsh.step`、`chat {model}`、
  `execute_tool {name}`，每个 span 带 `gen_ai.conversation.id`（= session id）；
  模型调用 span 带 `gen_ai.usage.input_tokens`/`output_tokens`、
  `gen_ai.usage.cache_read.input_tokens`、`gen_ai.usage.cache_creation.input_tokens`、
  `gen_ai.request.model` 和 `gen_ai.response.model`，正好是 OpenObserve 的
  LLM 可观测性读取的列；
- 指标：`gen_ai.client.token.usage`、`gen_ai.client.operation.duration`、
  `gen_ai.execute_tool.duration`。

插件不发射 logs：harness 的 `dsh-session-telemetry-otel` 行负责 logs，`dsh-otel`
不注册 `SessionTelemetryBackend`，两者不冲突。上游是
[krimvp/dsh-otel](https://github.com/krimvp/dsh-otel)；本仓库在 Nix 里构建并用
esbuild 打包成自包含 ESM，作为路径插件加载，不依赖运行时 npm 解析。

导出走标准 `OTEL_*`：`startHarness` 用同一份 ingestion 凭据导出
`OTEL_EXPORTER_OTLP_ENDPOINT`、`OTEL_EXPORTER_OTLP_HEADERS`（含
`stream-name=<hostname>_dsh_llm`）、`OTEL_SERVICE_NAME` 和
`OTEL_RESOURCE_ATTRIBUTES`，trace 与指标直接写入 `<hostname>_dsh_llm`；环境变量
优先于插件 cordis 配置里的 `endpoint`。`captureContent` 保持 `false`：prompt、
工具参数和工具结果不离开主机；要会话内容视图时必须显式开启，并同时限制该 stream 的
访问和保留时间。

### 脱敏原则

记录由**逐字段白名单**构造，而不是截取事件体后依赖规则清洗：消息正文、工具参数、
工具输出、流式分片和错误文案从不读取，因此不存在需要在
`session-telemetry/record` waterfall 上挂规则才能删掉的字段。这条性质是刻意的，
不要为了加字段而改成复制事件体——一旦引入自由文本，脱敏规则就变成必需项。

### 环境不完整时的行为

缺 `DSH_OBSERVABILITY_URL`、缺凭据文件或凭据为空时，插件只记一条 warning 并
保持挂载但不导出，不会阻止 Harness 启动。导出失败只写 logger，不进入会话日志，
也不阻断 agent loop。缓冲上限 5000 条，超出部分丢弃并计入一次 warning。

### 验证

```bash
systemctl --user is-active deepseek-harness
# 插件装载与导出错误只出现在这里
tail -n 200 "${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness/web.log"
```

在 OpenObserve 中确认对应组织中出现了 ledger 和 ops 两个 stream，并有一个活动
会话产生的记录。服务健康只证明 Harness 进程可达，不证明遥测写入成功；两者要
分别报告。查询示例：

```sql
SELECT event_type, COUNT(*) AS n,
       SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens
FROM "<hostname>_dsh_ledger"
GROUP BY event_type
```

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

新增一台主机（例如 ThinkBook）时，本地配置之外还需要管理端两步，未完成前服务只在 loopback 可用：

1. 在管理端创建 `svc:<host-service>`、添加 `tcp:443` → `http://127.0.0.1:<dsh-port>` endpoint 并批准该主机。
2. 为该 `svc:` 和它的 capability 增加 grants（用户设备给网络访问，tagged 设备另加 capability）。

`tailscale-services.service` 在 advertise 未定义/未批准的 Service 时只打印警告并保持 active，所以 `systemctl --user status tailscale-services` 和 `tailscale serve status` 都要看。

## 状态和回滚

- npm runtime：模块定义的用户运行时目录。同一主机也跑 ACP profile 时用独立目录（ThinkBook 是 `web-runtime`），两个模块不会互相重装或补丁同一棵 npm 树。
- 服务日志：`${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness/web.log`（`0600`），由启动脚本创建并重定向，不写入 journald（systemd 的 `LogsDirectory`/`%L` 重定向会在首次启动时因目录未创建而失败）。
- Harness 数据：模块定义的 `DSH_HOME` 目录；其中包括会话、Settings 和 credentials。同一主机上的 ACP profile 用自己的 `dshHome`（ThinkBook 是 `~/.dsh`），两者不共享。
- 会话遥测：写入 OpenObserve 的 ledger 和 ops 两个 stream。ingestion 凭据与
  `openobserve-agent` 共用同一份 agenix 机密：OpenObserve 的 ingestion token 是
  组织级作用域，单独签发不会带来额外权限差异。需要按服务轮换时再拆分，并把两个
  模块的 `age.secrets` 声明一起改。
- 升级：只修改模块中的 `dshVersion`，先 dry-run，再观察安装日志和页面。
- 回滚：恢复旧版本并重新执行 Home Manager；不要删除保存会话和 credentials 的数据目录。

## 参考资料

- [DeepSeek Harness 仓库](https://github.com/deepseek-ai/deepseek-harness)
- [Quickstart](https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart)
- [Web server reference](https://deepseek-harness.github.io/deepseek-harness/en/reference/subsystems/web-server)
- [远程 Settings 限制](https://github.com/deepseek-ai/deepseek-harness/discussions/5829)
- [OpenCode Go session header discussion](https://github.com/deepseek-ai/deepseek-harness/discussions/6467)
- [OpenObserve JSON 摄取接口](https://openobserve.ai/docs/api/ingestion/logs/json/)
- [OpenObserve 与 OpenTelemetry](openobserve.md)
