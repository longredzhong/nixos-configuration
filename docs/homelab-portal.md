# Home Lab Portal

[返回项目文档索引](README.md) · [返回项目 README](../README.md) · [返回修改约定](../AGENTS.md)

本页说明家庭实验室门户（Home Lab Portal）的部署方式、数据来源，以及「部署在本机并通过
Tailscale Service 暴露」和「部署在 Cloudflare Pages」两种方案的取舍。

## 目标与范围

门户回答三个问题：

1. 这台机器上部署了哪些服务。
2. 每个服务怎么访问，边界在哪里。
3. 机器和服务的当前状态如何。

门户是**只读**的：它没有、也不应该有任何可以修改 systemd 单元或服务状态的接口。所有变更仍然
通过仓库里的 Nix 模块和 Home Manager 切换完成。

## 架构

```text
浏览器（tailnet 内设备）
        │  https://portal.<tailnet>.ts.net
        ▼
tailscaled（终止 TLS，按 Tailscale Service 转发）
        │  http://<tailnet-ip>:<portal-port>
        ▼
homelab-portal（Python 标准库 HTTP 服务，用户级 systemd 单元）
        ├── config/homelab/inventory.json   服务清单（唯一来源）
        ├── systemctl --user show …          单元状态
        ├── HTTP/TCP 健康探针                接口可达性
        ├── tailscale status / serve status  身份与访问边界
        └── OpenObserve 查询 API             跨机器机群指标（可选，可降级）
```

选择 Python 标准库加无构建前端，是为了让整个站点由 Nix 直接构建：没有 JavaScript 工具链、
没有 `node_modules`、没有独立的构建步骤，也没有第三方 CDN 依赖。这一点在家庭实验室里很重要，
因为服务不应该依赖公网才能渲染。

## 数据来源与判定规则

| 视图 | 来源 | 失败时的表现 |
| --- | --- | --- |
| 服务器状态 | `/proc/loadavg`、`/proc/meminfo`、`/proc/uptime`、`shutil.disk_usage` | 字段留空，不影响服务视图 |
| 单元状态 | `systemctl --user show <unit>` | 标记为「未知」 |
| 服务可达性 | HTTP 或 TCP 探针，短超时 | 标记为「部分可用」 |
| 访问边界 | `tailscale status --json`、`tailscale serve status --json` | 入口标注为未配置 |
| tailnet DNS | 对 `<service>.<tailnet>.ts.net` 做名称解析 | 标注为未解析，提示管理端可能未定义或未审批 |
| 机群视图 | OpenObserve 指标流查询 | 该面板显示不可用原因，本机视图不受影响 |

单个服务的状态由三者共同决定：

- 主单元全部未运行 → **不可用**。
- 部分单元未运行，或单元在运行但探针失败，或单元正常但本机未 advertise 对应 Tailscale
  Service → **部分可用**。
- 全部通过 → **正常**。

这个区分是有意的：`active` 只说明进程在运行，不代表接口可用。例如 Anytype 单元处于
`active`，但没有存储的账号密钥时它会跳过自动登录，API 端口不监听，探针会判定为不可用。

HTTP 探针把 `401`/`403` 视为可达：对 `deepseek-harness` 和 `dufs` 这类要求认证的服务，
返回未授权恰恰证明服务在工作。每个服务的期望状态码写在清单里，不靠隐含约定。

## 部署方案分析

### 关键约束

**Cloudflare Pages 是静态与边缘托管，无法访问 tailnet 地址。** Tailscale 地址位于
`100.64.0.0/10`，只有在 tailnet 内的设备才能路由到。托管在 Cloudflare 边缘的页面既不在这
个网络里，也没有到该网络的隧道，因此**无法**读取本机 systemd 状态、执行健康探针，或直接查询
只绑定 tailnet 地址的 OpenObserve。

这不只是配置问题，而是拓扑问题。要让 Pages 显示实时状态，必须额外引入一个回源通道
（例如已有的 Cloudflare Tunnel 加一个 Worker），并把回源凭据放到 Cloudflare 侧，等于把
家庭实验室的信任边界向外扩展了一层。

### 对比

| 评估项 | NUC + Tailscale Service | Cloudflare Pages（静态托管） |
| --- | --- | --- |
| 读取实时状态 | 可以。后端与服务同机，直接读 systemd 与本机探针 | 不能。边缘节点无法路由 tailnet 地址 |
| 访问边界 | tailnet ACL 与设备审批；服务只绑定 tailnet 地址 | 默认公网可达，需要自建身份层 |
| 所需组件 | 一个 Home Manager 模块 | 静态前端之外还需 Worker 与 Tunnel 回源 |
| 跨机器状态 | 同网段，可直接查询 OpenObserve 机群指标 | 需先穿过 Tunnel 才能到达观测后端 |
| 凭据处理 | 复用 agenix 与本机运行时文件，凭据不离开本机 | 回源凭据位于 Cloudflare 侧，信任范围扩大 |
| 离线可用性 | tailnet 内可用，不依赖公网 | 依赖 Cloudflare 边缘网络与公网 |
| 变更与审计 | 随仓库模块走 `just apply` / `hm-switch` | 独立流水线，需要单独的 CI 或手动 deploy |
| 结论 | **状态门户与内部引导页的主方案** | 仅适合纯静态的对外引导页 |

### 结论

把门户部署在本机并通过 Tailscale Service 暴露。理由按重要性排序：

1. **只有本机方案能拿到实时状态。** 这是需求本身决定的，不是偏好问题。
2. **它与现有服务同构。** OpenObserve、AFFiNE、Garage UI 都用同样的「绑定 tailnet 地址 +
   Tailscale Service」模式，没有引入新的部署范式。
3. **凭据不离开家庭实验室。** 门户读取的 OpenObserve 凭据是本机运行时文件；放到
   Cloudflare 侧就多了一份需要轮换和审计的副本。
4. **变更与审计链路统一。** 门户随仓库模块走 `just check-fast` 加切换，和其余服务同一套流程。

Cloudflare Pages 的适用场景：需要给**不在 tailnet 里的人**看的、**不含实时状态**的静态引导
页或公开镜像。此时它是有价值的；用它承载需要 tailnet 的状态面板则会失败。

> 公网入口与 tailnet 入口是两条独立的边界。仓库里已有的 Cloudflare Tunnel 只暴露了明确需要
> 公网可达的单个服务；门户不在这条链路上。

## 配置与部署

### 文件

| 文件 | 作用 |
| --- | --- |
| `config/homelab/inventory.json` | 服务清单：分类、说明、单元、端口、入口、探针、文档链接 |
| `config/homelab/portal/server.py` | 只读后端（Python 标准库） |
| `config/homelab/portal/` 其余文件 | 无构建前端：`index.html`、`styles.css`、`app.js`、`markdown.js` |
| `modules/host-services/homelab-portal.nix` | 用户级 systemd 单元与选项 |
| `config/tailscale/nuc-services.hujson` | `svc:portal` 端点声明 |

### 关键选项

`hostServices.homelabPortal`：

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `enable` | `false` | 是否启用门户 |
| `bindHost` | `<tailnet-ip>` | 只能从 tailnet 访问；默认不监听局域网或公网 |
| `port` | `8090` | HTTP 端口 |
| `statusCacheSeconds` | `5` | 状态快照复用时长，避免探针被高频请求放大 |
| `openobserveBase` | `http://<tailnet-ip>:5080` | 设为 `null` 可完全关闭机群面板 |
| `openobserveEnvFile` | `<data-root>/openobserve/openobserve.env` | 运行时读取查询凭据；不进入仓库 |
| `openobserveWindowSeconds` | `900` | 跨机器查询的回看窗口 |

门户把服务脚本、静态资源、文档和清单都写成 store 路径。因此**只改内容也会改变单元**，
Home Manager 的 sd-switch 会重启它——这与 `openobserve-agent`、`garage`、`cloudflared`
的处理方式一致。

### 部署步骤

```bash
git diff --check
just check-fast
just eval-home '<user>@<host>'
just hm-dry-run '<user>@<host>'
just hm-switch '<user>@<host>'
```

`svc:portal` 只是本机的端点声明。**服务的可用范围仍由 Tailscale 管理端定义**：如果该服务名
没有在管理端定义并审批，本机 `tailscale serve advertise` 会失败。`tailscale-services`
单元会为每个服务单独报告这一失败并保持 active，不会因为一个未审批的服务让其余服务停止
advertise，也不会进入每五分钟重新清空并重配所有服务的重启循环。门户会把这种情况显示为
「部分可用」。

## 访问与验证

### 访问

- Tailscale Service：`https://portal.<tailnet>.ts.net`（TLS 由 tailscaled 终止）
- tailnet 直连：`http://<tailnet-ip>:8090`

两种方式都只在 tailnet 内可用。

### 验证

```bash
# 单元与监听
systemctl --user --no-pager status homelab-portal
ss -tlnp | grep 8090

# 健康接口与数据接口
curl -fsS http://<tailnet-ip>:8090/api/health
curl -fsS http://<tailnet-ip>:8090/api/status | head -c 400
```

静态检查、单元切换和实际业务验证是三件不同的事，报告时要分开说明：`just check-fast` 通过
只证明它**可以**构建，只有健康接口返回和页面能读到状态才证明它**已经**工作。

验证清单：

1. `systemctl --user status homelab-portal` 为 `active (running)`，且没有重启计数增长。
2. `/api/health` 返回 `{"ok": true, ...}`。
3. `/api/status` 中 `counts` 与 `systemctl --user list-units` 的实际情况一致。
4. 故意停一个非关键单元，确认页面把它标成「不可用」，恢复后回到「正常」。
5. 断开机群视图（例如把 `openobserveBase` 设为 `null` 或停掉 OpenObserve），确认只有机群面板
   降级，本机服务器与服务视图不受影响。

## 安全边界

- **网络**：默认只绑定 tailnet 地址。局域网邻居和公网都无法连接；没有公网入口。
- **授权**：谁能访问由 tailnet ACL 决定，不由门户决定。门户不实现自己的身份层，也不提供
  写操作，因此不需要额外的授权逻辑。
- **凭据**：机群查询使用本机生成的 OpenObserve 运行时凭据，运行时读取，不写入仓库、不写日志、
  不出现在任何响应里。采集端用的摄取 token 只能写入，无法用于查询，因此不能复用。
- **文档渲染**：内置 Markdown 阅读器只服务 `docs/*.md`，文件名经过白名单正则校验，且所有
  文本在生成标记前先做 HTML 转义，链接目标限制为安全协议。
- **静态资源**：HTTP 处理器只服务固定的资源白名单，服务脚本本身不在静态目录中。

> 机密、明文口令、token、带 token 的 URL、内网地址和 tailnet 域名都不应写入本文件或任何文档。
> 需要现场证据时，把它们放在变更记录里，并注明日期、目标和命令结果。

## 已知限制

- **同机探针**：门户只能探测自己所在机器上的单元。其他机器依赖 OpenObserve 的上报数据，
  没有上报不等于机器离线。
- **机群视图的依赖链**：它同时依赖 OpenObserve、Garage 和采集端。任一层故障都会让该面板
  退化；这是设计上的降级，不是门户故障。
- **`tailscale serve status` 只反映本机配置**：它证明本机声明了服务端点，不证明管理端已经审批
  或客户端 ACL 已经放行。门户因此把「本机端点配置」和「tailnet 域名是否解析」分成两行显示：
  域名不解析时，服务本身可能仍然正常，但通过 Tailscale Service 的访问路径还不可用，需要在
  管理端创建并审批该 Service。
- **状态是采样**：`statusCacheSeconds` 内的请求返回同一份快照，页面展示的是最近一次采集结果，
  不是瞬时值。
- **门户不持久化历史**：需要趋势和留存数据时，用 OpenObserve 的看板，而不是门户。

## 权威源码与上游参考

| 主题 | 位置 |
| --- | --- |
| 门户单元与选项 | `modules/host-services/homelab-portal.nix` |
| 服务清单 | `config/homelab/inventory.json` |
| 后端与前端 | `config/homelab/portal/` |
| Tailscale Service 端点 | `config/tailscale/nuc-services.hujson`、`modules/host-services/tailscale-services.nix` |
| 观测数据来源 | `modules/host-services/openobserve.nix`、`modules/host-services/openobserve-agent.nix` |

上游参考：

- Tailscale Services：<https://tailscale.com/kb/1552/tailscale-services>
- `tailscale serve`：<https://tailscale.com/kb/1242/tailscale-serve>
- Cloudflare Pages：<https://developers.cloudflare.com/pages/>
- Cloudflare Tunnel：<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/>
- OpenObserve 查询 API：<https://openobserve.ai/docs/api/search/>
