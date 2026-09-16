# 项目文档

[返回项目 README](../README.md) · [返回修改约定](../AGENTS.md)

## 使用顺序

1. 先阅读本页，确认配置来源和目标类型。
2. 运行 `just show-systems` 或 `just show-homes` 找到实际目标。
3. 修改对应 Nix 模块或 `config/` 声明文件。
4. 按主题文档执行 dry-run、切换和运行时验证。

## 文档地图

| 主题 | 内容 | 主要来源 |
| --- | --- | --- |
| [DeepSeek Harness](deepseek-harness.md) | Web 服务、Tailscale 身份认证、token 回退、远程 Settings 和回滚 | `modules/host-services/deepseek-harness.nix` |
| [OpenObserve 与 OpenTelemetry](openobserve.md) | OpenObserve、Garage、Collector、OTLP 和观测验证 | `modules/host-services/openobserve*.nix`、`modules/host-services/garage.nix` |
| [mihomo（Clash Meta）](mihomo.md) | 本机代理、订阅与自定义节点、Web 面板和 OpenObserve 指标 | `modules/host-services/mihomo.nix`、`config/mihomo/` |
| [Tailscale Services](tailscale-services.md) | Service endpoint、TLS 终止、审批和本地应用 | `config/tailscale/nuc-services.hujson`、`modules/host-services/tailscale-services.nix` |
| [Agenix 机密](../secrets/README.md) | 加密文件原则和运行时使用方式 | `secrets/*.age`、各服务模块的 `age.secrets` |
| [Garage 观测看板模板](openobserve-garage-dashboard.json) | 可导入的 Garage 指标看板模板 | OpenObserve dashboard JSON |
| [机器观测看板模板](openobserve-machine-dashboard.json) | 可导入的主机指标看板模板 | OpenObserve dashboard JSON |
| [Home Lab 观测看板模板](openobserve-homelab-dashboard.json) | 可导入的服务可用性与机器负载看板模板 | OpenObserve dashboard JSON |

## 来源与验证边界

- Flake 输出、Nix 模块和 `config/` 文件决定实际配置；文档不替代它们。
- 文档中的地址、主机、账号和 token 都使用占位符。部署时从目标配置和运行时状态读取实际值。
- “已部署”“已批准”“已有数据”等现场结论必须同时给出目标、时间和验证命令；没有这些信息时，只描述预期行为。
- 上游产品行为以主题文档末尾的官方链接为准；升级依赖后重新执行相关验证。

## 通用部署流程

```bash
just check-fast
just hm-dry-run '<user>@<host>'
just hm-switch '<user>@<host>'
systemctl --user --no-pager status '<service>'
journalctl --user -u '<service>' -n 100 --no-pager
```

NixOS 目标使用 `just eval-host '<host>'`、`just build '<host>'` 或 `just switch-nixos '<host>'`。不要把真实目标参数复制回通用文档。
