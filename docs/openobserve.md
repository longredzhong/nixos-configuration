# OpenObserve 与 OpenTelemetry

[返回文档索引](README.md) · [返回项目 README](../README.md)

## 作用范围

这组模块在一个 standalone Home Manager 目标上运行 OpenObserve、Garage 和 OpenTelemetry Collector：

| 组件 | 作用 | 配置来源 |
| --- | --- | --- |
| OpenObserve | 日志、指标和 Trace 的查询与存储入口 | `modules/host-services/openobserve.nix` |
| Garage | OpenObserve 的 S3-compatible 对象存储 | `modules/host-services/garage.nix` |
| Collector | journald、主机指标和 OTLP 数据采集 | `modules/host-services/openobserve-agent.nix` |
| 应用 instrumentation | 发送应用 Trace | 各应用服务模块 |

这是单节点部署。Garage 的复制配置、OpenObserve 的镜像、端口和数据路径都由 Nix 模块决定；文档不复制这些容易过期的值。单节点和单磁盘不等于高可用或异机备份。

## 存储与机密

- OpenObserve 的 SQLite 元数据、WAL 和本地缓存位于模块定义的数据目录。
- 日志、指标和 Trace 的 Parquet 对象写入 Garage bucket。
- 首次启动时，服务在运行时数据目录生成 env 文件、S3 配置和随机凭据；文件应保持 `0600`，不能进入 Git、Nix store、日志或截图。
- Collector 和应用只使用最小权限的 ingestion credential，不要使用 root 管理凭据发送数据。
- 备份至少覆盖 OpenObserve 的本地数据库、Garage 的 metadata/data 以及恢复所需的加密机密。

## 部署

standalone Home Manager 目标：

```bash
just check-fast
just hm-dry-run '<user>@<host>'
just hm-switch '<user>@<host>'
```

NixOS/WSL 目标按 [justfile](../justfile) 使用 `eval-host`、`build` 或 `switch-nixos`。切换后检查相关用户级服务：

```bash
systemctl --user --no-pager status garage openobserve openobserve-agent
journalctl --user -u openobserve -n 100 --no-pager
journalctl --user -u openobserve-agent -n 100 --no-pager
```

## 健康检查

从能够访问服务的主机执行：

```bash
curl --fail http://<observe-host>:<http-port>/healthz
```

健康接口只能证明 HTTP 入口可达。还要确认：

1. Garage 服务已启动并完成必要的单节点 layout；
2. OpenObserve env 文件包含完整的运行时配置；
3. Collector 没有 export、认证或 batch 错误；
4. UI 中对应 stream 有最近数据；
5. Garage bucket 中出现对象，或本地 WAL/compaction 状态符合预期。

如果数据暂时为空，先等待一个指标采集周期和 Collector batch timeout，再检查日志。健康接口成功不代表对象存储写入成功。

## Collector 数据流

Collector 默认负责三类数据：

- journald 日志：按 `<hostname>_journald` 之类的稳定命名区分主机；
- 主机指标：按 metric family 建立 `system_*` stream，并用 `host.name` 或等价 resource attribute 区分主机；
- OTLP logs/metrics/traces：由应用或其他 Collector 发送到 OpenObserve。

Garage 的 trace receiver 和 Prometheus receiver 只应在运行 Garage 的目标启用。Garage 的 S3 请求 Trace 和管理指标使用独立的 stream，避免与普通应用信号混合。

## OTLP 接入

应用或 Collector 使用 OpenObserve 的 OTLP/HTTP base endpoint：

```text
http://<observe-host>:<http-port>/api/<organization>
```

发送端自行追加 `/v1/logs`、`/v1/metrics` 或 `/v1/traces`。认证从运行时机密读取，示例只展示环境变量引用：

```yaml
exporters:
  otlp_http/openobserve:
    endpoint: http://<observe-host>:<http-port>/api/<organization>
    headers:
      Authorization: "Basic ${env:OPENOBSERVE_AUTH}"
      stream-name: example_logs
```

OTLP/gRPC 使用对应的 gRPC endpoint 和 header。容器中的 `127.0.0.1` 指向容器自身；容器接入宿主机服务时，应使用容器可达的宿主机地址或模块提供的网络方式。

应用接入时优先使用 batch、重试和内存限制。日志和 Trace 可能包含 prompt、请求参数或用户数据，应在 Collector processor、应用 instrumentation 或 OpenObserve pipeline 中脱敏，并限制 stream 的访问和保留时间。

## 应用 Trace

只有支持 OpenTelemetry 的 SDK 或 instrumentation 才会生成 span；单独设置 `OTEL_*` 环境变量不会为预编译服务自动创建 Trace。建议统一设置：

```text
OTEL_SERVICE_NAME=<service-name>
OTEL_RESOURCE_ATTRIBUTES=service.namespace=<namespace>,deployment.environment=<environment>,host.name=<host>
OTEL_EXPORTER_OTLP_ENDPOINT=http://<observe-host>:<http-port>/api/<organization>
```

使用稳定的 `service.name` 表示可部署服务，把主机、版本和环境放入 resource attributes。跨服务调用保留 `trace_id`、`span_id` 以及 `server.address`、`peer.service` 等标准属性，便于 Service Graph 和故障排查。

## 看板模板

仓库提供两个可导入模板：

- [Garage 看板](openobserve-garage-dashboard.json)：依赖 Garage Prometheus 指标和独立 Trace stream；
- [机器状态看板](openobserve-machine-dashboard.json)：按 `host_name` 聚合系统指标。

导入后在目标组织中检查 stream 名称和 metric labels。模板不包含账号、密码、地址或运行时看板 ID；不要把从生产 UI 导出的带 owner、URL 或权限信息的 JSON 直接提交。

## 数据验证

推荐按以下顺序验证：

```bash
systemctl --user is-active openobserve-agent
journalctl --user -u openobserve-agent --since '10 minutes ago' --no-pager
curl --fail http://<observe-host>:<http-port>/healthz
```

然后在 UI 中检查：

1. 日志 stream 有最近记录；
2. `system_*` 指标包含预期的 `host.name`；
3. 应用 Trace 的 `service.name`、时间线和错误状态正确；
4. Garage Trace 和指标在独立 stream 中出现；
5. retention、访问权限和磁盘占用符合预期。

## 故障排查

| 现象 | 优先检查 |
| --- | --- |
| OpenObserve 无法启动 | 数据目录权限、env 文件完整性、端口冲突和容器日志 |
| Garage 无法启动 | metadata/data 目录、RPC/S3 配置、layout 和加密机密 |
| 健康但没有数据 | Collector service、认证 header、endpoint、stream-name 和 batch 日志 |
| 指标存在但主机缺失 | `host.name`/resource processor、采集器权限和采集周期 |
| Trace 为空 | 应用是否真的启用了 instrumentation、协议是否匹配、时间范围和采样配置 |
| 对象存储没有新文件 | 先检查 WAL、推送间隔、compaction 和 Garage bucket，再判断是否失败 |

## 版本、备份和回滚

升级 OpenObserve、Garage 或 Collector 前：

1. 备份本地数据库和 Garage 数据；
2. 确认新版本的配置字段和存储迁移要求；
3. 修改对应 Nix 模块并运行 dry-run；
4. 切换后按本页顺序验证服务、数据和对象存储；
5. 需要回滚时恢复旧镜像/包版本，并保留兼容的数据库和 bucket 备份。

## 参考资料

- [OpenObserve 官方仓库](https://github.com/openobserve/openobserve)
- [OpenObserve 环境变量](https://openobserve.ai/docs/administration/configuration/environment-variables/)
- [OpenObserve 存储配置](https://openobserve.ai/docs/administration/maintenance/storage-management/storage/)
- [OpenObserve OTLP 接入](https://openobserve.ai/docs/ingestion/logs/otlp/)
- [OpenTelemetry Collector 配置](https://opentelemetry.io/docs/collector/configuration/)
- [Garage 快速开始](https://garagehq.deuxfleurs.fr/documentation/quick-start/)
- [Garage 配置参考](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
- [Garage 监控](https://garagehq.deuxfleurs.fr/documentation/cookbook/monitoring/)
