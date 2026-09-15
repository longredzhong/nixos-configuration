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

## 生成接收者

使用管理员实际持有的 age 公钥，或把受信 SSH 公钥转换成 age 公钥。命令输出中的公钥可以记录在本地密码管理器中；不要把私钥复制进仓库。

```bash
# 从 SSH 公钥转换为 age 公钥
ssh-to-age < ~/.ssh/id_ed25519.pub

# 生成专用 age 身份时，私钥只保存到受保护的本机路径
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
trap 'shred -u "$plain" "$encrypted"' EXIT

# 编辑 "$plain"，只在本机短时间存在
${EDITOR:-vi} "$plain"

age -r '<recipient-age-public-key>' \
  -o "$encrypted" "$plain"

# 经过接收者和目标路径复核后，替换仓库中的目标 .age 文件
cp "$encrypted" secrets/<secret-name>.age
```

如果一个机密需要多个身份，重复 `-r`，并在切换前验证每个目标身份都能解密。轮换时应先生成包含新旧接收者的文件、逐台部署并验证，再移除旧接收者；这样可以避免中途切换导致服务无法启动。

复制前检查：

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
