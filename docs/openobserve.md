# NUC 上的 OpenObserve

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

第一次登录后，在 OpenObserve UI 中确认组织 `default`，并按用途创建独立 stream，例如 `nuc_system`、`application`、`traces`。root 密码是首次初始化 SQLite 元数据时使用的 bootstrap 值；已经初始化后，不要通过随意修改 env 文件来改密码，应使用 UI 的用户管理流程。

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
  otlphttp/openobserve:
    endpoint: http://100.100.10.1:5080/api/default
    headers:
      Authorization: "Basic ${env:OPENOBSERVE_AUTH}"
      stream-name: otel_logs

service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlphttp/openobserve]
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
- [OpenObserve 环境变量](https://openobserve.ai/docs/administration/configuration/environment-variables/)
- [OpenObserve 存储配置](https://openobserve.ai/docs/administration/maintenance/storage-management/storage/)
- [OpenObserve OTLP 日志接入](https://openobserve.ai/docs/ingestion/logs/otlp/)
- [OpenObserve Systemd 部署说明](https://openobserve.ai/docs/administration/maintenance/operator-guide/systemd/)
- [Garage CLI 与 bucket/key 管理](https://garagehq.deuxfleurs.fr/documentation/quick-start/)
