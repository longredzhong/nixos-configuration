# mihomo（Clash Meta）

[返回文档索引](README.md) · [返回项目 README](../README.md)

## 作用范围

`modules/host-services/mihomo.nix` 在 standalone Home Manager 目标上创建用户级 `mihomo.service`，提供本机 mixed（HTTP/SOCKS）代理、metacubexd 控制面板，以及面向 OpenObserve 的指标采集。运行时配置由 `config/mihomo/config.template.yaml` 加运行时机密渲染，节点凭据不进入 Nix store。

实际端口、路径和开关以 Nix 模块为准。当前机器上 `9090` 已被 Cockpit 占用，因此 controller 默认使用 `9091`。

## 组件

| 组件 | 作用 | 来源 |
| --- | --- | --- |
| mihomo | 规则代理内核，监听 mixed-port | `pkgs.mihomo` |
| metacubexd | 本机 Web 控制面板 | `pkgs.metacubexd`，由 `mihomo -ext-ui` 提供 |
| 配置渲染 | 模板 + 运行时机密 → 0600 运行配置 | `config/mihomo/render.py` |
| 指标导出 | 轮询 controller API，转发 OTLP 指标 | `config/mihomo/metrics.py` |

## 机密与运行时文件

订阅链接和自定义节点是凭据，默认放在用户配置目录，不提交：

```bash
install -d -m 700 ~/.config/mihomo
printf '%s\n' '<subscription-url>' > ~/.config/mihomo/subscription.url
chmod 600 ~/.config/mihomo/subscription.url

# 可选：自定义节点（Clash YAML 的 proxies: 列表）
$EDITOR ~/.config/mihomo/custom.yaml
chmod 600 ~/.config/mihomo/custom.yaml
```

- 缺少订阅链接文件时，mihomo 仍会启动，只用自定义节点和 DIRECT，并在日志中提示。
- controller secret 由渲染脚本首次启动时随机生成并写入 `~/.local/state/mihomo/controller.secret`（0600）。
- 迁移到 Agenix：声明 `age.secrets.<name>`，把 `hostServices.mihomo.subscriptionUrlFile` 或 `customProxiesFile` 指向 `config.age.secrets.<name>.path`。

渲染后的运行文件：

- `~/.local/state/mihomo/config.yaml`
- `~/.local/state/mihomo/providers/sub.yaml`（订阅缓存，含节点凭据）
- `~/.local/state/mihomo/providers/custom.yaml`
- 目录 0700，文件 0600。

## 订阅与自定义节点

- 订阅由 `proxy-providers.sub`（`type: http`）管理，每 6 小时更新，带 lazy health-check、`size-limit` 和 `override`；无需外部 cron。
- 自定义节点独立于订阅：编辑 `custom.yaml` 后重启服务，订阅刷新不会覆盖它。
- 代理组：`PROXY`（手动选择）、`AUTO`（url-test）、`DIRECT`。订阅缺失时这些组只包含自定义节点和 DIRECT。
- 分流：loopback、私网和 Tailscale（`100.64.0.0/10`、`ts.net`）强制 DIRECT；`GEOSITE,category-ads-all` REJECT；`GEOSITE,cn`/`GEOIP,CN` DIRECT；其余 `MATCH,PROXY`。
- DNS：国内 DoH 为主，海外 DoH 作 fallback，`proxy-server-nameserver` 解析节点域名。mixed-port 桌面场景不监听 `:53`，也默认不用 fake-ip。

## 使用

控制面板（在本机浏览器打开）：

```text
http://127.0.0.1:9091/ui
```

首次打开后输入 `~/.local/state/mihomo/controller.secret` 的内容作为 API secret。面板可切换模式、选择节点、查看连接并触发订阅更新；结构性配置以仓库模板为准，改动后重新 `hm-switch`。

代理使用：

```bash
set_proxy            # 默认 127.0.0.1:7890（mixed）
show_proxy
curl -x http://127.0.0.1:7890 -sS -o /dev/null -w '%{http_code}\n' https://www.gstatic.com/generate_204
```

`hostServices.proxyUrl` 为 `http://127.0.0.1:7890` 时，`proxyEnvironment` 会把用户级服务也切到本机 mihomo。回退：把 `hostServices.mihomo.takeOverProxy` 设为 `false`（或把 `hostServices.proxyUrl` 指回上游）后 `hm-switch`。

远程访问面板时不要直接对公网暴露 controller；使用 SSH 隧道或 Tailscale，并保持 secret 与本机回环绑定。

## OpenObserve 接入

- 日志：mihomo 输出到 journald，现有 collector 的 journald receiver 会采到 `<hostname>_journald`，可按 `_SYSTEMD_USER_UNIT=mihomo.service` 过滤。
- 指标：`mihomo-metrics.timer` 每 30 秒轮询 controller，把 `mihomo_traffic_*`、`mihomo_memory_inuse_bytes`、`mihomo_connections` 以 OTLP/HTTP 发到本机 collector（`127.0.0.1:4318`），collector 再导出到 OpenObserve；`openobserve-agent.nix` 的 metrics pipeline 已包含 `otlp` receiver。
- 指标 resource 带 `service.name=mihomo`、`service.namespace=longred`、`deployment.environment=home-lab`。

## 部署和验证

```bash
just check-fast
just hm-dry-run '<user>@<host>'
just hm-switch '<user>@<host>'
```

切换后：

```bash
systemctl --user is-active mihomo mihomo-metrics.timer
journalctl --user -u mihomo -n 100 --no-pager
curl -x http://127.0.0.1:7890 -sS -o /dev/null -w '%{http_code}\n' https://www.gstatic.com/generate_204
secret=$(cat ~/.local/state/mihomo/controller.secret)
curl -sS -H "Authorization: Bearer $secret" http://127.0.0.1:9091/version
```

启动前可单独校验配置：

```bash
mihomo -t -d ~/.local/state/mihomo -f ~/.local/state/mihomo/config.yaml
```

## 状态和回滚

- 运行配置与 provider 缓存位于 `~/.local/state/mihomo/`（0700/0600）。
- 订阅缺失或失效不影响 DIRECT 规则和国内分流；国际流量会失败。恢复方式是修好订阅后重启，或临时把 `takeOverProxy` 设回 `false`。
- 回滚：恢复旧 generation；若曾把 `hostServices.proxyUrl` 切到本机，回滚会一并恢复。

## 参考资料

- [mihomo 仓库](https://github.com/MetaCubeX/mihomo)
- [mihomo 文档](https://wiki.metacubex.one/)
- [proxy-providers](https://wiki.metacubex.one/en/config/proxy-providers/)
- [API](https://wiki.metacubex.one/en/api/)
- [nixpkgs services.mihomo](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/mihomo.nix)
- [metacubexd](https://github.com/MetaCubeX/metacubexd)
