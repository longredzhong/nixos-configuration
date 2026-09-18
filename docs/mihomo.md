# mihomo（Clash Meta）

[返回文档索引](README.md) · [返回项目 README](../README.md)

## 作用范围

`modules/host-services/mihomo.nix` 在 standalone Home Manager 目标上创建用户级 `mihomo.service`，提供本机 mixed（HTTP/SOCKS）代理、metacubexd 控制面板，以及面向 OpenObserve 的指标采集。运行时配置由 `config/mihomo/config.template.yaml` 加运行时机密渲染，节点凭据不进入 Nix store。

实际端口、路径和开关以 Nix 模块为准。当前机器上 `9090` 已被 Cockpit 占用，因此 controller 默认使用 `9091`。

**目前两台主机各跑一份**：NUC（standalone Home Manager，`users/longred/nuc.nix`）与 `longred-vm`（NixOS 内嵌 Home Manager，`hosts/longred-vm/home.nix`）。VM 上那份是必需的，不是复制粘贴的偏好：这台客户机直连公网的路由很慢（实测 `cache.nixos.org` 289 ms RTT、约 9 KB/s），而它的 `nix-daemon` 又要靠替换器工作，所以 `hosts/longred-vm/configuration.nix` 用 `networking.proxy` 把系统服务（含 `nix-daemon`）指向**本机** `127.0.0.1:7890`，不再绕经 NUC。VM 那份 `controllerHost` 保持 `127.0.0.1`、`allowLan = false`，对 tailnet 的面仍然只有 NUC 那一个。

这个组合暴露过一处陷阱，已在模块里修掉：`networking.proxy` 会把代理写进**系统环境**，于是 mihomo 自己的 `ExecStartPre`（渲染脚本要抓订阅和覆写文档）也会继承 `http_proxy=127.0.0.1:7890`——而那个监听器此时还没起来，首次启动会渲染出一个没有任何节点的配置。现在 `renderConfig` 与 `startMihomo` 共用同一段 `noAmbientProxy` 前置（unset 所有代理变量 + 只保留回环 `no_proxy`），两个步骤都不再受环境代理影响。

## 组件

| 组件 | 作用 | 来源 |
| --- | --- | --- |
| mihomo | 规则代理内核，监听 mixed-port | `pkgs.unstable.mihomo`（跟随 nixpkgs-unstable） |
| metacubexd | Web 控制面板 | `pkgs.metacubexd`，由 `mihomo -ext-ui` 提供 |
| 配置渲染 | 模板 + 运行时机密 + 规则覆写 → 0600 运行配置 | `config/mihomo/render.py` |
| 指标导出 | 轮询 controller API，转发 OTLP 指标 | `config/mihomo/metrics.py` |

订阅链接只提供代理节点；代理组、`rule-providers` 和规则来自外部覆写文档（`hostServices.mihomo.rulesOverrideUrl`，默认 override-hub 的 ACL4SSR 配置）。渲染脚本启动时抓取该文档并缓存到状态目录，下载失败时回退上一次缓存，再无缓存则使用最小 `PROXY/DIRECT` 规则集。`external-controller` 绑定地址由 `hostServices.mihomo.controllerHost`（默认 `127.0.0.1`）与 `controllerPort` 决定，指标采集器跟随同一地址。

服务以用户级 systemd unit 运行，并启用了接近 NixOS `services.mihomo` 非 TUN 路径的加固（`ProtectSystem=strict`、`ProtectHome=read-only`、`PrivateDevices`、`RestrictAddressFamilies`、`SystemCallFilter=@system-service bpf`、`MemoryDenyWriteExecute` 等）。`Restart=on-failure` 并带 `StartLimitBurst`，配置损坏时不会无休止重启。

## 机密与运行时文件

订阅链接和自定义节点是凭据，默认放在用户配置目录，不提交：

```bash
install -d -m 700 ~/.config/mihomo
printf '%s\n' '<subscription-url>' > ~/.config/mihomo/subscription.url
chmod 600 ~/.config/mihomo/subscription.url

# 可选：自定义节点（Clash YAML 的 proxies: 列表，可为不带 proxies: 头的裸列表）
$EDITOR ~/.config/mihomo/custom.yaml
chmod 600 ~/.config/mihomo/custom.yaml

# 可选：自定义规则（Clash YAML 的 rules: 列表），前置到覆写规则之前
$EDITOR ~/.config/mihomo/rules.yaml
chmod 600 ~/.config/mihomo/rules.yaml
```

- 目录职责分离：**用户提供的凭据**放在 `~/.config/mihomo/`，**mihomo 运行时生成的文件**放在 `~/.local/state/mihomo/`（systemd `StateDirectory`，0700）。渲染脚本每次启动都会把这三个输入文件强制设为 0600，即使用户手工创建成 0644。
- 缺少订阅链接文件时，mihomo 仍会启动，只用自定义节点和 DIRECT，并在日志中提示。
- 自定义节点渲染为顶层 `proxies`（而不是 file provider），这样节点之间的 `dialer-proxy` 链才能解析；覆写里的 `include-all` 组仍会自动收录它们。
- 自定义规则按 Clash Party `+rules` 语义前置到覆写规则之前。注意 Clash 不接受 `*.ts.net` / `.local` 这类写法，应写成 `ts.net` / `local`。
- controller secret 由渲染脚本首次启动时随机生成并写入 `~/.local/state/mihomo/controller.secret`（0600）。
- 迁移到 Agenix：声明 `age.secrets.<name>`，把 `hostServices.mihomo.subscriptionUrlFile`、`customProxiesFile` 或 `customRulesFile` 指向 `config.age.secrets.<name>.path`。

用户配置目录（凭据，0600）：

- `~/.config/mihomo/subscription.url`
- `~/.config/mihomo/custom.yaml`
- `~/.config/mihomo/rules.yaml`

运行时状态目录（生成，0700/0600）：

- `~/.local/state/mihomo/config.yaml`（渲染结果）
- `~/.local/state/mihomo/controller.secret`
- `~/.local/state/mihomo/override.yaml`（覆写文档缓存）
- `~/.local/state/mihomo/providers/`、`ruleset/`、`GeoIP.dat`、`GeoSite.dat`、`cache.db`

## 订阅与自定义节点

- 订阅由 `proxy-providers.sub`（`type: http`）管理，每 6 小时更新，带 `health-check`（`lazy: false`，保证节点会真正被探测）、`size-limit` 和 `override`；无需外部 cron。provider 下载固定 `proxy: DIRECT`，避免在节点可用前因走代理规则而失败。
- 自定义节点独立于订阅：编辑 `custom.yaml` 后重启服务，订阅刷新不会覆盖它。
- 代理组来自覆写文档（如 `节点选择`、`自动选择`、`手动切换` 及各类分流组），多为 `include-all`。订阅缺失时回退到内置的 `PROXY`、`节点选择`、`AUTO` 组。
- 分流：覆写规则为主；`rules.yaml` 的自定义规则前置。请自行保证 Tailscale（`100.64.0.0/10`、`fd7a:115c:a1e0::/48`、`ts.net`）、内网地址与自建节点域名走 DIRECT。
- DNS：国内 DoH（`doh.pub`、`alidns`）为主解析，配 `fallback` 到可信海外 DoH（`1.1.1.1`、`dns.google`）并以 `fallback-filter`（`geoip-code: CN`）只在解析结果落在境外时才切换，避免 CN 域名/CDN 被海外解析污染。`proxy-server-nameserver` 固定国内 DNS 解析节点域名与订阅域名，防止解析回路。mixed-port 桌面场景不监听 `:53`，也不使用 fake-ip。
- 虽然 `allow-lan` 可开启以服务 LAN 客户端，但用 `lan-allowed-ips` 限定来源；NUC 上只放行回环与 Tailscale（`127.0.0.0/8`、`100.64.0.0/10`）。

## 使用

控制面板地址由 `controllerHost:controllerPort` 决定（默认 `127.0.0.1:9091`）：

```text
http://127.0.0.1:9091/ui
```

把 `controllerHost` 设为局域网或 Tailscale 地址即可远程访问面板，此时 `mihomo-metrics` 也会跟随该地址。代理端口的 LAN 访问由 `allowLan` + `lanAllowedIps` 控制，默认关闭。首次打开后输入 `~/.local/state/mihomo/controller.secret` 的内容作为 API secret。面板可切换模式、选择节点、查看连接并触发订阅更新；结构性配置以仓库模板和覆写文档为准，改动后重新 `hm-switch`。

代理使用：

```bash
set_proxy            # 默认 127.0.0.1:7890（mixed）
show_proxy
curl -x http://127.0.0.1:7890 -sS -o /dev/null -w '%{http_code}\n' https://www.gstatic.com/generate_204
```

`hostServices.proxyUrl` 为 `http://127.0.0.1:7890` 时，`proxyEnvironment` 会把用户级服务也切到本机 mihomo。回退：把 `hostServices.mihomo.takeOverProxy` 设为 `false`（或把 `hostServices.proxyUrl` 指回上游）后 `hm-switch`。

远程访问面板时不要直接对公网暴露 controller；使用 SSH 隧道或 Tailscale，并用 secret（`controller.secret`）保护 API。绑定到 LAN/Tailscale 地址时确保防火墙只放行可信来源。

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
curl -sS -H "Authorization: Bearer $secret" http://<controller-host>:9091/version
curl -sS -H "Authorization: Bearer $secret" http://<controller-host>:9091/providers/rules
```

启动前可单独校验配置：

```bash
mihomo -t -d ~/.local/state/mihomo -f ~/.local/state/mihomo/config.yaml
```

## 状态和回滚

- 用户凭据位于 `~/.config/mihomo/`（0600），运行时生成文件位于 `~/.local/state/mihomo/`（0700/0600）。
- 覆写文档不可达时使用上次缓存；从未成功下载则回退内置规则集。
- 订阅缺失或失效不影响 DIRECT 规则和国内分流；国际流量会失败。恢复方式是修好订阅后重启，或临时把 `takeOverProxy` 设回 `false`。
- 回滚：恢复旧 generation；若曾把 `hostServices.proxyUrl` 切到本机，回滚会一并恢复。

## 参考资料

- [mihomo 仓库](https://github.com/MetaCubeX/mihomo)
- [mihomo 文档](https://wiki.metacubex.one/)
- [覆写（YAML）](https://clashparty.org/docs/guide/override/yaml)
- [override-hub](https://github.com/mihomo-party-org/override-hub)
- [proxy-providers](https://wiki.metacubex.one/en/config/proxy-providers/)
- [API](https://wiki.metacubex.one/en/api/)
- [nixpkgs services.mihomo](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/mihomo.nix)
- [metacubexd](https://github.com/MetaCubeX/metacubexd)
