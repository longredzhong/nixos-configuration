# DeepSeek Harness ACP 集成（Zed）

[返回文档索引](README.md) · [返回项目 README](../README.md) · 相关：[DeepSeek Harness](deepseek-harness.md)

## 作用范围

本文描述在 **非 NixOS 的开发机（standalone Home Manager 目标）** 上，用 Zed 通过 ACP 驱动 DeepSeek Harness 的方案：进程模型、配置分层、三条同步线（开发配置 / 模型配置 / 全局记忆）、机密处理、模块设计、桥接选型和验证方法。

本文不重复 [DeepSeek Harness](deepseek-harness.md) 里的内容：那篇讲 NUC 上的 **web** profile、Tailscale 身份反代和 token 回退。两篇共享同一个 `$DSH_HOME` 布局和同一份全局 patch 层语义，差别只在暴露方式和 profile。

## 架构决策

ACP 是 **stdio JSON-RPC** 协议：客户端把 agent 作为子进程拉起，用 stdin/stdout 交换帧。因此：

- **agent 必须跑在 Zed 所在的机器上。** 不要把 ACP 通过 SSH 或 Tailscale 隧道指向另一台主机：那样 agent 的工作目录（`session/new.cwd`）会落在远端，编辑的是远端的文件，对本地开发没有意义。
- Zed 用 **系统 shell**（`/bin/sh -c "<command> <args>"`）启动 agent，`agent_servers.<id>.env` 是**合并**进继承环境而非替换；stdout 必须是纯 JSON-RPC，stderr 可以随便写（Zed 会记进 `dev: open acp logs`）。
- `$DSH_HOME` 必须是**本机本地文件系统**：会话日志每会话用 `flock(2)` 单写者，POSIX 首次落盘依赖 hardlink，`storages/` 的 JSON 后端**没有跨进程写锁**。网络盘（NFSv3 的 advisory flock 不可靠）或同步盘会破坏这些前提。

由此得到的分层原则：

| 内容 | 是否跨机同步 | 机制 |
| --- | --- | --- |
| `$DSH_HOME/cordis.patch.yml`（全局 patch 层：MCP、全局行） | 是 | Home Manager 从仓库生成 |
| `$DSH_HOME/profiles/<name>/package.json`（bundle 清单、`file:` 依赖） | 是 | 生成脚本（`ensureRuntime`） |
| `$DSH_HOME/settings.yaml` 的 provider 与默认模型 | 是（**种子 + 合并**） | activation，只补缺失键 |
| `$DSH_HOME/AGENTS.md`（全局记忆） | 是 | `home.file` |
| `$DSH_HOME/skills/`（可选） | 是 | `home.file` |
| API key | 是（**不落盘**） | agenix → 启动环境变量 |
| `sessions/` `storages/` `attachments/` `cache/` | **否** | 每机运行态 |

## 要不要像 NUC 那样加 Tailscale Service

**结论：ACP 这条线不需要，也不应该加。** 理由是协议本身没有网络面。

NUC 上的 `svc:deepseek-harness` 存在，是因为它要暴露 **web** profile 的 HTTP 服务给浏览器；Tailscale 负责 TLS 终止、身份注入和反代到回环端口。而 `dsh --profile acp` 是一个 **stdio** 服务：它只读写 stdin/stdout，不监听端口，没有任何可被反代的东西。给 ACP 加 Service 不会带来任何可达性，只会多出一层没有对象的暴露面。

因此"在不同环境中都能操作"要拆成两个不同的问题：

| 想做的事 | 正确做法 |
| --- | --- |
| 在 thinkbook 上用 Zed 编辑 thinkbook 的代码 | 本地 `dsh --profile acp`，**不需要**任何 Service |
| 在任意设备用浏览器操作 **NUC** 上的会话 | 复用 NUC 已有的 `svc:deepseek-harness`，无需新工作 |
| 在任意设备用浏览器操作 **thinkbook** 上的会话 | 已由 `svc:deepseek-harness-thinkbook` 提供（见下） |
| 在别的机器上编辑 **thinkbook** 的代码 | ACP 不做这件事；用 Zed 的远程项目或 SSH，agent 仍要在代码所在机器上跑 |

第三行曾经是"不建议在第一步就做"的独立决策，现在 thinkbook 已经通过仓库模块启用了 web profile（`users/longred/fedora-thinkbook.nix` 里的 `hostServices.deepseekHarness`，访问方式见 [DeepSeek Harness](deepseek-harness.md)）。当时列出的三个顾虑这样处理：

- web 与 ACP 是两个进程，但**不共用** `$DSH_HOME`：web 用模块默认的 `~/.local/share/deepseek-harness/home`，ACP 用本机既有的 `~/.dsh`；`runtimeDir` 也分开（web 是 `web-runtime`），因为两个模块会安装并补丁同一棵 npm 树。因此 `storages/` 没有跨进程锁这件事不再构成风险。
- web 面那套版本敏感的运行时补丁不复制、不改写：两台主机 import 同一个 `modules/host-services/deepseek-harness.nix`，补丁只在模块里维护一份；升级 DSH 时按该文档验证一次即可。ACP 面仍然不需要这些补丁，两条线可以独立回滚（`hostServices.deepseekHarness.enable = false`）。
- 每台暴露的机器在管理端单独写 grants，并用主机专属的 Service 名和 capability（thinkbook：`svc:deepseek-harness-thinkbook` + `example.com/cap/deepseek-harness-thinkbook`）。

它与 ACP 的配置互不依赖，停掉 web 服务不影响 Zed 里的 ACP 会话。

**不要做的事**：不要试图把 thinkbook 的 Zed 指向 NUC 上的 ACP（例如 `ssh <nuc> dsh --profile acp`）。stdio 确实能穿过 SSH，但 agent 的工作目录会落在 NUC 上，编辑的是 NUC 的文件——对本地开发没有意义。

## 与 NUC 共享配置

共享的前提是先分清"意图"和"运行态"。NUC 上 `$DSH_HOME` 的内容可以按可移植性分成三类：

| NUC 上的内容 | 可否共享 | 共享方式 |
| --- | --- | --- |
| `settings.yaml` 里**手工维护**的 provider 路由 | 可以 | 仓库种子 `config/deepseek-harness/settings.seed.yaml` |
| `settings.yaml` 里插件写入的 `opencode-go-live-*` | 不需要 | 每台机器由插件按目录重新生成 |
| `settings.yaml` 里 UI 偏好（`ui-theme`、`ui-onboarding`） | 可选 | 默认不共享，属于本机偏好 |
| `cordis.patch.yml` | **只共享结构** | 见下：NUC 那份含明文凭据，不能直接复制 |
| 全局记忆 | 可以 | 仓库 `config/deepseek-harness/user-instructions.md` |
| profile bundle 清单 | 可以 | 模块里的 `profilePlugins` / `extraBundles` |
| `.credentials.yaml` | 不可以进仓库 | agenix→启动环境，或一次性手工放置 |
| `sessions/` `storages/` `attachments/` `cache/` | 不可以 | 运行态；`flock` + hardlink + 非可移植 |

两个关键判断：

1. **`settings.yaml` 本身不含机密**（只有 `apiKeyEnv` 变量名），所以它可以安全地进仓库——但它同时是**运行时可写**的。这就是为什么共享方式是"种子 + 只补缺失键"，而不是软链或整体覆盖。
2. **NUC 现在的 `cordis.patch.yml` 不能复制**：它把 OpenObserve 的 `Authorization: Basic …` 明文写在文件里。共享的是**这一行该长什么样**（凭据用 `!!js process.env.<VAR>` 引用），值必须换成文件/agenix 来源。迁移时应同时轮换那个凭据。

凭据的落地顺序（推荐）：

1. 用 `age -e -R <recipients>` 生成 `secrets/deepseek-api-key.age` 与 `secrets/opencode-api-keys.age`，接收者至少包含两个 Home Manager 目标的 `~/.ssh/id_ed25519.pub`。不要用 `ssh-to-age` 转换公钥，理由见 [Agenix 机密](../secrets/README.md)。
2. 在模块里声明 `age.secrets.<name>`，并把 `config.age.secrets.<name>.path` 传给 `credentialsFiles`。启动环境的优先级高于 `.credentials.yaml`，所以 agenix 值会覆盖机器上的旧值，不需要删除运行时文件。
3. 在那之前，harness 会回退到自己的 `$DSH_HOME/.credentials.yaml`；此时可以用任意一种一次性方式放置（手工编辑该文件，或写 `$DSH_HOME/.env`）。

共享方向也要明确：**仓库是手工编写内容的唯一来源**，NUC 的 live `settings.yaml` 只是"种子 + UI 运行期改动"。合并只补缺失键，所以把 NUC 已有的路由再放进种子不会破坏 NUC 的现状。

## 上游能力边界

`dsh --profile acp` 是上游明确标注的 **automation-only** ACP v1 服务：它有意省略 DSH 专属的展示层。实测（版本见文末验证记录）：

| ACP 方法 | 支持 | 说明 |
| --- | --- | --- |
| `initialize` | 是 | `authMethods: []`（无需认证）；声明 `sessionCapabilities{close,list,resume}`、`mcpCapabilities{http:true}` |
| `session/new` | 是 | 校验绝对 `cwd`、stdio/HTTP MCP；返回完整配置选项 |
| `session/list` | 是 | 按更新时间倒序分页，可按绝对 `cwd` 过滤 |
| `session/resume` | 是 | 仅限非活动会话；不重放历史 |
| `session/close` | 是 | 静默取消 + 落盘 + 只释放该会话作用域 |
| `session/set_config_option` | 是 | 只有 `model` 和 `reasoning_effort` 两个选项 |
| `session/prompt` / `session/cancel` | 是 | 每会话同时只允许一个 prompt |
| `session/update` | 是 | 已提交的消息与思考、通用工具生命周期、配置变更、上下文用量 |
| `session/request_permission` | 是 | 一次性 allow/reject |
| `session/load` | **否** | 返回 `-32601 Method not found` |
| modes / commands / plans / terminals / 客户端 fs / elicitation | **否** | 不声明也不响应 |

两个直接后果：

1. **`authMethods: []` 使官方 profile 永远进不了 ACP Registry**（Registry 的 CI 强制 `verify_agents.py --auth-check` 要求至少一个 `type:"agent"` 或 `type:"terminal"` 的 auth method）。社区桥接都是靠补 auth 才够格的。
2. Zed 只在 agent **声明**能力时才调用对应方法，所以缺 `session/load` 不会让线程不可用，但**线程历史的导入/回放会退化**。这一点必须实测，不要按文档假设。

另外：`acp` 是 `patchReload: startup`，改配置需要重启 agent 进程；`web` 模板是 `live`。两者语义不同。

## 三条同步线

### 开发配置

**全局 patch 层 `$DSH_HOME/cordis.patch.yml`** 对**所有** profile（含 `acp`）生效，是放跨 profile 共享行的唯一位置。补丁语义是**顶层 key 浅覆盖**：`config:` 会整体替换该行，`name`/`inject` 保留。一个 patch 指向不存在的 id 只打印 warning 并跳过；**空文件或只有注释的文件会让启动失败**，要禁用该层请写 `[]`。

示例（MCP 行；凭据通过环境变量引用，见"机密"）：

```yaml
- insert:
    - id: mcp-openobserve
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: openobserve-mcp
        transport: streamable-http
        url: http://<tailnet-ip>:5080/api/default/mcp
        headers:
          # !!js 表达式可用，但不能以反引号开头（见"最佳实践"）
          Authorization: !!js process.env.OPENOBSERVE_MCP_AUTH
        toolCallTimeoutMs: 120000
        # 保持 false：OpenObserve 不可达时不应阻止 Harness 启动
        failOnStartupError: false
```

**profile composition**：`$DSH_HOME/profiles/<name>/` 由 `package.json` 的 `dsh.profile.bundles` 决定层顺序，`dependencies` 里用 `file:` 指向 Nix store 里的插件。把现有 `ensureRuntime` 泛化成「profile 名 + bundle 列表 + 插件路径」即可让 `acp` 与 `web` 复用同一套逻辑：

```json
{
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-acp-app",
        "@longred/deepseek-harness-opencode-session",
        "@longred/deepseek-harness-observability",
        "dsh-otel"
      ],
      "patchReload": "startup"
    }
  }
}
```

### 模型配置

模型配置分两层，缺一不可：

- **provider 路由**在 `settings.yaml` 的 `llm-pi-ai.providers`。`dsh-base` 把 `llm-pi-ai` 挂成**休眠**状态（零路由，模型选择器里只有 `deepseek-official`），只有 settings 层提供了 provider 才会有对应路由。`opencode-go-live-*` 是由 `@longred/deepseek-harness-opencode-session` 插件按协议自动写入的三个受管路由。
- **默认选择**用 patch 固定 `id: acp`（并同时固定 `id: agent-default-model`，让子代理等其它入口一致）：

  ```yaml
  - id: acp
    config:
      provider: opencode-go-live-chat
      model: deepseek-v4.1-flash
  ```

`settings.yaml` 是 **namespace → 用户分区** 的文档，解析顺序是 `schema 默认 → composition base → 用户分区`。它被插件周期性重写（受管路由每 4 小时刷新一次），所以：

> **`settings.yaml` 只能是真实文件，不能 `home.file` 软链。** 软链会因运行时写入而失败。

**合并语义：种子优先，但只对种子提到的键。** 部署时递归应用仓库种子——种子里的键覆盖磁盘上的值，种子没提到的键一律不动。于是「模型配置由仓库拥有」和「运行期状态不被破坏」可以同时成立：插件写入的 `*-live-*` 受管路由、UI 偏好、各机自己的 `agent-default-model` 都原样保留。

这一点很重要，因为**只补缺失**的旧语义修不了坏配置：一台机器上遗留的 `llm-deepseek.baseURL` 覆盖会让 `deepseek-official` 悄悄指向别的网关，症状是每个请求都 401 而 key 本身没问题。种子显式写出 `baseURL` 才能把它清掉。

种子按用途分层，避免把需要凭据的路由推到拿不到凭据的机器上：

| 种子 | 内容 | 加载条件 |
| --- | --- | --- |
| `settings.seed.yaml` | `deepseek-official`（`llm-deepseek`：`protocol` / `apiKeyEnv` / `baseURL`） | 总是 |
| `settings.seed.opencode.yaml` | `opencode-go` 静态路由 | `openCodeRoutes.enable` |
| `settings.seed.<host>.yaml` | 该机自己的网关与默认路由（例如 ten-rings） | `extraSettingsSeeds` |

另有一条更容易踩的约束：**`settings.yaml` 不支持 `${ENV_VAR}` 插值**，只接受字面值。密钥要靠 `apiKeyEnv: <变量名>` 这种「凭据引用」间接使用。

**只声明本机能认证的路由。** 一条 route 注册成功不代表它能工作：`apiKeyEnv` 解析不到值时第一次请求以 `MISSING_CREDENTIAL` 失败，而**解析得到但服务端拒绝**时是另一类错误。两者都会让选择器里多一条"选中就失败"的条目——而 ACP 客户端（Zed）**会记住上次选择的模型**，所以一次误选就会让之后每个新线程都失败，症状看起来像"harness 坏了"。

实测过的第三种情况：OpenCode Zen 的 7 个免费模型用同一个 key 能通过认证，但服务端返回 `403 FreeTierError: OpenCode's free tier can only be used from within OpenCode`。**这类路由不能靠换 key 修好**，只能不声明——它已从本仓库的配置里移除。

**一个凭据可以服务多个变量名。** OpenCode Go 与 OpenCode Zen 接受同一个 key，所以 `OPENCODE_GO_API_KEY` 和 `OPENCODE_API_KEY` 指向**同一个密文**，而不是存两份（存两份迟早分叉）。`credentialsFiles` 里把两个变量名映射到同一个 `config.age.secrets.*.path` 即可。

从「开启」切到「关闭」是**一次性迁移**，不是自动收敛：bundle 清单和 `settings.yaml` 里的路由都可能是上一代留下的。provision 只会移除它在 `dsh.profile.homeManagerPlugins` 里记录过的 bundle（不认识更早的世代留下的条目）；种子优先的合并只覆盖种子**提到**的键，删不掉旧键。切换后要手工清一次遗留路由。

### 全局记忆

DSH 没有名为 "global memory" 的功能。用户级全局指令就是**唯一一个** `$DSH_HOME/AGENTS.md`：

- 它在第一个请求里作为随历史持久化的 baseline 注入，位置在**项目指令链之前**，因此**优先级最低**——项目 `AGENTS.md` 永远覆盖它，system/developer/用户直指令覆盖两者。
- 项目链从项目根（默认 `.git` 标记）逐级到会话工作目录，每个目录按 `AGENTS.md` → `CLAUDE.md` → `AGENTS.local.md` → `CLAUDE.local.md` 加载；项目根之上的父目录不读。
- **全局文件与项目链共享一个字节预算**（base 里是 `maxBytes: 65536`）。超预算时先整体丢弃较宽泛的文件，再截断最具体的那个。所以全局记忆要写短：适合放跨项目的个人偏好，不适合放项目规则。
- 内容相同的兄弟文件（例如与 `AGENTS.md` 重复的 `CLAUDE.md`）只渲染一次。

仓库里的源文件叫 `config/deepseek-harness/user-instructions.md`，由模块用 `home.file` 软链到 `$DSH_HOME/AGENTS.md`（DSH 只读它，软链安全）。**源文件名不能叫 `AGENTS.md`**——那样 DSH 会把仓库里的源文件当成该目录的项目级指令，任何一次读写都会让这份"全局"内容以项目指令的身份重复注入；原因见「最佳实践」。

## 机密

凭据解析优先级是固定的：**启动环境 > `$DSH_HOME/.credentials.yaml` 的 `refs` > `<cwd>/.env` > `$DSH_HOME/.env`**。配置里只写变量名。

因此推荐让 **agenix 提供的文件在 wrapper 里被读成环境变量**：

- 启动环境优先级最高，所以 thinkbook 上**不需要** `.credentials.yaml`，也不会和 NUC 上由 UI 托管的凭据互相干扰。
- 仓库、Nix store、patch 文件里都不出现明文；`cordis.patch.yml` 里只出现变量名。
- 顺带修掉现存问题：NUC 的 `$DSH_HOME/cordis.patch.yml` 现在把 OpenObserve 的 `Authorization: Basic …` **明文**写在文件里（文件自身注释也承认，0600）。迁移到本文方案时应改为环境变量引用，并轮换该凭据。

需要的变量：`DEEPSEEK_API_KEY`、`OPENCODE_GO_API_KEY`、`OPENCODE_API_KEY`，以及给 MCP 用的完整 header 值（例如 `OPENOBSERVE_MCP_AUTH`）。前三个与 `apiKeyEnv` 的名字一一对应。

不要试图把 `$DSH_HOME` 整体放进同步盘；也不要指望文件权限能隔离 agent——agent 的工具进程和凭据文件是同一个 OS 用户。

模块侧的接口是 `credentialsFiles`（环境变量名 → 文件路径），值由 wrapper 在 exec 前读出并导出。用 agenix 时路径形如 `${XDG_RUNTIME_DIR}/agenix/<name>`，所以该选项是**字符串**而不是 Nix `path`：只有启动时的 shell 才能把它展开成绝对路径。

新增机密用 `age -e -R <recipients>`，接收者是各目标的 `~/.ssh/id_ed25519.pub`（不是 `ssh-to-age` 转换出来的 X25519 公钥），理由见 [Agenix 机密](../secrets/README.md)。生成后先用本地身份解密一次做往返比对，再提交密文。

凭据的写入和轮换用 `scripts/dsh-credentials.py`（值只经不回显的交互输入，不落明文、不进 argv）：`list` 查看密文状态与运行时库里的值长度，`set <ENV>` 重新加密一个，`set-all` 逐个提示全部（不打算改的直接回车跳过），`verify` 逐个往返校验。`list` 报出的长度能直接暴露占位符——一个 2 字节的 key 就是"路由存在但永远失败"的根因。

一个密文可以服务多个环境变量名：脚本以密文为键、变量名为值，所以 OpenCode Go 与 Zen 共用同一个文件（它们接受同一个 key），`list`／`verify` 会把两个名字并列显示，不需要存两份、也就不会分叉。

改完密文后必须让目标主机重新解密：把 `secrets/*.age` 同步过去（`set --push <host>` 会做这一步），在那边 `home-manager switch`，然后重启 agent 进程。只改文件不 switch，`$XDG_RUNTIME_DIR/agenix/` 里还是旧值。

## 模块设计

实现位于 `modules/host-services/deepseek-harness-acp.nix`，通过 `hostServices.deepseekHarnessAcp`
启用。它和面向 web/Tailscale 的 `modules/host-services/deepseek-harness.nix` 是**两个模块**，
但刻意共用同一套 `$DSH_HOME` 与 runtime 布局，因此一台主机可以只启用其中一个，日后也可以两个
都启用而仍然只有一个 runtime 目录。

模块负责的是"运行时不变量"：

- `dshVersion` 固定的 npm 安装，带版本戳快速路径，只在版本或 bundle 变化时重装；
- `$DSH_HOME/profiles/<name>/` 的 profile composition（`file:` 依赖软链 + bundle 清单）；
- 由仓库生成的静态配置：profile patch、全局 patch 层、settings 种子；
- `dsh` 入口脚本：按需 provision → 从文件导出凭据 → `exec` harness；
- `systemd.user.services.deepseek-harness-runtime`（oneshot，登录时预热，避免第一次 Zed 会话
  在编辑器里等一次网络安装）。

对应的仓库侧内容：

| 文件 | 作用 |
| --- | --- |
| `config/deepseek-harness/settings.seed.yaml` | 模型配置种子；只补缺失键 |
| `config/deepseek-harness/user-instructions.md` | 全局记忆，安装为 `$DSH_HOME/AGENTS.md` |

要点：

- **运行时安装不能在 Zed 启动路径上做重活**。`provision` 先比版本戳，命中就直接返回；未命中才
  联网 `npm install`，并且用 `flock` 串行化，避免两个 Zed 线程同时安装。
- **`dsh` 脚本的 stdout 必须留给 profile 自己**。provision 的所有输出都重定向到 stderr；Zed 把
  非 JSON 行当作 transport 错误并静默丢弃，所以 stdout 一旦被污染，症状是"会话无声地失败"。
- **`web` profile 需要 `--expose-internals`**（HMR loader 的原生回退）；`acp` 的 HMR 关闭，不需要，
  统一加上也无害。
- **两个 profile 都必须用官方 nodejs.org 构建**（`pkgs/nodejs-official`）。dsh 0.1.6-alpha.2 起，
  启动任何 profile 都会经过 `node-addon-require-builtin`，其原生预编译只识别官方 Node 的 V8 布局；
  nixpkgs 的 `nodejs_22` 与 `nodejs_24` 都会以 `Unsupported/no-getter` 在 host preparation 阶段
  失败。npm 仍来自 nixpkgs。
- **`dsh` 不支持 `socks5://` 代理**（会静默跳过该 scheme）；需要代理时用 `http://<proxy-host>:<port>`。

### 待跟进的重构

两个模块目前各自维护一份 runtime 安装脚本和 `$DSH_HOME` 路径常量。合并成一个 optioned 模块
（`hostServices.deepseekHarness.{web,acp}`，写法对齐 `modules/host-services/openobserve-agent.nix`）
是更干净的目标形态，但 web 模块当时带着未提交的 Tailscale capability 改动，先不动它可以把风险
限制在新增文件内。合并时还要顺带处理：

- **stream 名按主机派生**：web 模块现在硬编码 `nuc_dsh_ledger` / `nuc_dsh_ops` / `nuc_dsh_llm`，
  多机共用同一个 OpenObserve 组织时会串流。

### 选择 `$DSH_HOME`

Harness 解析顺序是**显式配置 > `$DSH_HOME` > `~/.dsh`**。模块的 `dshHome` 默认沿用 web 模块的
服务式路径（`~/.local/share/deepseek-harness/home`），因为 NUC 上的 web 服务就是这样配置的。

**在一台已经用默认 home 交互式用过 harness 的机器上，必须显式指向 `~/.dsh`。** 否则 harness
会去读一个空 home：已有的 `settings.yaml`、provider 路由、`.credentials.yaml` 和会话全部被
绕过，而新的空 home 会被悄悄建起来——症状是"配置明明部署了，模型列表却是出厂默认"。模块的
`dsh` 入口脚本会显式导出 `DSH_HOME`，所以这个选择不依赖调用方（Zed、终端、headless）的环境。

判断方法：看目标机上 `.dsh/settings.yaml` 与 `.dsh/.credentials.yaml` 是否存在且非空。

## Zed 接入

**不要让 Home Manager 接管 `~/.config/zed/settings.json`。** 该文件是手工维护的 JSONC（带尾逗号），并且可能包含 provider 凭据；整体接管风险大于收益。用 Zed 自己的界面写入：

`Ctrl+Shift+P` → `agent: open settings` → External Agents → `Add Agent` → `Add Custom Agent`

形如：

```json
{
  "agent_servers": {
    "DeepSeek Harness": {
      "type": "custom",
      "command": "/home/<user>/.nix-profile/bin/dsh",
      "args": ["--profile", "acp"],
      "env": { "DSH_HOME": "/home/<user>/.local/share/deepseek-harness/home" }
    }
  }
}
```

字段集（以 Zed 源码为准，文档并不完整）：`type`（必填，`"custom"` / `"registry"`）、`command`、`args`、`env`、`default_mode`、`default_config_options`、`favorite_config_option_values`。

- **没有** `default_model` / `favorite_models`，也**没有** per-agent 的 `agent` 子对象：那是顶层 `agent.*`，**对外部 agent 无效**。外部 agent 的模型选择只能来自 ACP 的 `configOptions`。
- **不要设 `default_mode`**：DSH 不实现 ACP modes。
- 用**绝对 `command`**：KDE/GNOME launcher 启动的 Zed 走登录 shell 的环境，`~/.nix-profile/bin` 不一定在 PATH 里。
- 想固定初始模型可用 `default_config_options`，值就是 ACP 选项的字符串（DSH 的 model 选项值是 `["<provider>","<model>"]` 的 JSON 文本）：

  ```json
  "default_config_options": {
    "model": "[\"opencode-go-live-chat\",\"deepseek-v4.1-flash\"]",
    "reasoning_effort": "high"
  }
  ```

  更稳的做法是把它留在 profile patch（`id: acp`）里作为唯一来源，让 Zed 的下拉只做 per-session 覆盖。

### Zed 编辑器里能看到哪些控件

Zed 的输入框把 agent 的 ACP `configOptions` 渲染成选择器，因此**能否出现控件完全取决于
`session/new` 当时声明了什么**。两个桥接的差别如下（本仓库现在用 enhanced）：

| 控件 | 官方桥 | 增强桥 | 条件 |
| --- | --- | --- | --- |
| 模型 | 是 | 是 | 总是；选项来自实时 LLM 目录，按 provider 分组 |
| 思考强度 | **有条件** | **有条件** | 只有**当前选中的那个模型**声明了 `reasoningEfforts` 时才声明该选项 |
| 权限预设 | 否 | 是 | 增强桥挂载了 `permission-presets`，三档：`read-only` / `workspace-write` / `danger-full-access` |
| Agent 预设 | 否 | 是 | 会话工具/提示词组合；**非空会话锁定**，切换需新会话 |
| 模式（plan 等） | 否 | 是 | `plan_mode`，category `plan` |

思考强度这条最容易误判成"坏了"：模型选择器换了 provider 之后控件会消失，因为新 provider 的模型没声明
effort。修法是在 `settings.yaml` 里给该 route 的模型加 `reasoningEfforts`，键是 DSH 的等级、值是
provider 侧的取值：

```yaml
    ten-rings:
      api: openai-responses
      models:
        - id: gpt-5.6-terra
          reasoningEfforts:
            off:            # 空值 = 该等级不发送 reasoning 参数
            low: low
            high: medium
            max: high
```

**只声明 provider 真正接受的取值**：声明了就意味着选择器会把它发出去，错的值会让请求 400。落地时逐个
等级发一次最小请求验证。

权限和模式在**官方桥**下没有对应控件，那里只能：

- 用**启动时**的 `DSH_PERMISSION_MODE`（`read-only` / `workspace-write` / `danger-full-access`）
  固定整台机器的沙箱与审批策略——这是模块选项，不是 per-thread 开关；
- 或者用 web profile 的界面，那里有完整的设置面。

本仓库现已改用增强桥（`bridge = "enhanced"`），上述三档权限、agent 预设和 `plan_mode` 都在编辑器里可
选，`DSH_PERMISSION_MODE` 只作为初始值。

## 桥接选型

官方 `--profile acp` 零第三方依赖，但如上表所述缺少交互面。社区为此做了多个桥接，**全部是第三方、非 DeepSeek 官方**，且截至撰写时 **ACP Registry 里没有任何 DeepSeek Harness 条目**（有 4 个未合并 PR）。

| 项目 | 形态 | 补上的能力 | 主要风险 |
| --- | --- | --- | --- |
| `dsh-acp-enhanced` | dsh 插件 bundle | `session/load`、plans、真 diff/terminal 卡片、把 fs/terminal 委派给 Zed、elicitation、`/preset` | 单作者，文档最少 |
| `dsh-acp-v1`（`dangpangch/dsh-acp`） | dsh 插件 bundle | `load/list/delete/resume/close`、plans、`/` 命令 + skills、preset/model/effort 选择、elicitation | 使用量很小；忽略客户端 MCP |
| `@openma/deepseek-harness-acp` | 插件或独立 server | 全套 + 三种 auth + display terminal | GitHub 许可与 npm 声明不一致 |
| `deepseekharness-acp-interactive`（`ClickPM/dsh-acp-interactive`） | 独立 npm server（自带 composition） | `session/load` 回放、plans、subagent 卡片、`/` 命令、elicitation | **不读 `$DSH_HOME/cordis.patch.yml`**，本仓库的全局 patch 层会失效 |
| `@anht3889/dsh-acp-zed` | 独立 npm server | `session/load` 回放、MCP OAuth | npm 包**没有 repository 字段**，源码不可追溯 |

选型原则：

1. **优先选「dsh 插件 bundle」形态。** 它仍在 dsh 的 profile/patch 机制内，`$DSH_HOME/cordis.patch.yml` 全局层、`settings.yaml`、agenix 环境变量全部照旧生效。独立 server 形态自带 composition，会把本仓库的声明式配置旁路掉。
2. **不要用 `dsh plugin add` 联网动态安装。** 照抄仓库既有做法（`pkgs/deepseek-harness-opencode-session` 等）：固定 commit → Nix 构建 → profile `file:` 依赖软链。这样没有运行时联网安装，也没有供应链漂移。
3. **先官方、后升级。** 官方 profile 足以跑通整条链路（进程、密钥、settings、记忆、Zed 接入）；等 plans/历史/slash 命令确实影响日常使用，再引桥接。

### `dsh-acp-enhanced`：从上游缺陷到本仓库的 fork 补丁

本仓库把增强桥打包成 `pkgs/dsh-acp-enhanced`（自带嵌套 `node_modules`，无需运行时 `npm install`），
模块侧用 `bridge = "enhanced"` 切换。**该 bundle 现在固定在本仓库作者维护的 fork 上**，因为上游 0.7.0
在 harness 0.1.6-alpha.2 上不能交付回答。

**上游缺陷（2026-09-18 用 `ACP_DEBUG=1` 定位）：事件契约不匹配，不是配置问题。** 增强桥只在一处把
流式内容变成 ACP chunk：`ctx.on('session/event')` 的 `case 'assistant/chunk'` → `handleChunk()`，由
`block-start` / `text-delta` / `block-end` 累积并发出 `agent_message_chunk`；另一个 `assistant/message`
分支当时只做 usage 统计与图片占位符，**文本转发只存在于 `session/load` 的历史回放路径**。而 alpha.2
的一轮真实 prompt 事件流是
`turn/start → step/start → user/message → assistant/message → step/end → turn/end(reason=completed)`——
**`assistant/message` 到了，`assistant/chunk` 一条都没有**。佐证：在 alpha.2 的整个 runtime 里，
`assistant/chunk` 只出现在 `dsh-session-format-*` 的迁移器和 JSONL 持久化 worker 中，**已经没有实时
emit 方**，它是被新版事件模型淘汰的遗留事件。症状是 turn 以 `stopReason: end_turn` 结束、`usage_update`
报告非零 output tokens，而客户端一条 `agent_message_chunk` 都收不到（面板空白）；控件面则完全正常
（`permission_preset` category=`mode`、`agent_preset` category=`model_config`、`plan_mode` category=`plan`、
`loadSession: true`）。对照实验钉死了归因：同一 route、同一 harness、同一探针，官方桥 `TEXT_LEN: 8`，
增强桥 `TEXT_LEN: 0`。

**本仓库的补丁**：`pkgs/dsh-acp-enhanced` 现在用 `fetchgit` 固定
`longredzhong/dsh-acp-enhanced@97d175a`（0.8.0），该提交在实时路径补了 `emitMessageFallback()`——把已提交的
`assistant/message` 中**流式尚未送达的部分**转发给客户端。去重按内容前缀比较（`streamedText` /
`streamedThought` 每个 step 累积自所有上线路径，含 `block-end` 提交与 `delta` 合并刷新），因此发
`assistant/chunk` 的宿主不受影响：既不重复也不丢内容；前缀比较而非块下标匹配，是因为重试会重启块下标。
上游仍未合入，所以这是一个**本地 pin**：等上游发布修复后，把 `pkgs/dsh-acp-enhanced/default.nix` 换回
npm tarball 即可（文件里那段注释写明了切换点）。

**当前状态（2026-09-18，fedora-thinkbook，harness 0.1.6-alpha.2）**：`bridge = "enhanced"`，
`AGENT: deepseek-harness-acp-enhanced 0.8.0`；探针拿到三档权限模式、全部五个 config option，以及
`agent_message_chunk: PROBE-OK`（`TEXT_LEN: 8`、`DIRTY_STDOUT_LINES: 0`、exit 0）；`scripts/acp-client.mjs`
全套 PASS。也就是说**"选择器"与"能回答"现在同时成立**，这正是当初切回 official 时放弃的目标。

## 最佳实践

- **项目 `.env` 里不能放代理变量。** dsh 启动 profile 前会把**当前工作目录**（Zed 里就是打开的项目根目录，不必是 git 根）的 `.env` 当作 project 层加载，而 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` / `NO_PROXY`（大小写都算）连同 `DSH_*` / `XDG_*` 前缀属于 bootstrap-only：它们决定进程如何启动、代码与指令从哪里加载、流量走哪条路由。这类名字只允许由**继承的启动环境**提供，代理类额外允许由 `$DSH_HOME/.env` 提供（只有 harness home 这一层放宽，因为它是用户自己的文件，不会随仓库走）。所以一个为 direnv 准备的、带 `https_proxy` 的项目 `.env` 会让任何以该项目为工作目录的 ACP 会话在 profile 启动前抛 `dsh: <dir>/.env sets "https_proxy", which only the launching environment may set` 并退出 1。注意 `dsh --help`、`--dump-config` 仍然正常——它们不走 profile 启动路径，所以这个故障看起来像"时好时坏/只有 Zed 里才犯"。修法是让这些名字离开项目 `.env`：值留在 direnv 读的另一个文件里（`.env.proxy` + `dotenv_if_exists .env.proxy`），harness 自己的代理改由 `$DSH_HOME/.env`、启动环境，或模块的 `hostServices.deepseekHarnessAcp.proxyEnvironment`（wrapper 在 exec 前导出）提供。
- **`!!js` 表达式不能以反引号开头。** 用户 patch 文件由 js-yaml 以 `JSON_SCHEMA` + `!!js` 标量标签解析，而 `!!js \`Bearer ${...}\`` 这种以反引号开头的字面量会让标量解析失败，报 `cannot resolve a node with !<tag:yaml.org,2002:js>`。写 `!!js process.env.X`（把完整 header 值放进环境变量），或 `!!js process.env.A + process.env.B`。
- **`export VAR="$(cat <file>)"` 不会因为读不到文件而失败。** `export` 返回的是它自己的状态，不是命令替换的状态，所以 `set -e` 也拦不住：变量被静默设成空串，直到第一次请求才以 `MISSING_CREDENTIAL` 暴露出来。另外 agenix 把机密放在 `$XDG_RUNTIME_DIR` 下，而**非登录启动**（桌面项拉起的编辑器、一条普通 ssh 命令）里这个变量可能是空的。模块因此显式回退到 `/run/user/$(id -u)`，并在读不到文件时直接报错退出。
- **不要用默认的 PyYAML 解析 `settings.yaml`。** 它的解析器遵循 YAML 1.1，会把裸写的 `off:` / `no:` / `yes:` 读成布尔值——而 harness 用的是 js-yaml 的 `JSON_SCHEMA`，那里 `off` 是字符串。用默认解析器改写一次，`reasoningEfforts.off` 就变成 `false`，整个 provider route 校验失败并消失（症状是 `no adapter registered for provider "<route>"`）。改写前先装载只把 `true`/`false` 当布尔的解析器。
- **`--dump-config` 不证明 `!!js` 生效。** 它按设计**原样回显**表达式不求值。要验证求值，必须让求值结果产生可观测差异（例如把 provider 交给 `!!js` 后看 `session/new` 选中了哪条路由）。
- **`settings.yaml` 是运行时可变的**：种子化只能补缺失键，不能整体覆盖，也不能软链。
- **验证脚本要能压出 stdout 纯净性问题**：客户端必须把任何非 JSON 行计为失败，而不是忽略。
- **别在 Zed 里用一次会话做判断**：`dev: open acp logs` 里有握手、capabilities 和 agent stderr；`patchReload: startup` 意味着改配置后要重启 agent 进程。
- **两个 dsh 进程共用一个 `$DSH_HOME` 要谨慎**：会话日志有 `flock` 保护，但 `storages/` 的 JSON 后端没有跨进程锁。要在同一台机器同时跑 `web` 和 `acp`，要么接受这个风险，要么拆成两个 `$DSH_HOME`（代价是不共享会话与 settings）。
- **provision 的版本戳必须包含 bundle 清单。** provision 命中戳就直接返回，如果戳只覆盖插件与生成的
  patch、不含 `removeBundles` / `ensureBundles`，那么改 `bridge`（或改任何 bundle 增减）都不会触发重
  provision：服务照样 `active`、握手照样成功，但 profile 的 `dsh.profile.bundles` 仍是上一代，控件面
  悄悄停在旧的那一层。诊断入口是 provision 的 stderr——它每次增删都会打印 `removed plugin …` /
  `restored bundle …`，一行都没有就说明根本没跑。
- **`dsh.profile.bundles` 的顺序是语义，不是排版。** dsh 把这份清单折成有序的补丁层栈，落在 ACP bridge 之后的层会被丢掉。0.1.6-alpha.1 上实测：`[base, acp-app, <插件>]` 会让模型路由整体失效（`session/new` 返回 `no adapter registered for provider "<route>"`，而 `settings.yaml` 里的 route 文本完全正确，看起来像 key 或网关的问题），换成 `[base, <插件>, acp-app]` 立刻正常。profile 模板自带的顺序恰好是前者，而 provision 过去只会 append，于是**新建的 home 拿到坏顺序、旧 home 因为历史保留好顺序**——症状是"同一份配置，一台机器能用、另一台不能用"。模块现在声明 `desiredBundles`，并在 provision 的最后一步把所有 bundle 变更归一化成这个顺序。
- **不要在仓库里放名为 `AGENTS.md` 的全局记忆源文件。**`$DSH_HOME/AGENTS.md` 是目标路径，但只要源文件在仓库里叫 `AGENTS.md`，DSH 就会把它当成该目录的**项目级**指令文件：任何对该目录的读写都会让这份"全局"内容以项目指令的身份注入当前会话。源文件必须用一个非magic 名字（本仓库用 `user-instructions.md`），由模块安装到目标路径。

## 验证

静态（在仓库侧）：

```bash
just check-fast
just eval-home '<user>@<host>'
```

目标主机上的进程级验证——不依赖 Zed，直接压 ACP：

```bash
# 1) profile 能初始化，且 patch 生效
dsh --profile acp --dump-config | grep -A4 'id: acp'

# 2) stdout 纯净性 + 握手（预期两帧 result，然后退出 0）
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"/tmp","mcpServers":[]}}' \
  | dsh --profile acp
```

要覆盖 `session/list`、`session/load`（预期 `-32601`）、`session/set_config_option` 和模型分组，用仓库里的
`scripts/dsh-acp-probe.py`——一个只依赖标准库的 ACP 客户端，按 Zed 的方式（同样的 `initialize`
capabilities）起进程，然后报告三件事：控件面（`modes` 与 `configOptions` 的分类）、**是否真的收到
`agent_message_chunk`**、以及 stdout 是否始终是纯 JSON。只有拿到助手文本才退出 0，所以它能直接当
冒烟测试用（这也是当初识破 `dsh-acp-enhanced` 静默无输出的工具）：

```bash
# 目标主机上，用模块安装的 wrapper（它会自己解析凭据）
scripts/dsh-acp-probe.py --command "$(command -v dsh)" --prompt 'Reply with exactly: PROBE-OK'

# 换一条 route / 模型验证选择器与凭据
scripts/dsh-acp-probe.py --model '["<route>","<model>"]'
```

其它脚本和 Zed 都应按 **`/bin/sh -c`** 的方式起进程，与 Zed 的启动方式一致。

Zed 侧：`dev: open acp logs` 看握手、capabilities 和 stderr；确认线程能创建、能流式输出、模型下拉里出现期望的 provider 分组。

## 状态和回滚

- runtime：模块定义的用户运行时目录（版本固定，依赖树由 npm 决定）。
- `$DSH_HOME`：`settings.yaml`（种子 + 运行时写入）、`cordis.patch.yml`（生成）、`profiles/`（生成）、`AGENTS.md`（生成）、`.credentials.yaml`（本方案下不需要）、`sessions/` `storages/`（本机运行态，不要删、不要同步）。
- 回滚：Home Manager 回退到上一代即可恢复生成的配置层；**不要删除 `sessions/`**。
- 升级：改模块里的 `dshVersion`；如果新版 dsh 依赖的原生解析器与官方 Node 版本绑定，同步
  `pkgs/nodejs-official` 的官方 Node 版本。先 dry-run，再重启 agent 进程观察。

## 风险

- 上游 `acp` 能力面会随版本变化（npm 上的 latest 与 master 长期不一致），任何"缺 X"的结论都要按实际安装版本重新确认。
- 无 `session/load` 时 Zed 的线程历史/导入行为未实测到确定结论，需要按上面方法在目标机上确认。
- runtime 由 npm 安装，版本固定但依赖树不固定；这是仓库现状，升级前应记录实际版本。
- 官方 profile 的 `authMethods: []` 意味着它不会被 ACP Registry 收录；走 Registry 只能依赖第三方桥接。

## 参考资料

- [DeepSeek Harness 仓库](https://github.com/deepseek-ai/deepseek-harness)
- [dsh-acp 包说明](https://deepseek-harness.github.io/deepseek-harness/en/reference/config-catalog)（automation-only 契约与限制）
- [配置模型（provider / settings.yaml）](https://deepseek-harness.github.io/deepseek-harness/en/guide/providers.md)
- [Memory MCP 与用户 patch 层持久化](https://deepseek-harness.github.io/deepseek-harness/en/guide/mcp-memory.md)
- [网络代理支持范围](https://deepseek-harness.github.io/deepseek-harness/en/guide/network-proxy.md)
- [Zed External Agents](https://zed.dev/docs/ai/external-agents)
- [Zed ACP agent_servers 定义](https://github.com/zed-industries/zed/blob/main/crates/settings_content/src/agent.rs)
- [Agent Client Protocol v1](https://agentclientprotocol.com/protocol/v1/overview)
- [ACP Registry](https://github.com/agentclientprotocol/registry)

## 验证记录

2026-09-17，目标主机 fedora-thinkbook（Fedora 44，standalone Home Manager）与 NUC（对照）。使用安装在 `~/.local/share/deepseek-harness/runtime` 的 `@deepseek-ai/dsh@0.1.6-alpha.1`，在**隔离的临时 `$DSH_HOME`** 下通过 `/bin/sh -c "<node> --expose-internals <dsh> --profile acp"`（与 Zed 启动路径一致）驱动 ACP。结果：`initialize` / `session/new` / `session/list` / `session/close` 成功，`session/load` 返回 `-32601`，`stdout` 无非 JSON 行；种子化 `settings.yaml` + `- id: acp` patch 后模型分组出现 `opencode-go-live-chat`；`cordis.patch.yml` 里的 `!!js process.env.<VAR>` 在环境变量存在/缺失两种情况下产生不同结果，确认求值生效。以上为方法可复现的结论，具体版本与命令输出以目标机当前状态为准。

2026-09-18，目标主机 nuc（Fedora，standalone Home Manager），升级到 `@deepseek-ai/dsh@0.1.6-alpha.2`，两个 runtime 都用 `pkgs/nodejs-official`（官方 nodejs.org 22.23.2）重建。结果：`deepseek-harness.service` active、loopback `127.0.0.1:3080` 返回 401、launch-token URL 返回 303，`journalctl --user -u deepseek-harness` 无新错误；web profile 清单包含 `deepseek-harness-opencode-session`、`deepseek-harness-observability`、`dsh-otel` 三个 bundle；`dsh --profile acp --dump-config` 退出 0，说明 ACP composition、`file:` bundle 与插件解析在 alpha.2 上可加载。真实 prompt 的 `agent_message_chunk` 验证尚未在 alpha.2 上重跑。

2026-09-18，目标主机 fedora-thinkbook（Fedora，standalone Home Manager）：Zed 以 `~/.nix-profile/bin/dsh --profile acp` 启动 agent，打开的项目工作目录里有一份为 direnv 准备的 `.env`，含 `https_proxy` / `no_proxy`。症状是 ACP server 立刻 `exit status 1`，stderr 为 `dsh: <项目目录>/.env sets "https_proxy", which only the launching environment may set ...; export https_proxy, or put it in <$DSH_HOME>/.env`；同一个目录里 `dsh --help` 正常退出 0。把两个代理变量移到 `.env.proxy`、`.envrc` 改为 `dotenv_if_exists .env` + `dotenv_if_exists .env.proxy` 并 `direnv allow` 后：`.env` 中不再有代理类名字，`direnv exec` 仍导出 `https_proxy`（项目侧行为不变），同目录 `dsh --profile acp` 以 EOF stdin 启动退出 0，`scripts/dsh-acp-probe.py --command "$(command -v dsh)"` 在项目工作目录内跑通握手并收到 `agent_message_chunk`（`TEXT: PROBE-OK`，`DIRTY_STDOUT_LINES: 0`，退出 0）。以上为方法可复现的结论，具体版本与命令输出以目标机当前状态为准。

2026-09-18，目标主机 fedora-thinkbook：按上一节流程把 `bridge` 切到 `"enhanced"` 并在 `0.1.6-alpha.2` 上复测。切换本身干净：provision 把 bundle 栈换成 `[dsh-base, opencode-session, dsh-acp-enhanced]` 并写入 `- id: acp-enhanced` patch。`scripts/dsh-acp-probe.py` 结果：控件面齐全（`MODES` 三档 `read-only`/`workspace-write`/`danger-full-access`，`permission_preset` category=mode、`agent_preset` category=model_config、`plan_mode` category=plan，`loadSession: true`，图片 prompt 为真），但 `TEXT_LEN: 0`、`UPDATE_KINDS` 无 `agent_message_chunk`，探针 exit 1。A/B 对照（同 route `ten-rings`/`gpt-5.6-terra`、同 harness、同探针）：官方桥 `TEXT_LEN: 8` 且收到 `agent_message_chunk`，exit 0。`ACP_DEBUG=1` 事件流显示 `assistant/message` 到达而 `assistant/chunk` 一条未发（详见「桥接选型」一节的根因）。已回滚 `bridge = "official"` 并重新 switch，回滚后 bundle 栈恢复 `[dsh-base, opencode-session, dsh-acp-app]`，探针再次 exit 0。

2026-09-18（同日续），目标主机 fedora-thinkbook：把上游零文本缺陷修好后重新启用增强桥。诊断在隔离 `$DSH_HOME` 下复现（fork 检出 + 手动 profile：`fetchgit` 的源码目录直接挂成 `node_modules/dsh-acp-enhanced`），修复提交为 `longredzhong/dsh-acp-enhanced@97d175a`（0.8.0）。`pkgs/dsh-acp-enhanced` 随之从 npm tarball 改为 `fetchgit` 固定该 rev，构建产物为 `dsh-acp-enhanced-0.8.0` 且含 `emitMessageFallback`。`home-manager switch` 后：profile bundle 栈 = `[dsh-base, opencode-session, dsh-acp-enhanced]`，home 内副本版本 0.8.0。验证：`scripts/dsh-acp-probe.py` 报告 `MODES` 三档、五个 config option（model / reasoning_effort / permission_preset / agent_preset / plan_mode）、`CHUNK: PROBE-OK`、`TEXT_LEN: 8`、`DIRTY_STDOUT_LINES: 0`、exit 0；`scripts/acp-client.mjs` 对该 profile 全套 PASS。回归对照：修复前的 fork HEAD 在同一隔离环境下稳定复现 `TEXT_LEN: 0`。已知无关失败：`scripts/acp-smoke-keyless.mjs` 与 `scripts/acp-resume-test.mjs` 在本机 dsh 宿主上失败，已用 `git stash` 验证其在修复前后同样失败——前者是 `dsh plugin add` 新建 profile 缺少 `subagent-model-selection-settings` 行（本文档前述已知问题），后者 FATAL 出现在 `session/list` / `session/delete` 阶段。
