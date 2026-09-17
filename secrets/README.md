# Agenix 机密

[返回文档索引](../docs/README.md) · [返回项目 README](../README.md)

## 仓库规则

- `secrets/*.age` 是可提交的加密文件；文件名可以说明用途，但文件内容不能在仓库中解密。
- 明文机密、解密后的运行时文件、API key、密码、token、SSH 私钥和带凭据的 URL 不得提交。
- 加密文件的接收者是访问控制的一部分。修改接收者前，先确认所有仍需启动服务的目标都能解密。
- 服务模块通过 `config.age.secrets.<name>.path` 读取解密后的临时路径；不要把内容插入 Nix 表达式或 Nix store。

## 当前配置方式

这个 checkout 没有提交 `secrets/secrets.nix` 接收者清单。实际机密声明位于各服务模块的 `age.secrets` 属性中，身份路径由对应 Home Manager/NixOS 配置设置。因此旧版 `scripts/secretctl.py` 及 `just secret-*` 命令依赖的清单目前不是可用的仓库工作流；不要用示例公钥或虚构清单生成新机密。

新增或轮换机密前，先检查：

```bash
rg -n 'age\.secrets|age\.identityPaths' modules hosts users
git status --short
```

## 接收者格式：使用 SSH 公钥

本仓库的 `secrets/*.age` 全部是 **`ssh-ed25519` 接收者**，必须由 `age -e -R <ssh-公钥文件>` 生成。原因是 agenix 的 `age.identityPaths` 指向 **SSH 私钥**，而上游 `age` 只在接收者本身是 `ssh-ed25519` 时才会用 SSH 私钥解密。

当前使用的两个身份：

| 目标类型 | `age.identityPaths` | 用来加密的公钥 |
| --- | --- | --- |
| Home Manager（Fedora 等） | `${config.home.homeDirectory}/.ssh/id_ed25519` | `~/.ssh/id_ed25519.pub` |
| NixOS 主机 | `/etc/ssh/ssh_host_ed25519_key` | `/etc/ssh/ssh_host_ed25519_key.pub` |

对齐真实目标时，直接读它的 `age.identityPaths`：

```bash
rg -n 'age\.identityPaths' modules hosts users
```

### 不要用 `ssh-to-age` 生成这里的接收者

`ssh-to-age < ~/.ssh/id_ed25519.pub` 得到的是 `age1...` 形式的 X25519 公钥。把它交给 `age -r` 时，agenix 用 SSH 私钥解密会失败：

```text
age: error: no identity matched any of the recipients
```

需要专用 age 身份（非 SSH）时，才用 `age-keygen`，私钥只保存到受保护的本机路径：

```bash
age-keygen -o <private-key-path>
chmod 600 <private-key-path>
```

目标主机用于解密的私钥路径必须与 `age.identityPaths` 一致。不要为了方便把主机私钥或用户私钥复制到另一台机器。

## 创建或轮换加密文件

在仓库外创建临时明文，并在完成后删除：

```bash
set -eu
plain=$(mktemp)
encrypted=$(mktemp --suffix=.age)
recipients=$(mktemp)
trap 'shred -u "$plain" "$encrypted" "$recipients"' EXIT

# 接收者文件：每行一个 SSH 公钥，只列真正需要解密该机密的目标。
# 公钥本身不是机密，可以从各目标主机收集到本地。
#   Home Manager 目标：~/.ssh/id_ed25519.pub
#   NixOS 目标：/etc/ssh/ssh_host_ed25519_key.pub
cat <ssh-pubkey-1> <ssh-pubkey-2> > "$recipients"

# 编辑 "$plain"，只在本机短时间存在
${EDITOR:-vi} "$plain"

# -R 读取 SSH 公钥文件；不要用 -r，那会写出 agenix 解不开的文件
age -e -R "$recipients" -o "$encrypted" "$plain"

# 经过接收者和目标路径复核后，替换仓库中的目标 .age 文件
cp "$encrypted" secrets/<secret-name>.age
```

替换仓库文件前，先确认接收者格式正确（应输出 `ssh-ed25519`，出现 `X25519` 说明用错了 `-r`）：

```bash
grep -ao 'ssh-ed25519\|X25519' secrets/<secret-name>.age | sort -u
```

如果一个机密需要多个身份，把它们都写进接收者文件（或重复 `-R`），并在切换前验证每个目标身份都能解密：

```bash
age -d -i <identity-private-key> -o /dev/null secrets/<secret-name>.age
```

轮换时应先生成包含**新旧接收者**的文件、逐台部署并验证，再移除旧接收者；这样可以避免中途切换导致服务无法启动。

提交前检查：

```bash
git diff --check
git status --short
```

不要把临时文件放在仓库目录，也不要把 `age` 命令的完整参数、Shell 历史或错误输出发布到文档和 CI 日志。

## 在模块中使用

典型的 Home Manager 服务声明如下：

```nix
{
  age.secrets.example-token.file = ../../secrets/example-token.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  systemd.user.services.example = {
    Service = {
      Environment = "TOKEN_FILE=${config.age.secrets.example-token.path}";
    };
  };
}
```

NixOS 与 Home Manager 的差别不止身份路径：

- **NixOS** 的 agenix 在 activation 阶段解密，**不会**产生 `agenix.service`，服务不该声明对它的依赖。
- **Home Manager** 的 agenix 会生成 `agenix.service` 用户单元，而且只在确实有机密需要解密时才存在。

把一侧的 `Requires=agenix.service` 抄到另一侧会让服务起不来（`Unit agenix.service not found`）。另外，Home Manager 下 `config.age.secrets.<name>.path` 的字面量是 `${XDG_RUNTIME_DIR}/agenix/<name>`，取用时必须放在**双引号**里交给 shell 展开；单引号会让 `cat` 找不到文件。

服务启动后在目标主机上检查服务和解密错误：
```bash
systemctl --user --no-pager status <service>
journalctl --user -u <service> -n 100 --no-pager
```

日志中只能出现“文件缺失”或“权限错误”等不含机密值的诊断。若工具可能打印环境变量、请求头或命令行参数，应先关闭或过滤相关日志。

## 验证与恢复

```bash
just check-fast
just hm-dry-run '<user>@<host>'
just hm-switch '<user>@<host>'
```

发生解密失败时，按顺序检查目标主机的 identity path、文件接收者、文件权限和 Agenix unit；不要把明文机密提交来绕过错误。回滚应使用之前已验证的 `.age` 文件和 Home Manager generation。

## 参考资料

- [Agenix](https://github.com/ryantm/agenix)
- [age](https://github.com/FiloSottile/age)
- [NixOS Wiki: Agenix](https://wiki.nixos.org/wiki/Agenix)
