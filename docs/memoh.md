# Memoh

[返回项目文档索引](README.md) · [返回项目 README](../README.md)

[Memoh](https://github.com/felinics/Memoh) 是一个多智能体平台：每个 Agent 拥有一台自己的"云端电脑"（独立 workspace，含文件系统、桌面、浏览器、网络与长期记忆）。上游以 Docker Compose 分发，本仓库把它部署在 `longred-vm` 上。

## 为什么不在 NUC 上

这是本仓库里**唯一**引入 rootful 容器守护进程的服务，因此放在隔离的客户机上而不是承载数据的那台：

- 上游 compose 里 `server` 服务写死了 `privileged: true` 与 `pid: host`；
- 实测该容器内 `ps` 能看到 `agetty`、`cloudflared`、`tailscaled`、`containerd-shim` 等**宿主进程**，也就是说它具备宿主 root 的能力；
- 在 NUC 上这意味着它可以读取 `/run/user/1000/agenix/` 下**全部已解密机密**（Cloudflare 隧道 token、Garage admin token、ntfy 发布 token、二进制缓存签名私钥）以及整个 `/data`。

上游自己在 DEPLOYMENT.md 里写着「Main service has privileged container access — only run in trusted environments」。客户机上的爆炸半径小得多，而且它是 NixOS，整份部署可以进仓库。

## 声明式构成

| 部分 | 做法 |
| --- | --- |
| 上游源码 | `fetchFromGitHub` 固定在 revision `1aaef83f`，解包哈希写死在模块里。**不把上游文件拷进 git**：那个部署目录带 43 个 provider 定义，我们不该分叉它们 |
| `config.toml` | 每次启动从**上游自己的模板**生成，每条替换都断言出现次数，上游模板一变就会让单元直接失败而不是静默漂移 |
| 密钥 | 生成后经 `age -e -R` 加密为 `secrets/memoh-env.age`（接收者：本机主机密钥 + 管理员机器）；解密后同时充当 compose 的 `.env` 与模板替换的数据源 |
| 状态目录 | `/var/lib/memoh`，0700；`config.toml` 与 `.env` 都是 0600 |
| 启动 | systemd oneshot + `RemainAfterExit`，`ExecStartPre` 准备目录与配置，`ExecStart` 执行 `docker compose up -d` |

`docker-compose.local.yml` 是仓库自己的叠加层，负责三件事：把端口收回 loopback、替换 pgvector 镜像、补上上游遗漏的 `channel` 镜像。

## 上游与环境留下的四个坑

部署过程中撞到四处，都已修掉并写在模块注释里：

1. **上游的国内镜像 overlay 漏了 `channel` 服务。** 它只覆盖 `postgres`/`pgvector`/`migrate`/`server`/`web`，而 `channel` 是默认（非 profile）服务，于是仍指向 `registry-1.docker.io`。本客户机对该域名**完全不可达**（实测 `000`），启动会直接失败。
2. **`memoh.cn` 没有 pgvector 命名空间。** 它对 `library/*`、`memohai/*` 正常，但 `pgvector/pgvector` 的所有路径都返回 403。因此这一个镜像改从公共 Docker Hub 镜像站拉取，并按 **digest 固定**，避免内容被静默替换。该 digest 无法与 Docker Hub 官方值交叉核对——本客户机没有到 Docker Hub 的路由，这是这条链路上已知的信任缺口。
3. **NixOS 默认没有 `/etc/localtime`。** compose 把该路径 bind mount 进多个容器，路径不存在时 Docker（runc）会自行创建一个**空目录**，随后容器启动报 `not a directory: Are you trying to mount a directory onto a file`。模块因此在宿主上设置了 `time.timeZone`，让该路径真实存在。
4. **`WorkingDirectory` 必须早于单元存在。** systemd 在执行 `ExecStartPre` **之前**就 chdir，所以目录要靠 `systemd.tmpfiles.rules` 建立，写在准备脚本里已经太晚（会以 `status=200/CHDIR` 失败）。

## 暴露面

| 端口 | 绑定 | 用途 |
| --- | --- | --- |
| 8080 | `127.0.0.1` | 平台 API |
| 8082 | `127.0.0.1` | Web UI |
| 8443 | tailnet（`tailscale serve`） | Web UI 的对外入口 |

端口必须显式收回到 loopback：**Docker 会自行插入 iptables 规则，绕过 `networking.firewall`**，所以沿用上游的 `8080:8080` / `8082:8082` 会把管理界面直接发布到该客户机的实验室局域网口上。这里用 compose 的 `!override` 替换而不是追加端口列表。

Web UI 走 `tailscale serve --https=8443`：这条节点上 443 已经被 ntfy 占用，所以另开一个端口，仍然只对 tailnet 开放。

**未接线**：`1455` 与 WebRTC 的 UDP 30000 未发布，因此 Agent 桌面的远程串流尚不可用。

## 使用

管理员口令是生成后写入 `secrets/memoh-env.age` 的，可以在目标机上读出来（该文件仅 root 可读）：

```bash
sudo grep '^MEMOH_ADMIN_PASSWORD=' /run/agenix/memoh-env
```

登录入口是 `https://<host>.<tailnet>.ts.net:8443`，用户名 `admin`。**上游默认口令 `admin123` 已被替换并实测拒绝**——这一条务必在升级后复查，它决定了这个界面是不是对任何能访问 8443 的人敞开。

## 验证

```bash
# 单元与容器
systemctl is-active memoh
sudo docker compose --project-directory /var/lib/memoh \
  -f /var/lib/memoh/docker-compose.yml \
  -f /var/lib/memoh/docker-compose.cn.yml \
  -f /var/lib/memoh/docker-compose.local.yml ps   # 五个服务都应是 running (healthy)

# 迁移确实执行过（首次部署后应有数十张表）
sudo docker exec memoh-postgres psql -U memoh -d memoh -tAc \
  "select count(*) from information_schema.tables where table_schema=current_schema()"

# 登录：默认口令应 401，生成的口令应 200 并返回 access_token
sudo docker exec memoh-server ...   # 或从宿主直接打 127.0.0.1:8080/auth/login

# 工作区后端（嵌套 containerd）是否活着
sudo docker exec memoh-server ls /run/containerd/containerd.sock
```

> 登录路由是 `/auth/login`，不在 `/api/` 前缀下；`/api/*` 是需要 JWT 的另一套接口，用错前缀会得到 `missing or malformed jwt` 而不是凭据错误。

## 已知限制

- **Agent 工作区尚未端到端验证。** 已验证平台能启动、迁移完成、可登录，以及嵌套 containerd 存活；但真正拉起一个 Agent workspace 需要先在界面里配置模型 API Key，属于用户侧步骤。
- `server` 与 `web` 使用 `:latest` 标签，升级是手工动作，不是声明式的。
- 本仓库只有这一个服务使用 rootful Docker；其余服务一律走 rootless podman，两者互不影响，但排查时要分清。

## 权威源码与上游参考

- 权威来源：[`hosts/longred-vm/memoh.nix`](../hosts/longred-vm/memoh.nix)、[`secrets/memoh-env.age`](../secrets/memoh-env.age)
- [Memoh 仓库](https://github.com/felinics/Memoh)、[DEPLOYMENT.md](https://github.com/felinics/Memoh/blob/main/DEPLOYMENT.md)、[配置模板](https://github.com/felinics/Memoh/blob/main/conf/app.docker.toml)
