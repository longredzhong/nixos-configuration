# Agenix 密钥管理指南

本文档提供了使用 Agenix 管理密钥的完整指南，包括如何添加新密钥、更新现有密钥以及在 NixOS 配置中使用这些密钥。

## 目录结构

```
secrets/
├── ssh/              # SSH 相关密钥
│   ├── id_ed25519.age        # SSH 私钥
│   ├── id_ed25519.pub.age    # SSH 公钥
│   ├── config.age            # SSH 配置
│   └── known_hosts.age       # 已知主机
├── api_keys/         # API 密钥
│   ├── github_token.age      # GitHub 令牌
│   └── openai_api_key.age    # OpenAI API 密钥
└── passwords/        # 密码
    └── db_password.age       # 数据库密码
```

## 前提条件

1. 确保已安装 agenix 并在 flake.nix 中配置：

   ```nix
   # 在 flake.nix 中已配置:
   inputs.agenix.url = "github:ryantm/agenix";
   ```

2. 获取加密密钥所需的公钥（用户和系统）：

   ```bash
   # 获取当前用户公钥
   cat ~/.ssh/id_ed25519.pub
   
   # 获取系统公钥 (NixOS)
   cat /etc/ssh/ssh_host_ed25519_key.pub
   ```

## 添加新密钥

### 1. 更新 secrets.nix

首先在 `secrets.nix` 文件中定义新密钥及其访问权限：

```nix
"secrets/新路径/文件名.age".publicKeys = [可访问密钥的公钥列表];
```

例如，添加一个只有 longred 用户可访问的新 API 密钥：

```nix
"secrets/api_keys/new_service_token.age".publicKeys = [longred];
```

### 2. 创建加密文件

使用以下命令创建新的加密文件：

```bash
# 方法一：交互式创建（会打开编辑器）
nix run github:ryantm/agenix -- -e secrets/新路径/文件名.age

# 方法二：从明文文件创建
echo "密钥内容" > /tmp/temp_secret
nix run github:ryantm/agenix -- -e secrets/新路径/文件名.age -i /tmp/temp_secret
rm /tmp/temp_secret  # 安全清除临时文件
```

### 3. 在 NixOS 模块中使用密钥

创建或更新模块文件，配置密钥的使用方式：

```nix
{ config, pkgs, ... }:

{
  age.secrets.密钥别名 = {
    file = ../secrets/新路径/文件名.age;
    path = "/目标路径";  # 可选，指定解密后的文件路径
    owner = "拥有者";    # 可选，指定文件拥有者
    group = "用户组";    # 可选，指定文件用户组
    mode = "0600";       # 可选，指定文件权限
  };
}
```

## 更新现有密钥

### 1. 更新加密内容

使用以下命令更新现有加密文件：

```bash
# 交互式更新
nix run github:ryantm/agenix -- -e secrets/路径/文件名.age

# 从新的明文文件更新
echo "新密钥内容" > /tmp/new_secret
nix run github:ryantm/agenix -- -e secrets/路径/文件名.age -i /tmp/new_secret
rm /tmp/new_secret  # 安全清除临时文件
```

### 2. 重新部署系统

更新密钥后，重新部署系统以应用更改：

```bash
sudo nixos-rebuild switch --flake .#主机名
```

## SSH 密钥管理示例

### 添加 SSH 密钥

1. 生成新的 SSH 密钥对（如果需要）：

   ```bash
   ssh-keygen -t ed25519 -f /tmp/id_ed25519 -C "longred@example.com"
   ```

2. 加密 SSH 密钥：

   ```bash
   # 加密私钥
   nix run github:ryantm/agenix -- -e secrets/ssh/id_ed25519.age -i /tmp/id_ed25519
   
   # 加密公钥
   nix run github:ryantm/agenix -- -e secrets/ssh/id_ed25519.pub.age -i /tmp/id_ed25519.pub
   ```

3. 安全删除临时文件：

   ```bash
   rm /tmp/id_ed25519 /tmp/id_ed25519.pub
   ```

## 安全注意事项

1. **不要将未加密的密钥提交到版本控制系统**
2. **不要在不安全的位置临时存储密钥**
3. **确保 `secrets` 目录已添加到 `.gitignore`**
4. **定期更新敏感密钥**
5. **备份用于解密的私钥**

## 故障排除

### 无法解密密钥

如果遇到无法解密密钥的问题：

1. 确保密钥访问权限正确配置

   ```bash
   cat secrets.nix | grep 问题密钥
   ```

2. 确保拥有正确的私钥

   ```bash
   ls -la ~/.ssh/id_ed25519
   ```

3. 检查 agenix 是否正确配置

   ```bash
   nix run github:ryantm/agenix -- --help
   ```

### 密钥权限问题

如果遇到密钥权限问题：

1. 检查并修复模块中的权限设置

   ```nix
   mode = "0600";  # 对于私钥
   mode = "0644";  # 对于公钥和其他可共享文件
   ```

2. 确保设置了正确的所有者

   ```nix
   owner = "用户名";
   group = "用户组";
   ```
