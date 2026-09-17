# 告警与通知

[返回文档索引](README.md) · [返回项目 README](../README.md)

本页说明 home lab 的告警链路：谁负责判定、谁负责送达、为什么通知端不与被监控对象同机，以及如何验证每一段。

## 职责分层

| 层 | 职责 | 落点 | 状态 |
| --- | --- | --- | --- |
| L1 判定 | 指标、日志、Trace 的规则判定与抑制 | OpenObserve（NUC） | 本文档描述的 provision 已覆盖 |
| L2 送达 | 把告警变成手机上的一条通知 | ntfy（`longred-vm`），公网主机名经 Cloudflare Tunnel 发布 | 见 `hosts/longred-vm/ntfy.nix` 与 `hosts/longred-vm/cloudflared.nix` |
| L3 死亡确认 | 主机或整个网络消失时仍然发出告警 | 外部服务的心跳 | **尚未实现**，见"已知缺口" |

L1 与 L2 都在家里，因此它们只能证明"家里还活着"。没有 L3 时，断电、断网或整机故障表现为沉默，而沉默与"一切正常"无法区分。

## 为什么通知端放在 `longred-vm` 而不是 NUC

NUC 是 OpenObserve 监控的对象。把通知端放在被监控的机器上，它会在告警最需要送达的时刻一起静默。`longred-vm` 位于另一台物理主机（虚拟化宿主），因此 NUC 掉线不会带走通知链路。

这个选择有代价，必须写明：该 VM 依赖虚拟化宿主与 libvirt NAT，独立性弱于另一台裸机。这正是 L3 不能省略的原因。

## 部署形态

### 通知端（NixOS，`longred-vm`）

`services.ntfy-sh` 监听 **loopback**，由 `tailscale serve` 发布到本节点的 tailnet HTTPS 名。这样做的两个理由：

- 直接绑定 tailnet 地址会与 `tailscaled` 竞争启动顺序：nixpkgs 的单元只声明 `after = [ "network.target" ]`，tailnet 地址在 `tailscaled` 就绪前不存在，单元会启动失败。
- 走 `tailscale serve` 由 `tailscaled` 终止 TLS，无需额外证书，也不需要任何防火墙端口（443 由 `tailscaled` 自己持有）。ntfy 由此通过 `X-Forwarded-For` 获取客户端地址，所以配置里必须保持 `behind-proxy = true`。

访问控制按"私有实例"配置：

- `auth-default-access = "deny-all"`：默认既不可读也不可写。
- `auth-default-access = "deny-all"`：默认既不可读也不可写，且**没有任何匿名条目**。发布端用 bearer token，订阅端用账号或令牌。早先允许匿名写入发布主题，那在服务只存在于 tailnet 内时是可接受的，一旦挂上公网主机名就不再成立。

> 主题名不是机密。它出现在仓库的配置与文档里，安全性由上面的 ACL 提供，而不是靠"没人知道主题名"。

### 为什么凭据不是声明式的

ntfy 支持在 `server.yml` 里声明 `auth-users` / `auth-tokens`。本仓库**没有**使用它们，原因有两条：

- `settings` 生成的文件会进入 `/nix/store`，而 access token 是明文 bearer 凭据，属于"不得插入 Nix 表达式或 Nix store"的范畴。
- 改用 `environmentFile` 可以把值移出 store，但会让凭据出现在进程环境里，与本仓库"服务只拿 `config.age.secrets.<name>.path`"的约定不一致。

因此用户与 token 通过 `ntfy` CLI 在目标主机上创建，只存在于该主机的 `auth-file` 中。这与 OpenObserve 自身的 root 口令、Garage 的 RPC secret 采用同一种"首次生成、只落本机"的模式。

### 判定端（OpenObserve，NUC）

`modules/host-services/openobserve.nix` 里新增的 `openobserve-alerts` 单元通过 API 幂等地调和（reconcile）消息模板、通知目标和告警规则：缺失则创建，已存在但与仓库不一致则更新。它是**追加式**的：不修改 `openobserve` 单元本身，因此应用这个模块不会重启正在运行的 OpenObserve 容器。

单元用 `Wants` 而非 `Requires` 依赖 `openobserve.service`：provision 失败不应该连带把观测栈拖下去。修复原因后用 `systemctl --user start openobserve-alerts` 重跑即可。

目标 URL 里的路径就是发布主题路径，模板渲染出的正文会成为通知正文，标题、优先级与标签通过 `headers` 传递。

### SQL 告警按**返回行数**判定，不是按聚合值

这是本页最容易踩错、且不会报错的一点。OpenObserve 用查询**返回的行数**去和 `trigger_condition` 比较，`SELECT` 出来的聚合值不参与判定。实测：`SELECT 0.5 AS v ... LIMIT 1` 得到的 `actual_value` 是 `1`。

后果是双向的，且都属于"看起来正常"的失败：

- `SELECT max(value) ...` 永远只返回一行，因此**永远触发不了**（除非阈值恰好 ≤ 1）；
- `SELECT count(*) ...` 也永远只返回一行，配 `>= 1` 就是**无条件误报**。

正确的写法是让**一行代表一次越限**，阈值固定为 1：

```sql
SELECT host_name, max(value) AS load1
FROM "<metric-stream>"
GROUP BY host_name
HAVING max(value) >= <threshold>
```

规则里因此不再用聚合结果当阈值。判定端用同一个 SQL 引擎，可以直接用查询接口先验证：健康时应返回 **0 行**，把阈值调大做阳性对照时应返回对应数量的行。

### 日志告警要读 `body_unit`，不是 `body__systemd_unit`

判定"某个服务单元失败了"必须用 systemd 的 `UNIT=` 字段（流里是 `body_unit`），**不是** `_SYSTEMD_UNIT`（`body__systemd_unit`）。原因是报"某单元失败"的那几行日志由 PID 1 写出，它们的 `_SYSTEMD_UNIT` 是 `init.scope`，只有 `UNIT=` 才指向真正失败的单元。实测：按 `body__systemd_unit` 过滤永远匹配不到任何失败记录，换成 `body_unit` 立刻匹配到。

同一族字段里 `body_unit_result` 只在单元**非正常退出**时才被写入（实测 26 小时内只出现过 `exit-code`，成功退出不写），所以"该字段非空"本身就是失败判据，不需要去正则匹配日志正文——那既脆弱又会把正文里出现 "failed" 的正常日志算进来。

## 首次启用

在通知端主机上为订阅者（手机）创建一个用户：

```bash
sudo ntfy user add --role=admin <user>
```

CLI 没有 `-c/--config` 这类全局参数；它自行读取本机的 `/etc/ntfy/server.yml`（即 nixpkgs 模块生成的配置），因此不需要指定 `auth-file`。创建后核对：

```bash
sudo ntfy user list
sudo ntfy access
```

Android 客户端可直接订阅主题并登录该用户；iOS 客户端还依赖 `base-url` 与上游转发，见下文。

## 已知边界与依赖

- **SSRF 防护被有意关闭。** OpenObserve 默认拒绝把告警 webhook 投递到**任何解析为私网地址的目标**——loopback、LAN 与 Tailscale 的 `100.64.0.0/10` 都在拒绝范围内（实测 `127.0.0.1` 与 tailnet 地址均返回 400，公网地址放行）。本部署唯一的通知端正好是 tailnet 地址，因此 `ZO_SKIP_SSRF_CHECKS=true` 是告警链路能工作的前提。这确实关掉了一层真实防护（该模块历史上有多起 SSRF 绕过 CVE）。补偿措施：HTTP 监听只绑 Tailscale 地址，LAN 与公网都到不了 API；组织内只有一个 root 用户，"低权限租户诱导服务端访问内网"这一威胁模型在此不成立。**一旦新增第二个用户、或引入不可信的摄入/富化路径，必须重新评估这一项。**
- **投递是直连，不经过代理。** OpenObserve 容器以 `--http-proxy=false` 启动，podman 因此不会把宿主机的 `http_proxy`/`https_proxy` 注入容器；实测容器内没有任何代理变量，webhook 直接走 tailnet。**这一点必须保持**：实测把同一个请求交给本机代理时 TLS 握手会失败，若将来打开代理注入，通知链路会随之失效，届时需要把该域名加入 `no_proxy`。
- **HTTPS 监听依赖已签发的证书。** `tailscale serve` 只发布监听、不负责取证书；证书缺失时 TCP 能建立但握手失败，表现为难查的 `unexpected eof`。因此 `tailscale-serve-ntfy` 在启动监听前用幂等的 `tailscale cert` 确保证书就位。
- **iOS 推送经过第三方，并且需要两个设置同时正确。** Android 完全自足；iOS 无法在没有中心服务器的前提下收推送，所以自建服务器必须同时满足：

  1. `base-url` 与客户端实际订阅的地址**逐字一致**（它参与 Firebase 主题的哈希计算，不一致时 iPhone 静默收不到而 Android 正常）；
  2. `upstream-base-url` 指向一个有 APNs 通道的上游（这里用官方 `ntfy.sh`）。

  第 2 条**不是内置默认值**：官方文档的配置表把它列成默认 `https://ntfy.sh`，但 `ntfy serve --help` 对它不显示默认值，源码里的判断是 `UpstreamBaseURL != ""`。不设置时一切看起来正常，只是 iPhone 的通知会退化成慢轮询（文档说法是"可能几小时"）。只有 Android 用户时这个坑不会暴露。
- **附件保持启用。** nixpkgs 存在"禁用附件时切换报错"的已知问题（见上游参考），因此这里不改 `attachment-cache-dir`，由 nixpkgs 模块的默认值处理。
- **覆盖范围受数据源限制。** 只有上报到 OpenObserve 的主机才能被判定；`longred-vm` 通过 `openobserve-agent.nix` 上报主机指标与 journald 之后即被覆盖。任何新增主机同样需要先接入采集器，否则规则对它是空的——注意"没有数据"和"一切正常"在这个判定模型里长得一样，规则不会因为主机消失而报警。
- **新出现的流会有短暂的字段滞后。** OpenObserve 的字段 schema 是随记录逐步学出来的，因此新流刚建立时，引用新字段的规则会因为"字段不存在"报错。这不是配置问题，记录进来之后自愈；历史里会留下几条 `error` 记录。
- **流名会把 `-` 规范成 `_`。** 采集器按 `${hostname}_journald` 命名，实际落地为 `longred_vm_journald`；写规则时要用规范后的名字。
- **告警规则只创建、不删除。** provision 幂等的方向是"缺失即创建"，不负责删除仓库中已移除的规则；需要清理时在控制台或 API 中删除。

## 发布端凭据

发布端不使用匿名写入。通知目标带 `Authorization: Bearer` 头，取值来自 `secrets/ntfy-publish-token.age`，由 `config.age.secrets.ntfy-publish-token.path` 在运行时读出。

这个 token **不写进目标配置的 store 文件**：目标 payload 是先 `builtins.toJSON` 写进 `/nix/store` 的，而 store 路径全局可读，所以脚本在运行时用 `jq` 把头部注入一份 `mktemp` 出来的临时副本再提交。同理，agenix 在 Home Manager 下的路径是**字面量** `${XDG_RUNTIME_DIR}/agenix/<name>`，取用时必须放在双引号里让 shell 展开，单引号会让 `cat` 找不到文件。

provision 会比对目标的 `url`/`method`/`type`/`template`/`skip_tls_verify`/`headers`，不一致就 `PUT` 更新——因此**轮换 token 后重新 apply 即可生效**，不需要手工删除目标。用 `ntfy token add --label=<name> <user>` 生成新 token 时，注意 `ntfy token list` 会把 token 明文打印出来，不要在会被记录的地方执行它。

## 验证

判定端：

```bash
systemctl --user --no-pager status openobserve-alerts
journalctl --user -u openobserve-alerts -n 100 --no-pager
```

通知端：

```bash
systemctl status ntfy-sh tailscale-serve-ntfy
tailscale serve status
```

端到端：从**另一台** tailnet 设备发布一条测试消息并确认手机收到。不要在服务所在主机上验证可达性——服务所在节点无法回环访问自己的服务地址。

```bash
curl -H "Title: test" -H "Priority: low" -d "alerting pipeline check" \
  https://<ntfy-host>.<tailnet>.ts.net/<topic>
```

"规则存在"不等于"会触发"，"接口可达"也不等于"链路通"。至少要做三件事：

1. **验证规则判定方向**：按上面的方式在同一个 SQL 引擎里跑规则的查询，确认健康时返回 0 行、把阈值调大做阳性对照时返回预期的行数。
2. **验证会真触发**：临时建一条阈值必然满足的规则，等它评估，确认通知端计数增长、告警历史里 `status` 为 `firing` 且 `error` 为空，然后删掉这条临时规则。
3. **验证通知确实送达手机**：前两步只能证明请求被接受，最后一段只有你看得见。

iOS 那一跳可以独立验证，而且不需要 iPhone 在场。服务器会把每个消息转成一条 `poll_request` 发到上游的一个公开主题，主题名就是 `sha256("$baseUrl/$topic")`：

```bash
h=$(printf '%s' 'https://<公网主机名>/<topic>' | sha256sum | cut -d' ' -f1)
( curl -sN "https://ntfy.sh/$h/json" > /tmp/poll.txt & )
sleep 3
# 在另一处发布一条消息
curl -H "Authorization: Bearer <token>" -d "hello" https://<公网主机名>/<topic>
sleep 5
cat /tmp/poll.txt     # 应出现 {"event":"poll_request", ..., "poll_id":"..."}
```

注意这个主题**不能**用 `?poll=1` 读回历史：poll_request 不进可轮询的缓存，必须实时订阅才能观察到。找不到转发记录时，先确认 `upstream-base-url` 是否真的设置过。

## 参考

- 权威来源：[`hosts/longred-vm/ntfy.nix`](../hosts/longred-vm/ntfy.nix)、[`modules/host-services/openobserve.nix`](../modules/host-services/openobserve.nix)
- [ntfy 配置](https://docs.ntfy.sh/config/)、[ntfy 发布](https://docs.ntfy.sh/publish/)
- [OpenObserve 告警](https://openobserve.ai/docs/alerts/)
- nixpkgs [ntfy-sh 模块](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/misc/ntfy-sh.nix)、[禁用附件的已知问题 #299003](https://github.com/NixOS/nixpkgs/issues/299003)
