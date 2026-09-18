# longred-vm：Nix 构建机、二进制缓存、Garage 备份节点与通知端

[返回项目文档索引](README.md) · [返回项目 README](../README.md) · [返回修改约定](../AGENTS.md)

本文说明 `longred-vm` 这台 KVM 虚拟机在家庭实验室里承担的角色：Nix 远程构建机、带签名的二进制缓存、
NUC 上 Garage 对象存储的备份节点，以及告警链路里的通知端与观测数据源。主机本身的定义在 `hosts/longred-vm/`。

通知端与采集器是后来加入的，各自的理由写在它们自己的文档里：

| 角色 | 模块 | 说明 |
| --- | --- | --- |
| ntfy 通知端 | `hosts/longred-vm/ntfy.nix` | 见 [告警与通知](alerting.md)；放在这里是因为 NUC 正是被监控的对象 |
| 观测数据源 | `hosts/longred-vm/home.nix` → `modules/host-services/openobserve-agent.nix` | 上报主机指标与 journald；因为是用户级服务，`dev` 需要 `linger`，令牌由系统级 agenix 用主机密钥解密后按路径交给该用户服务 |
| 公网入口 | `hosts/longred-vm/cloudflared.nix` | Cloudflare Tunnel，**凭证托管**模式：只传 tunnel token，公网主机名在 Zero Trust 仪表盘配置。这里**故意不写本地 ingress**——托管模式下本地 ingress 不生效，现有 `modules/host-services/cloudflared.nix` 就是这种情况 |
| 多智能体平台 | `hosts/longred-vm/memoh.nix` | 见 [Memoh](memoh.md)。本仓库**唯一**使用 rootful Docker 的服务，放在这台隔离客户机而不是 NUC，原因是它的 `server` 容器是 privileged + `pid: host` |
| 出口代理 | `hosts/longred-vm/home.nix` → `modules/host-services/mihomo.nix` | 见 [mihomo](mihomo.md)。这台客户机直连公网只有约 9 KB/s（`cache.nixos.org` 实测 289 ms RTT），而它的 `nix-daemon` 必须靠替换器工作，所以它跑自己的代理并让**系统服务走本机** `127.0.0.1:7890`（`hosts/longred-vm/configuration.nix` 的 `networking.proxy`）；不要再把它指向 NUC 的监听器，那会把每次取包都变成跨网段往返 |

## 这台机器是什么

一台单盘 KVM 客户机，跑干净的 NixOS 26.05，除本文描述的基础设施外不承载业务服务：

| 项 | 值 |
| --- | --- |
| 登录用户 | `dev`（沿用重装前的账号，所以 `ssh dev@<host>` 不变） |
| 磁盘 | 1 MiB BIOS boot 分区 + 单 ext4 根分区，GRUB 传统引导 |
| 网络 | `enp2s0` 走实验室局域网（默认路由，metric 100），`enp1s0` 是 libvirt NAT（metric 500） |
| Tailscale | 沿用重装前的节点身份，节点名与地址不变 |
| 其他 | zram swap、qemu guest agent、ttyS0 串口控制台 |

`enp1s0` 所在的 libvirt NAT 网络在这台宿主上没有可用外网出口，所以 dhcpcd 的 metric 被显式钉住，
让局域网网卡持有默认路由。少了这一步会出现「DNS 能解析、网关能 ping 通，但出站流量全部不通」的现象。

## 远程构建机

其他机器把 `longred-vm` 当作 `nix.buildMachines` 目标。构建机侧需要的只有两件事：

- `nix.settings.trusted-users` 包含 `root` 与 `@wheel`，让连上来的客户端可以请求构建；
- `sshd` 允许 **仅密钥** 的 root 登录。Nix 通过 SSH 驱动对端的 nix-daemon，而 daemon 要写 `/nix/store`，
  所以构建机必须接受 root 登录。真正决定谁能连的是 tailnet ACL。

`nix.settings.system-features` 声明了 `nixos-test`、`benchmark`、`big-parallel`、`kvm`
（这台客户机有 `/dev/kvm`）。

## 二进制缓存

`services.harmonia.cache` 提供缓存服务，监听 `[::]:5000`，但防火墙规则挂在 `tailscale0` 上，
所以只有 tailnet 内可达，局域网与 libvirt NAT 网络都到不了。

缓存用一把签名密钥给 narinfo 签名，客户端凭公钥校验。密钥的处理方式：

- 私钥以 agenix 加密文件 `secrets/nix-binary-cache-key.age` 提交；
- 接收者是这台机器自己的 SSH host key，以及管理员账号的公钥作为恢复路径；
- 注意接收者必须用 **SSH 形式**（`age -R <pubkey>`，密文里是 `ssh-ed25519` 接收者）。
  用 `ssh-to-age` 把 SSH 公钥转成 `age1...` 接收者再加密是不行的：upstream `age` 只接受
  SSH 私钥作为 `ssh-ed25519` 接收者的身份，对 X25519 接收者会报
  `no identity matched any of the recipients`；
- 解密后的私钥通过 systemd credential 交给 harmonia，不进入 Nix store，也不写日志。

公开的缓存公钥是 `longred-vm-cache-1:NC3x6LieSUDpdcCsPXZOwE4xJS2CD0fJCpEtHZrG+ag=`。

## Garage 备份节点

NUC 上跑着单节点 Garage，数据约 1.6 GB。这台机器跑第二个、独立的单节点 Garage，
把 NUC 的 bucket 镜像过来，因此备份本身就是可用的 S3 端点，而不是一堆不透明的文件。

**为什么走 S3 而不是拷文件。** Garage 的数据目录在节点写入时不能安全读取，直接复制可能得到不一致的
备份。走 S3 API 天然是应用层一致的。

**为什么用定时器而不是常驻。** 这台机器到 NUC 只有一条中继（DERP）链路，实测约 1.6 MB/s。
增量镜像没问题，持续流式同步则很痛苦。定时器每 6 小时跑一次，开机后立即跑第一次。

组成：

- `garage-backup.service`：Garage 本体，数据在 `/var/lib/garage`，RPC 与 admin API 只监听 loopback，
  S3 API 对 tailnet 开放；
- `garage-backup-init.service`：首次启动生成 RPC secret 与 admin token（本机集群自己用，不需要进仓库）；
- `garage-backup-provision.service`：应用单节点 layout、建 bucket、建镜像用 key，并把 key 凭据写到
  `/var/lib/garage/dest.env`（root-only）。全部幂等，每次开机都跑；
- `garage-backup-mirror.service` + `.timer`：用 rclone 对每个 bucket 做 `sync`。

凭据分两侧：

- **源侧**是 NUC 上一把只读 key，通过 `secrets/garage-backup-read.age` 下发到这台机器，镜像从不写 NUC；
- **目标侧**是 provision 在本机生成的 key，凭据留在本机文件里。

rclone 的凭据写在运行时的配置文件里而不是命令行参数，因此进程表和日志里都不会出现。

新增被镜像的 bucket 时，把名字加到 `hosts/longred-vm/garage-backup.nix` 的 `buckets` 列表。

## 客户端配置

### 局域网内的 Fedora 主机

Fedora 上的 Nix 由发行版管理，daemon 配置在 `/etc/nix/nix.conf`。在 `nix.custom.conf` 里加：

```ini
trusted-users = root <user>
substituters = http://<host>:5000 https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:... <host>-cache-1:...
builders = ssh-ng://root@<host> x86_64-linux /root/.ssh/id_ed25519 8 1 big-parallel,kvm,nixos-test,benchmark
builders-use-substitutes = true
```

并确保 `!include nix.custom.conf` 出现在 `nix.conf` 里，然后重启 `nix-daemon`。

**本地缓存排在前面**：命中时完全不出网，未命中才回退到 `cache.nixos.org`。

**`builders-use-substitutes` 决定这次构建从哪里出网。** 为 `true` 时客户端**不下载输入**，改由
builder 从**它自己**的 substituter 取。于是 builder 的出口质量就是整条构建路径的质量：本 lab 实测
直连 `cache.nixos.org` 是 289 ms RTT、约 9 KB/s，经代理约 690 KB/s（约 25 倍）。更隐蔽的是，这些
字节**不会出现在客户端主机的代理里**——客户端的 `http_proxy` 只对它自己发起的请求有效，而在这个
模式下它根本不发请求。看到"构建很慢、代理里却一片安静"，先怀疑这里。

判断卡在哪一侧：

```bash
# 客户端：它与 builder 的 ssh-ng 连接
ss -tnp | grep nix-daemon
# builder：它自己的出口（连着境外 :443 且只有几 KB/s = builder 在慢慢拉）
ssh <builder> 'ss -tnp | grep -E "nix-daemon.*:443"'
```

选择：

- builder 出口正常（例如这台 guest 自带 mihomo 且 `networking.proxy` 指向它）→ 保留 `true`，
  输入只在 builder 上取一次，之后命中它自己的 store。
- builder 出口不好 → 设为 `false`，让客户端用它自己可用的代理取，再经 1 ms 局域网传给 builder。
- 不想改系统文件时的一次性覆盖：`NIX_CONFIG='builders-use-substitutes = false' just switch`。

### NUC（Determinate Nix）

NUC 上的 `/etc/nix/nix.conf` 由 Determinate 安装器管理并注明不要直接改
（"user modification can go in nix.custom.conf"），而该账号没有免密 sudo，所以仓库写不了它。
需要在 root 下执行：

```bash
printf 'trusted-users = root <user>\nbuilders = ssh-ng://root@<host> x86_64-linux /home/<user>/.ssh/id_ed25519 8 1 big-parallel,kvm,nixos-test,benchmark\nbuilders-use-substitutes = true\n' >> /etc/nix/nix.custom.conf
systemctl restart nix-daemon
```

> **不要把这些设置写进 `~/.config/nix/nix.conf`。** `substituters`、`trusted-public-keys` 与
> `builders` 都是受限设置，非受信用户会被忽略；更糟的是 `substituters` 会**替换**默认列表，
> 于是唯一那项又被丢弃，机器最终一个 substituter 都没有，开始从源码构建一切
> （表现是从 ftpmirror 拉 bash 补丁并 403 失败）。仓库里 `users/longred/nuc.nix` 特意什么都不写。

## 部署到这台机器

**不要从 NUC 走 tailnet 部署。** NUC 到这台机器只有中继链路，`nixos-rebuild` 会选到
`nix-copy-closure` 并在推送闭包时挂死（连接建立、两端零吞吐、客户机空闲）。实测 Tailscale SSH
本身的批量传输没问题，卡的是那条旧的拷贝路径。

可靠的做法是显式 build → copy → activate；从局域网内的机器执行最快：

```bash
# 在局域网内的机器上
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link --print-out-paths
nix copy --no-check-sigs --to "ssh-ng://dev@<host>?compress=true" <toplevel>
ssh dev@<host> "sudo nix-env -p /nix/var/nix/profiles/system --set <toplevel> && sudo <toplevel>/bin/switch-to-configuration switch"
```

`--no-check-sigs` 是必需的：目标机默认拒绝没有受信签名的路径，而本地构建出来的路径（
`firewall-reload`、单元脚本等）没有签名，只有来自 cache.nixos.org 的路径才有。

## 验证

```bash
# 缓存可达且签名
curl -s http://<host>:5000/nix-cache-info
curl -s "http://<host>:5000/$(basename <toplevel> | cut -d- -f1).narinfo" | grep ^Sig

# 缓存只在 tailnet 上（局域网应失败）
timeout 5 bash -c 'echo > /dev/tcp/<lan-ip>/5000' && echo unexpected || echo blocked

# 远程构建（客户端上，禁用本地构建以强制走远端）
nix build --impure --max-jobs 0 --expr 'derivation { name="t"; system="x86_64-linux"; builder="/bin/sh"; args=["-c" "echo ok > $out"]; }'

# 备份节点
sudo garage -c /nix/store/<...>-garage-backup.toml --admin-token-file /var/lib/garage/admin-token \
  --rpc-secret-file /var/lib/garage/rpc-secret bucket list
systemctl list-timers garage-backup-mirror
du -sh /var/lib/garage/data
```

判断标准要分开：单元 active 只说明进程在跑，`bucket list` 有内容才说明 layout 生效，
数据目录增长才说明镜像真的在搬数据。

## 已知限制

- **部署路径特殊**：见上文，走 tailnet 的 `nixos-rebuild` 会挂死。
- **镜像语义是 sync**：源端删除的对象在目标端也会被删。需要防误删的话改成 rclone `copy`，
  代价是已删除对象会一直堆积。
- **首次全量镜像慢**：1.6 GB 在 1.6 MB/s 的中继链路上约 17 分钟。
- **备份节点自身没有备份**：这台机器的磁盘是单盘、无冗余。
- **缓存与构建都依赖 tailnet ACL**：ACL 放开谁，谁就能用这个构建机和缓存。

## 权威源码与上游参考

| 主题 | 位置 |
| --- | --- |
| 主机定义 | `hosts/longred-vm/configuration.nix` |
| 磁盘布局 | `hosts/longred-vm/disko.nix` |
| Garage 备份节点 | `hosts/longred-vm/garage-backup.nix` |
| 用户定义 | `users/dev/default.nix`、`hosts/longred-vm/home.nix` |
| 签名密钥 | `secrets/nix-binary-cache-key.age` |
| 源侧只读凭据 | `secrets/garage-backup-read.age` |

上游参考：

- harmonia：<https://github.com/nix-community/harmonia>
- 分布式构建：<https://nix.dev/manual/nix/latest/advanced-topics/distributed-builds>
- 二进制缓存与签名：<https://nix.dev/manual/nix/latest/package-management/binary-cache>
- Garage：<https://garagehq.deuxfleurs.fr/documentation/>
- rclone：<https://rclone.org/s3/>
- disko：<https://github.com/nix-community/disko>
