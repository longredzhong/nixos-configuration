# Agent 记忆服务（方案）

[返回文档索引](README.md) · [返回项目 README](../README.md)

> **状态：方案，尚未实施。** 本页描述目标架构、社区方案评估与落地路径，不对应任何已部署的单元。
> 文中的地址、端口、镜像标签、命令和配置一律是**示例**，实际值以目标配置和运行时状态为准。

本页要解决的问题：让**所有 harness 平台**（DSH、opencode、Memoh 内的 agent，以及将来的 Claude Code / Codex 等）在**多个项目、多台机器、多种环境**下共用同一份长期记忆，重点是"尝试新事物"过程中的沉淀——试过什么、结论是什么、哪条结论已经被推翻。

## 目标与约束

### 目标

| 维度 | 要求 |
| --- | --- |
| 覆盖面 | 任何 harness 都能读写同一份记忆，不绑定某一个产品 |
| 作用域 | 跨项目（全局）+ 单项目 + 实验记录，且允许一条查询跨越它们 |
| 位置无关 | 机器、环境、在线/离线开发机都能访问同一份记忆 |
| 可审计 | 语料是人类可读、可 diff、可 git 备份的，不锁死在某个产品的数据库里 |
| 失败软化 | 记忆是增强能力，服务不可用时 harness 必须照常工作 |

### 硬约束

| 约束 | 来源与影响 |
| --- | --- |
| **DSH 的 MCP 客户端只支持 `stdio` 与 `streamable-http`**，不支持 SSE | `@deepseek-ai/dsh-mcp-client` 的类型定义只有 `StdioConfig` / `StreamableHttpConfig`。**因此跨机器共享的服务端必须讲 Streamable HTTP**，这一条直接淘汰若干流行方案 |
| DSH 全局指令只有一个文件，且与项目链**共享 64 KiB 预算** | `$DSH_HOME/AGENTS.md` 在第一个请求中作为持久化 baseline 注入，位置在项目指令链之前、优先级最低；超预算时先整体丢弃较宽泛的文件。→ **常驻层必须极小**，详见 [DSH ACP 文档](deepseek-harness-acp.md) |
| 仓库是公开仓库 | 记忆语料**绝不能**进入本仓库；只提交 `secrets/*.age` 密文，明文永不落盘到仓库、Nix store 或终端输出，判据见 [Agenix 机密](../secrets/README.md) |
| Memoh 的原生记忆**按 bot 隔离且命名空间写死** | `memory_nodes` / `memory_edges` 以 `bot_id` 为主键，HTTP 层只接受 `namespace="bot"`（其他值返回 400）。→ Memoh **不能**充当全平台记忆库，应当反过来通过 MCP 消费本方案的服务 |
| Memoh 的 Mem0 / OpenViking 提供方是**空实现** | 界面仍列出这两个选项，但适配器每个方法都返回 `provider is disabled`。不要选它们 |

### 复用既有能力（不新造）

- 机密：agenix。加密用 `age -e -R`（ssh-ed25519 recipients），判据见 [secrets/README.md](../secrets/README.md)。
- 暴露：Tailscale 与 `tailscale serve`，模式见 [Tailscale Services](tailscale-services.md)。
- 观测：`modules/host-services/openobserve-agent.nix` 采集 `${hostname}_journald`；新增 systemd 单元会自动进入该流，无需额外配置。
- 备份目的地：`longred-vm` 上的 Garage 镜像节点，判据见 [longred-vm](longred-vm.md)。

## 架构

### 三层

| 层 | 载体 | 作用域 | 预算 |
| --- | --- | --- | --- |
| **Tier 0 常驻层** | 文件：`$DSH_HOME/AGENTS.md`、项目 `AGENTS.md` / `CLAUDE.md`、各 harness 的规则文件 | 全局偏好与硬约束，外加指向 Tier 1 的**指针** | 极小（DSH 侧与项目链共享 64 KiB） |
| **Tier 1 检索层** | 自部署服务，MCP over Streamable HTTP | 全局 + 项目 + 实验，按标签分区，可跨区检索 | 无上限 |
| **Tier 2 语料层** | 私有 git 仓库中的 Markdown | 真相源；服务端索引是可重建的**派生物** | 无上限 |

要点：**Tier 0 与 Tier 1 是一份语料的两个视图，不是两套系统。** Tier 0 只放"必须每轮生效"的内容，其余全部沉到 Tier 1，这是 64 KiB 预算不被撑爆的唯一办法。

### 命名空间

| 命名空间 | 用途 | 例（示例） |
| --- | --- | --- |
| `global` | 跨项目偏好与约定 | 语言偏好、工具链习惯、机密处理纪律 |
| `project:<slug>` | 单项目知识 | 决策、坑、架构说明，`<slug>` 取仓库名 |
| `experiment:<id>` | 一次尝试的完整记录 | 见下方写入协议 |

采用**软命名空间**（标签/目录）而非强租户隔离：目标是同一个人跨项目检索，"全局层"需要能被任何项目查到；强隔离会迫使把全局事实在每个分区各复制一份。

### 写入协议（写进 Tier 0 文件，约束每个 agent）

1. **何时写**：做过非显然的排查、得到可复用结论、**推翻旧结论**、踩到坑。
2. **写什么**：`hypothesis` / `tried` / `result` / `conclusion` / `status`，其中 `status ∈ {open, confirmed, superseded, dead-end}`。
3. **推翻时不删除**：把旧条目标记为 `superseded` 并指向新条目，保留"当时为什么那么认为"。
4. **何时提升**：只有"稳定且必须每轮生效"的内容才提升进 Tier 0 文件，且走正常 commit 审查。

### 失败软化

记忆服务必须**不在关键路径上**：

- 客户端配置为启动失败不影响 harness（DSH 侧即 `failOnStartupError: false`）。
- 设置合理的调用超时，避免服务卡住时拖慢每一轮对话。
- Tier 0 文件始终存在，因此服务全挂时 harness 仍具备基本全局指令。

## 各 harness 的接入面

| Harness | 接入位置 | 关键字段 | 备注 |
| --- | --- | --- | --- |
| DSH | `cordis.patch.yml` 增加一条 `@deepseek-ai/dsh-mcp-client` 行 | `transport: streamable-http`、`url`、`headers.Authorization`、`serverName`、`failOnStartupError: false`、`toolCallTimeoutMs` | 工具以 `mcp__<serverName>__<tool>` 暴露；`headers` 支持从环境变量取值 |
| opencode | `~/.config/opencode/opencode.jsonc` 的 MCP 段 | 由现有生成脚本插入 | 见 `modules/host-services/opencode.nix` |
| Memoh | 每个 bot 的 MCP 连接 | `type: http` | `mcp_connections` 按 bot 存储；Memoh 原生记忆继续独立存在，两者互不替代 |
| Claude Code / Codex | 各自 MCP 配置 | `--transport http` | 均支持 Streamable HTTP |

DSH 侧的形态（示例，取自 `dsh-mcp-client` 的配置契约）：

```yaml
- id: mcp-agent-memory
  name: '@deepseek-ai/dsh-mcp-client'
  config:
    serverName: memory
    transport: streamable-http
    url: https://<memory-host>/mcp
    headers:
      Authorization: !!js '`Bearer ${process.env.AGENT_MEMORY_TOKEN}`'
    failOnStartupError: false
```

## 社区方案评估

### 已淘汰

| 方案 | 淘汰理由 |
| --- | --- |
| `@modelcontextprotocol/server-memory`（官方参考实现） | 源码只有 `StdioServerTransport`，单 JSONL 文件，无认证、无命名空间 → 无法满足多机 HTTP 共享。本轮核查的候选里只有它被 nixpkgs 收录（`mcp-server-memory`），但**收录不等于可用**：实测该打包版本启动即失败，闭包里缺少 `zod`（`ERR_MODULE_NOT_FOUND`，NUC / Fedora 44，2026-09-18）。即便修复打包，也仍需额外的 stdio→HTTP 桥 |
| Mem0 | **自托管没有 MCP**（`mem0-mcp` 已归档，官方 MCP 改为纯云、前置条件为平台账号）；且 OSS 新算法是 ADD-only，**不失效旧事实**，与"记录被推翻的结论"直接相悖 |
| Zep | Community Edition 已废弃，仓库本身降级为示例与集成集合；自托管只能落到 Graphiti |
| Redis Agent Memory Server | 开源 `V0/` 已停止维护，官方导向托管服务；MCP 侧只有 SSE（不满足 DSH 的传输限制），且强制 Redis Stack + 嵌入 + LLM 三重依赖 |

> **这条赛道淘汰率很高**：上面四条里有两条是"项目已废弃或转型"。这正是下面"语料与引擎解耦"的理由——不要把知识只存在某个产品的数据库里。

### 可用候选

| 候选 | 远程 MCP | 认证 | 多项目 | 存储与备份 | 写入是否需要 LLM | 时效语义 |
| --- | --- | --- | --- | --- | --- | --- |
| Basic Memory | stdio / streamable-http / sse | **HTTP 无授权**，需自行前置 | 项目=目录，可锁死单项目 | Markdown + 可重建索引 | 否 | 无 |
| mcp-memory-service | `POST /mcp` | Bearer API key，可选 OAuth2 | 仅标签约定 | 二进制单文件库 | 否（本地 ONNX 嵌入） | 无 |
| Hindsight | `/mcp/{bank_id}/` | 默认开放，可加租户扩展 | bank 严格隔离 | Postgres + pgvector，官方备份/导出工具 | **是** | 细化而非覆盖，原文保留 |
| Graphiti | HTTP（官方自称 experimental） | 文档无认证项 | `group_id` 分区 | 图数据库；无官方导出工具 | **是**（且必须支持 structured output） | bi-temporal 有效期 + 自动失效 |

### 元判断：语料与引擎解耦

上表的选择会随时间变化，所以架构上把**语料**（Markdown + 私有 git）与**引擎**（检索服务）分开：

- 换引擎不丢数据：索引永远是派生物，可从语料重建。
- 备份即 git；审计即 diff。
- 引擎即便选 DB-only（如 Hindsight），也必须补一个定期 export → Markdown + git 的任务。

### 选型决策规则

- 要 Markdown/git 当真相源、项目=目录 → **Basic Memory**，代价是自己加认证、关闭自动更新、以及 AGPL 的注意义务。
- 要零外部 API key、内置 Bearer、最少运维 → **mcp-memory-service**，代价是存储不可读、项目隔离只有标签、且远程面近期才修完一串安全公告，版本要跟紧。
- 要写入侧自动"细化而非覆盖"且有官方备份工具 → **Hindsight**，代价是写入路径必须经过 LLM，且严格 bank 隔离与"全局层"目标冲突。
- 只在确实需要审计"某时点的真值" → **Graphiti**。
- 都不愿背第三方生命周期 → 自己写一个小的 MCP 服务，落在同一份 Markdown 语料上（DSH 是 Node 生态，Nix 打包顺手，并可顺带暴露 REST 给非 MCP 的机器）。

**倾向**：Tier 0 与引擎选型无关，应先行落地；Tier 1 建议在 Basic Memory 与 mcp-memory-service 之间做一次实测 spike 再定，不建议一上来就选 Hindsight。

## 部署方案（未实施）

以下全部是**待实施的设计**，不是现状。

### 位置

放在 `longred-vm`：SSD、内存充足、已在 tailnet、已承载 Garage 备份节点。

**不要**放在 NUC：该机是机械盘且 iowait 偏高，记忆服务是随机读写型负载。

### 形态

沿用仓库既有惯例——**rootless podman + systemd**，参考 [`modules/host-services/affine.nix`](../modules/host-services/affine.nix) 的 `commonFlags` 模式（`--rm --replace --security-opt label=disable --http-proxy=false --network <net>`，`ExecStartPre` 里 `podman network create`）。注意 `hosts/longred-vm/memoh.nix` 是仓库中**唯一**使用 rootful Docker 的服务，新服务不应加入该例外。

镜像按 digest 固定，不使用浮动标签；`--pull missing` 只用于首次拉取。

### 暴露与认证

两种可选路径，均为 tailnet-only，**不经过公网隧道**（与 ntfy 有意不同：记忆含内部知识）：

1. 绑回环 + `tailscale serve`：拿到合法主机名与 TLS，模式同 `hosts/longred-vm/ntfy.nix`。
2. 直接绑定 tailnet 地址：模式同 `affine.nix` 的 `listenAddress`，省一层进程，但没有 TLS 证书。

无论哪种，都再加一层 bearer token（走 agenix），理由是 Tailscale 只回答"设备是否可信"，不回答"哪个客户端可以读全部记忆"，且 token 可单独轮换。

### 持久化与备份

- 主备份：Tier 2 的私有 git 仓库（推送远端 + 可再镜像到 Garage）。
- 次备份：引擎原生导出（若有）或 `pg_dump`，落 Garage。
- **必须做恢复演练**：只有导出命令跑通过不算验证，要真的从备份恢复到一台干净实例并检索到已知条目。

### 可观测性

新 systemd 单元自动进 journald，现有 agent 会把它采进 `${hostname}_journald`。至少覆盖：服务存活、写入失败、检索延迟。

### 机密

- bearer token 以 `secrets/<name>.age` 提交密文，用 `age -e -R`（ssh-ed25519 recipients）。
- 运行时经 `config.age.secrets.<name>.path` 读取，禁止写入 Nix 表达式或 Nix store。
- **不要运行会回显凭据的子命令**（例如某些工具的 `token list` 会明文打印 token）。

## 分阶段落地

| 阶段 | 内容 | 依赖 |
| --- | --- | --- |
| **Phase 0** | Tier 0 常驻层与写入协议：私有语料仓库 + `$DSH_HOME/AGENTS.md` 等全局文件 + 各项目 `AGENTS.md` 指针 | 无新服务，立即可用 |
| **Phase 1** | Tier 1 检索层：按选型规则挑一个候选，走一次真实 spike（见下） | 一个容器 + 一条 tailnet 暴露 + 一个 token |
| **Phase 2** | 仅在有明确需求时：Graphiti 式"某时点真值"审计；或把语料聚合进观测看板 | 视需求 |

## 验证方法

静态检查、远端部署与实际业务验证必须**分别报告**，健康接口可达不能代替业务验证。

1. **静态检查**：`git diff --check`、`just check-fast`。
2. **部署检查**：单元处于 active、监听地址正确、日志无错误。
3. **业务验证**（唯一能证明"记忆真的生效"的一段）：
   - 从**至少两个不同的 harness** 各做一次真实往返：写入一条带唯一标记的记忆 → 在另一个 harness 里检索到它。
   - 反向验证隔离与共享：`global` 条目应能被两个不同项目检索到；`project:<slug>` 条目不应被无关项目的默认查询命中。
   - 记录检索延迟与召回质量，作为选型依据。
4. **失败软化验证**：停掉服务，确认两个 harness 仍能正常启动与对话。

## 未决问题与未确认项

- **四个可用候选均未做运行时验证。** 本轮对它们只做了一手来源核查（官方 README / docs / 源码 / compose）与本地 nixpkgs 打包核查，没有启动过任何一个、没有打过一次真实请求。选型表因此是"文档事实"，不是"实测事实"。
- 唯一被实际启动过的是已淘汰的官方 `@modelcontextprotocol/server-memory`：nixpkgs 打包版本启动即因缺少 `zod` 失败（见上表），未取得任何协议响应。
- 在开发机（NUC）上观察到：`nix run` 会去重新下载一个**本地已存在**的 store 路径，并长时间阻塞（两次，各 ≥15 分钟）。原因**未确认**——不排除是该环境的 store 视图或缓存隔离所致，未必是本机常态。因此候选的实测 spike 建议放在 `longred-vm` 上做。
- 未确认：Basic Memory 语义搜索的默认开关状态；各候选在中英混语料下的召回质量；Hindsight 是否支持 stdio 传输。
- DSH 的 `failOnStartupError` 默认值未确认，落地时应显式设置。
- Tier 0 的落地细节**已实现**：源文件是 `config/deepseek-harness/user-instructions.md`（不能叫 `AGENTS.md`，否则会被当成该目录的项目级指令），由 `modules/host-services/deepseek-harness-acp.nix` 通过 `home.file` 链接为 `$DSH_HOME/AGENTS.md`；见 [DSH ACP 文档](deepseek-harness-acp.md) 的"全局记忆"一节。
- 多环境下的凭据分发方式（离线开发机、WSL 目标）尚未设计。

## 权威源码与上游参考

- 权威来源：`modules/host-services/`（用户级服务模式）、`hosts/longred-vm/*.nix`（系统级服务与暴露模式）、`secrets/README.md`（机密判据）
- 接入面：DSH 侧以**本地安装的** `@deepseek-ai/dsh-mcp-client` 类型定义与 README 为准（`transport`、`serverName`、`url`、`headers`、`failOnStartupError`、`toolCallTimeoutMs`、`reconnect`）；[Memoh 配置模板](https://github.com/felinics/Memoh/blob/main/conf/app.docker.toml)
- 候选方案：[Basic Memory](https://github.com/basicmachines-co/basic-memory)、[mcp-memory-service](https://github.com/doobidoo/mcp-memory-service)、[Hindsight](https://github.com/vectorize-io/hindsight)、[Graphiti](https://github.com/getzep/graphiti)
- 已淘汰方案的判据：[官方 memory server](https://github.com/modelcontextprotocol/servers/tree/main/src/memory)、[Mem0 官方 MCP](https://docs.mem0.ai/platform/mem0-mcp)、[Redis Agent Memory Server](https://github.com/redis/agent-memory-server)
- 第三方横向对比（需交叉验证，非权威）：[memory-server-comparison](https://github.com/provos/ironcurtain/blob/HEAD/docs/designs/memory-server-comparison.md)
- 桥接工具：[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy)（stdio ↔ SSE/StreamableHTTP，**自身不做认证**）
