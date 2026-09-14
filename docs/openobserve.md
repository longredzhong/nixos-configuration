# OpenObserve 部署与机器观测

本仓库在 Fedora NUC 上以 Home Manager 的用户级 systemd 服务运行 OpenObserve，容器使用 rootless Podman。当前使用 OpenObserve `v1.0.0`，访问地址是：

- Web UI、HTTP API、OTLP/HTTP：`http://100.100.10.1:5080`
- OTLP/gRPC：`100.100.10.1:5081`
- 健康检查：`http://100.100.10.1:5080/healthz`

`100.100.10.1` 是当前 NUC 的 Tailscale 地址。服务只监听这个地址，不应直接暴露到公网。

## 存储方式

这是单节点部署，配置含义如下：

| 数据 | 位置 | 作用 |
| --- | --- | --- |
| SQLite 元数据、WAL、查询缓存 | `/data/openobserve/data` | 单节点运行状态和本地临时数据 |
| 日志、指标、Trace 的 Parquet 文件 | Garage 的 `openobserve` bucket，前缀 `openobserve/` | OpenObserve 的对象存储数据 |

OpenObserve 使用 `ZO_LOCAL_MODE=true` 和 `ZO_LOCAL_MODE_STORAGE=s3`。Garage 通过 `http://127.0.0.1:3900` 提供 S3 API，区域名是 `garage`。配置使用 path-style S3 请求（`ZO_S3_FEATURE_FORCE_HOSTED_STYLE=false`），这是 loopback endpoint 能稳定工作的关键。

NUC 配置将 `ZO_MAX_FILE_RETENTION_TIME` 设为 60 秒、`ZO_FILE_PUSH_INTERVAL` 设为 10 秒，让低流量 stream 的 WAL 也能较快写入 Garage。这两个值控制 WAL 推送时机，不是日志保留期限；各 stream 的实际保留策略仍应在 UI 中单独设置。

首次启动 `openobserve.service` 时会：

1. 等待 Garage 健康；
2. 创建 `openobserve` bucket；
3. 创建名为 `openobserve` 的 Garage key，并授予它读写权限；
4. 生成 OpenObserve root 用户密码和 S3 配置，保存到 `/data/openobserve/openobserve.env`。

这个 env 文件只在第一次启动时生成，权限为 `0600`，不要提交到 Git，也不要把它复制到 Nix 表达式或日志中。Garage 当前版本支持从 `key info --show-secret` 重新读取已创建 key 的 secret，因此首次启动中途失败后可以重试；如果实际 Garage 版本不能重新显示 secret，需要删除并重新创建该 key。

Garage 本身目前是单节点、`replication_factor = 1`，并且和 OpenObserve 使用同一块 `/data` 磁盘。这解决了对象存储接口和容量管理问题，但不等于异机备份；需要另外备份 Garage 数据以及 OpenObserve 的 SQLite 数据。

## 部署前检查

在 NUC 上确认 `/data` 已挂载，并且 `longred` 对它有写权限：

```bash
findmnt /data
test -w /data
systemctl --user is-active garage
```

Garage 第一次使用前必须完成单节点 layout。如果 Garage 已经能正常存取 bucket，就不要重复执行 layout 命令。首次初始化时，先查看节点 ID：

```bash
garage status
```

然后按实际可用空间设置容量并应用 layout；下面的 `NODE_ID` 和容量只是示例：

```bash
garage layout assign -z nuc -c 1.5T NODE_ID
garage layout apply --version 1
```

如果 NUC 上的 `garage` CLI 没有默认读取 `~/.config/garage/garage.toml`，从 `systemctl --user cat garage` 中复制服务使用的 `--config`、`--rpc-secret-file` 参数后再执行上述命令。不要在命令行或文档中记录 RPC secret。

## 应用配置并启动

在配置仓库目录执行：

```bash
just hm-dry-run 'longred@nuc'
just hm-switch 'longred@nuc'
systemctl --user restart garage
systemctl --user restart openobserve
```

检查服务和健康状态：

```bash
systemctl --user --no-pager status garage openobserve
journalctl --user -u openobserve -n 100 --no-pager
curl --fail http://100.100.10.1:5080/healthz
```

期望健康检查返回：

```json
{"status":"ok"}
```

如果首次启动失败，先看 `journalctl --user -u openobserve`。常见原因是 Garage 尚未完成 layout、`/data` 不可写、端口已经被占用，或旧的 `openobserve.env` 不完整。修复原因后重启服务即可。

## 全部机器与服务追踪

OpenObserve 的 Kubernetes 推荐页同时说明了三类数据：容器日志、Kubernetes 事件和集群指标，以及工作负载 Trace。当前管理的机器没有统一的 Kubernetes 集群，仓库因此采用 OpenObserve Linux 推荐页的等价方案：通过 Home Manager 在 `nuc`、`fedora-thinkbook`、`metacube-wsl` 和 `thinkbook-wsl` 部署用户级 OpenTelemetry Collector，把每台机器的 journal、主机指标和本机 OTLP Trace 入口送回 NUC 上的 OpenObserve。

采集器由 `openobserve-agent.service` 管理，配置文件是 `~/.config/opentelemetry-collector/config.yaml`，认证令牌由 Agenix 解密到运行时路径，不会写进 Nix store。每台机器按自己的 hostname 使用日志和 Trace stream；指标 stream 按 metric family 共用，并通过 `host.name` 区分机器。当前数据分类如下：

| Stream | 内容 | 来源 |
| --- | --- | --- |
| `<hostname>_journald` | 该机器的 journald 日志 | NUC 上的 `garage`、`openobserve`、`garage-ui`、`dufs`、`cloudflared`、`opencode`、`anytype`、`affine` 及其依赖服务；其他机器的系统和用户服务 |
| `system_*` | CPU、磁盘、文件系统、负载、内存、网络、分页和进程数指标；OpenObserve 按 metric family 建立多个 `system_*` stream | 全部机器，30 秒采集一次；按 `host.name` 区分 |
| `<hostname>_traces` | OpenTelemetry spans | 各机器本机 `127.0.0.1:4317`（gRPC）或 `127.0.0.1:4318`（HTTP/protobuf） |

NUC、Fedora ThinkBook 和 standalone Home Manager 目标中的采集器都以 `longred` 的用户级 systemd 单元运行；两个 NixOS WSL 目标同时把 `longred` 加入 `systemd-journal` 组，以便读取系统 journal。NUC 上的 agent 依赖本机 `openobserve.service`，其他机器通过 Tailscale 地址发送到 NUC，不依赖本机运行 OpenObserve。采集器的写入令牌只授予写入权限，不使用 root 密码。

配置仓库变更后，按目标类型应用：

```bash
# Fedora / NUC / standalone Home Manager
just hm-dry-run 'longred@fedora-thinkbook'
just hm-switch 'longred@fedora-thinkbook'
just hm-dry-run 'longred@nuc'
just hm-switch 'longred@nuc'

# NixOS WSL
sudo nixos-rebuild switch --flake .#metacube-wsl
sudo nixos-rebuild switch --flake .#thinkbook-wsl
```

每台机器都应检查自己的 user service；Collector 的 zpages 调试页只监听本机，可用下面的命令查看状态：

```bash
systemctl --user is-active openobserve-agent
systemctl --user --no-pager status openobserve-agent
journalctl --user -u openobserve-agent -n 100 --no-pager
curl --fail http://127.0.0.1:55679/debug/servicez
```

看板使用 `system_*` metric stream 聚合所有机器，因此不会因为某台机器的日志 stream 尚未创建而缺少机器状态。每台机器第一次启动 agent 后，等待一个 30 秒采集周期和 batch timeout，再在看板中按 `host.name` 检查数据。

### 接入应用 Trace

应用必须使用 OpenTelemetry SDK、框架 instrumentation 或其他支持 OTLP 的 instrumentation 才会产生 span。只设置环境变量不会给没有埋点能力的预编译服务自动生成 Trace；当前 NUC 的 AFFiNE、Garage、DUFS、Anytype、OpenCode、Cloudflared 和 OpenObserve 的现有启动配置因此主要由 `nuc_journald` 和 `system_*` 观测。

在任一已完成 OpenTelemetry instrumentation 的机器上，应用可以把 Trace 发给本机采集器：

```bash
export OTEL_SERVICE_NAME=my-service
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

如果应用在 rootless Podman 容器内运行，容器中的 `127.0.0.1` 指向容器自身，通常应把 endpoint 改为：

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://host.containers.internal:4318
```

SDK 会向 OTLP HTTP endpoint 追加 `/v1/traces`，采集器随后用专用写入令牌和该机器的 `<hostname>_traces` stream 转发到 OpenObserve。应用自身不需要保存 OpenObserve 密码或写入令牌。查询时在 UI 的 Traces 页面选择对应机器的 Trace stream，时间范围先选最近 15 分钟，再按 `service.name` 过滤。

如果应用必须直接写 OpenObserve，使用 IAM 中单独创建的写入令牌，不要使用 root 密码。OTLP/HTTP base endpoint 是 `http://100.100.10.1:5080/api/default`，请求头至少需要 `Authorization: Basic <base64-token>`；日志和 Trace 可以用 `stream-name` 指定目标 stream。OTLP 指标会按 metric family 建立自己的 stream，不能依赖 `stream-name: nuc_system` 合并。Collector、SDK 和 OpenObserve 的 endpoint 都应使用内网/Tailscale 地址，不要把 4317、4318 或 Garage 的 3900 端口暴露到公网。

### 验证日志和指标

切换后先确认采集器没有导出错误：

```bash
systemctl --user --no-pager status openobserve-agent
journalctl --user -u openobserve-agent --since '10 minutes ago' --no-pager
curl --fail http://100.100.10.1:5080/healthz
```

然后在 OpenObserve UI 中分别打开 Logs 和 Metrics：

1. Logs 选择对应机器的 `<hostname>_journald`，时间范围选择最近 15 分钟；
2. Metrics 选择任一 `system_*` stream（例如 `system_cpu_time` 或 `system_memory_usage`），确认每个 `host.name` 有最近时间戳；
3. 展开日志记录，按 `body__systemd_user_unit` 或服务名称筛选，例如 `garage.service` 和 `openobserve.service`；
4. 有应用 instrumentation 后，再到对应机器的 `<hostname>_traces`，确认 span 的 `service.name`、时间线和错误状态。

如果 API 健康但 stream 暂时为空，先等待一个 30 秒指标周期和 Collector 的 batch timeout，再检查 agent 日志。OpenObserve 的写入成功也可能早于 Garage 对象完成 compaction；对象存储验证仍按本文后面的命令执行。

### 令牌轮换

仓库使用 OpenObserve IAM 中名为 `nuc-host-agent` 的专用写入令牌为全部机器写入数据。令牌只以 `secrets/openobserve-agent-token.age` 的加密形式保存，并以各管理机器的用户/主机 SSH 密钥作为 Agenix 接收者；不能把 UI 中显示的 Basic 字符串写入 Nix 表达式、日志或文档。轮换时：

1. 在 OpenObserve 的 IAM → 写入令牌中创建新令牌并停用旧令牌；
2. 用全部目标机器可用的 SSH 公钥重新加密 `secrets/openobserve-agent-token.age`；
3. 按上面的 NixOS/Home Manager 命令逐台切换，然后检查每台机器的 `openobserve-agent.service` 状态和日志；
4. 在每台机器的 `<hostname>_journald`、任一 `system_*` metric stream 和 `<hostname>_traces` 中完成写入验证后，再删除旧令牌。

## 首次登录

浏览器打开 `http://100.100.10.1:5080`。初始 root 用户是：

```text
root@openobserve.local
```

密码只保存在 NUC 的 env 文件中，可在 NUC 本机读取：

```bash
awk -F= '$1 == "ZO_ROOT_USER_PASSWORD" { print $2 }' \
  /data/openobserve/openobserve.env
```

第一次登录后，在 OpenObserve UI 中确认组织 `default`，并按用途创建独立 stream，例如 `nuc_journald`、`nuc_traces`、`application`。root 密码是首次初始化 SQLite 元数据时使用的 bootstrap 值；已经初始化后，不要通过随意修改 env 文件来改密码，应使用 UI 的用户管理流程。

## 发送日志

### JSON API 快速测试

下面的请求会把一条日志写入 `default` 组织的 `nuc_demo` stream：

```bash
OPENOBSERVE_PASSWORD="$(awk -F= '$1 == "ZO_ROOT_USER_PASSWORD" { print $2 }' \
  /data/openobserve/openobserve.env)"

curl --fail-with-body \
  -u "root@openobserve.local:${OPENOBSERVE_PASSWORD}" \
  -H 'Content-Type: application/json' \
  'http://100.100.10.1:5080/api/default/nuc_demo/_json' \
  --data '[
    {
      "level": "info",
      "service": "nuc",
      "message": "OpenObserve smoke test"
    }
  ]'
```

然后在 UI 的 Logs 中选择 `nuc_demo`，把时间范围调到包含当前时间并执行查询。日志通过批量写入和文件推送进入对象存储，上传到 Garage 的时间可能比 API 返回成功稍晚。

### OTLP/HTTP（推荐作为应用和 Collector 的默认入口）

OTLP/HTTP 的 base endpoint 是：

```text
http://100.100.10.1:5080/api/default
```

这个 URL 不要加末尾 `/`；Collector 会自己追加 `/v1/logs`、`/v1/metrics` 或 `/v1/traces`。认证头是 HTTP Basic Auth：

```bash
printf '%s' 'root@openobserve.local:YOUR_PASSWORD' | base64 -w0
```

OpenTelemetry Collector 的关键配置片段：

```yaml
receivers:
  otlp:
    protocols:
      http:
      grpc:

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 400
  batch:
    send_batch_size: 1024
    timeout: 5s

exporters:
  otlp_http/openobserve:
    endpoint: http://100.100.10.1:5080/api/default
    headers:
      Authorization: "Basic ${env:OPENOBSERVE_AUTH}"
      stream-name: otel_logs

service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp_http/openobserve]
```

日志会进入 `otel_logs` stream。指标和 Trace 使用同一个 base endpoint，或者在发送端分别使用 `/v1/metrics`、`/v1/traces`。OTLP/gRPC 使用 `100.100.10.1:5081`，同时发送 `organization: default`、`Authorization` 和 `stream-name` headers。

实际接入应用时，优先让应用或 Collector 使用 batch、重试和内存限制；不要为每一条日志单独发一个 HTTP 请求。敏感字段应在进入 OpenObserve 前通过 Collector processor 或 OpenObserve pipeline 脱敏。

## 验证数据确实进入 Garage

可选用 AWS CLI 检查 Garage 的对象：

```bash
set -a
. /data/openobserve/openobserve.env
set +a
export AWS_ACCESS_KEY_ID="$ZO_S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ZO_S3_SECRET_KEY"

nix run nixpkgs#awscli2 -- s3 ls \
  "s3://${ZO_S3_BUCKET_NAME}/openobserve/" \
  --endpoint-url "$ZO_S3_SERVER_URL" \
  --region "$ZO_S3_REGION_NAME"
```

只看到 SQLite 文件、看不到 Garage 对象并不一定是失败：OpenObserve 会先写 WAL 和本地缓存，再按推送/compaction 周期写 Parquet。应结合 OpenObserve 日志、UI 中的日志查询和 Garage bucket 内容一起判断。

## 日常运维

查看运行日志：

```bash
journalctl --user -u openobserve -f
```

修改 `modules/host-services/openobserve.nix` 后，重新执行 `just hm-switch 'longred@nuc'`。升级时修改 `openobserveImage` 的版本并先备份 `/data/openobserve/data` 和 Garage bucket；回滚时恢复旧镜像 tag 后重新切换 Home Manager generation。涉及 SQLite schema migration 时，不要在没有备份的情况下反复切换版本。

为避免同一块盘被日志持续填满，应根据实际保留需求配置各 stream 的 retention，并持续观察：

```bash
du -sh /data/openobserve /data/garage
df -h /data
```

OpenObserve Web UI、OTLP endpoint 和 Garage S3 endpoint 是三个不同的用途：采集端只需要 OpenObserve 的 `5080/5081`；不要把 Garage 的 `3900` 暴露给不需要直接操作对象的客户端。

## 参考资料

- [OpenObserve 官方仓库](https://github.com/openobserve/openobserve)
- [OpenObserve Linux agent](https://github.com/openobserve/agents)
- [OpenObserve Kubernetes Helm chart](https://github.com/openobserve/openobserve-helm-chart)
- [OpenObserve 环境变量](https://openobserve.ai/docs/administration/configuration/environment-variables/)
- [OpenObserve 存储配置](https://openobserve.ai/docs/administration/maintenance/storage-management/storage/)
- [OpenObserve OTLP 日志接入](https://openobserve.ai/docs/ingestion/logs/otlp/)
- [OpenTelemetry Collector OTLP exporter](https://opentelemetry.io/docs/collector/configuration/)
- [OpenObserve Systemd 部署说明](https://openobserve.ai/docs/administration/maintenance/operator-guide/systemd/)
- [Garage CLI 与 bucket/key 管理](https://garagehq.deuxfleurs.fr/documentation/quick-start/)
