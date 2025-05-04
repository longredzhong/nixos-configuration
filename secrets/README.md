# 使用 Agenix 管理机密

本指南演示如何在本仓库中使用 [Agenix](https://github.com/ryantm/agenix) 对敏感信息（SSH 密钥、API Token 等）进行加密管理，并由 NixOS 在系统激活时自动解密。这遵循了 NixOS 凭据管理的基本原则，即将加密后的凭据存入仓库，在目标主机上使用其特有的密钥解密。

---

## 1. 前置条件

- `flake.nix` 已包含 agenix 输入：
  
  - 在 [`flake.nix`](../flake.nix) 中：
    ```nix
    inputs = {
      # ... other inputs
      agenix.url = "github:ryantm/agenix";
      agenix.inputs.nixpkgs.follows = "nixpkgs";
      # ... other inputs
    };
    ```
- 各主机的 NixOS 模块已导入 `inputs.agenix.nixosModules.default`：
  
  ```nix
  # 例如在 hosts/nuc/nixos.nix 中
  imports = [
    # ... other imports
    inputs.agenix.nixosModules.default
    ../../secrets/secrets.nix # 导入 secrets 定义文件
    # ... other imports
  ];
  ```
- 已安装 `age` 命令行工具 (`pkgs.age`).

---

## 2. 理解密钥角色与生成

参考 [NixOS 不见光凭据管理综述](https://blog.nyaw.xyz/nixos-secret-management-introduction)，凭据管理通常涉及两种身份：

*   **Per Host Identity (主机身份):** 每个目标主机用于**解密**其凭据的密钥。Agenix 通常使用目标主机的 SSH 私钥 (如 `/etc/ssh/ssh_host_ed25519_key`) 作为此身份。这是在 NixOS 激活期间实际用于解密的密钥。
*   **Admin Identity (管理员身份):** 管理员用于**加密**凭据的密钥。这可以是管理员个人的 SSH 密钥或专门生成的 age 密钥。此密钥的公钥部分 (`age1...`) 在运行 `age -r ...` 命令时指定接收者。

**密钥管理与 `secrets/secrets.nix`:**

为了集中管理和记录用于加密的公钥，我们在 [`secrets.nix`](./secrets.nix) 文件顶部的 `let` 块中定义它们。

*   **定义公钥:** 该 `let` 块包含用户和主机的 SSH 公钥及其对应的 `age` 公钥 (`age1...` 格式)。**你需要手动使用 `ssh-to-age` 获取这些 `age` 公钥并填入 `secrets.nix`**。
*   **记录接收者:** `let` 块中的 `secretRecipients` 属性集记录了每个 `.age` 文件预期应该使用哪些 `age` 公钥进行加密。这主要用于**文档记录和参考**。
*   **加密时使用:** 在执行 `age -r ...` 加密命令时，你应该从 `secrets.nix` 的 `let` 块中复制所需的 `age` 公钥字符串。

**选择/生成用于 Agenix 的密钥:**

**主机密钥 (Per Host Identity - 用于解密):**

*   **选项 1: 使用现有的 SSH 主机密钥 (推荐)**
    *   **私钥文件路径 (用于 `age.identityPaths`):** 通常是 `/etc/ssh/ssh_host_ed25519_key` 或 `/etc/ssh/ssh_host_rsa_key`。此文件**已存在**于目标主机上，**无需**也**不应**复制到配置仓库或手动管理。
    *   **对应公钥 (用于加密):** 你需要获取此私钥对应的 `age1...` 格式的公钥，以便在加密时指定此主机为接收者。在目标主机上执行：
        ```bash
        # 在目标主机上执行 (例如 nuc)
        sudo cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
        # 记下输出的 age1... 公钥，并将其更新到 secrets.nix 的 let 块中对应主机的 _age 变量
        ```
        *(需要安装 `ssh-to-age` 工具, 例如 `nix-shell -p ssh-to-age --run '...'`)*

*   **选项 2: 生成专用的 age 主机密钥 (较少用)**
    *   如果你不想使用 SSH 主机密钥，可以在每个主机上生成专用密钥：
        ```bash
        # 在目标主机上执行
        sudo age-keygen -o /etc/ssh/agenix_host_key.txt
        sudo chmod 600 /etc/ssh/agenix_host_key.txt
        sudo chown root:root /etc/ssh/agenix_host_key.txt
        # 记下文件注释中的 age1... 公钥 (用于加密)
        # 将 /etc/ssh/agenix_host_key.txt 添加到 secrets.nix 的 age.identityPaths
        ```
    *   **注意:** 这种方式需要你在每个主机上手动生成和管理密钥文件。

**用户/管理员密钥 (Admin Identity - 主要用于加密):**

*   **选项 1: 使用现有的用户 SSH 密钥 (推荐)**
    *   **私钥文件路径 (可用于 `age.identityPaths` 以解密用户级机密):** 通常是 `~/.ssh/id_ed25519` 或 `~/.ssh/id_rsa`。
    *   **对应公钥 (用于加密):** 获取此私钥对应的 `age1...` 公钥：
        ```bash
        # 在你的管理机器上执行
        cat ~/.ssh/id_ed25519.pub | ssh-to-age
        # 记下输出的 age1... 公钥，并将其更新到 secrets.nix 的 let 块中对应用户的 _age 变量
        ```

*   **选项 2: 生成专用的 age 管理员密钥**
    *   ```bash
        # 在你的管理机器上执行
        age-keygen -o ~/.ssh/admin_agenix_key.txt
        chmod 600 ~/.ssh/admin_agenix_key.txt
        # 记下文件注释中的 age1... 公钥 (用于加密)
        # 如果需要用此密钥解密 (例如 CI/CD)，需将私钥文件路径加入 age.identityPaths
        ```

**总结:**

*   `age.identityPaths` 列出的是目标主机上用于**解密**的**私钥**文件路径。
*   `secrets.nix` 文件顶部的 `let` 块定义了用于**加密**的**公钥** (`age1...`)，并记录了每个秘密文件的预期接收者。
*   `age -r <公钥>` 命令中的 `<公钥>` (从 `secrets.nix` 的 `let` 块获取) 指定了哪些身份能够解密该文件，这是实现访问控制的关键。

---

## 3. 编写和加密机密文件

1.  在 `secrets/` 目录下创建包含敏感信息的明文文件。
2.  **查阅 `secrets.nix` 的 `let` 块** 找到目标接收者对应的 `age` 公钥 (`age1...` 字符串)。
3.  使用 `age` 工具和从 `secrets.nix` 获取的**目标接收者的公钥**对其加密。

    ```bash
    # --- 加密示例 (使用 secrets.nix let 块中的公钥) ---

    # 假设 secrets.nix 的 let 块中定义了:
    # host_nuc_age = "age1nuc..."
    # user_longred_age = "age1longred..."
    # host_thinkbook_age = "age1thinkbook..."

    # 手动从 secrets.nix 复制公钥值
    NUC_HOST_PUBKEY="age1nuc..."      # Replace with actual key from secrets.nix
    USER_LONGRED_PUBKEY="age1longred..."  # Replace with actual key from secrets.nix
    THINKBOOK_HOST_PUBKEY="age1thinkbook..." # Replace with actual key from secrets.nix

    # 加密文件，仅允许 nuc 主机解密 (对应 secrets.nix 中 "nuc-only-secret.age" 的定义)
    age -r "${NUC_HOST_PUBKEY}" \
        -o secrets/nuc-only-secret.age secrets/nuc-only-secret

    # 加密文件，允许 nuc 主机 和 用户 longred 解密 (对应 "shared-nuc-user-secret.age")
    age -r "${NUC_HOST_PUBKEY}" -r "${USER_LONGRED_PUBKEY}" \
        -o secrets/shared-nuc-user-secret.age secrets/shared-nuc-user-secret

    # 加密文件，允许所有相关主机和用户解密 (对应 "global-secret.age")
    # (需要构建包含所有公钥的列表)
    ALL_PUBKEYS="${NUC_HOST_PUBKEY} ${THINKBOOK_HOST_PUBKEY} ${USER_LONGRED_PUBKEY}"
    age $(echo "$ALL_PUBKEYS" | sed 's/ /\n/g' | sed 's/^/-r /') \
        -o secrets/global-secret.age secrets/global-secret

    # 只加密给用户 longred (对应 "user-api-token.age")
    age -r "${USER_LONGRED_PUBKEY}" \
        -o secrets/user-api-token.age secrets/user-api-token
    ```
    *   **关键:** 确保 `-r` 参数使用的公钥与 `secrets.nix` 中为该秘密文件记录的预期接收者一致。
    *   加密后的 `.age` 文件可以安全地提交到 Git。

4.  **删除明文文件**。

---

## 4. 更新 `secrets/secrets.nix`

编辑 [`secrets.nix`](./secrets.nix)，定义所有 `.age` 文件，并在文件顶部的 `let` 块中维护公钥定义和接收者映射。指定**所有可能**在目标主机上用于**解密**的**私钥**文件路径 (`age.identityPaths`)。通过注释引用 `let` 块中的信息，可以清晰地表明每个秘密文件的预期接收者。

**注意:**

*   `age.identityPaths` 列出的是**解密**时使用的私钥文件路径 (Per Host/User Identities)。Agenix 会在目标主机上查找这些文件，并尝试用它们解密 `age.secrets` 中定义的每个文件。
*   一个主机能否成功解密某个特定的 `.age` 文件，取决于该文件在**加密时**是否包含了该主机对应私钥的公钥。
*   这与 `sops-nix` 的某些模式不同，Agenix 没有内置的 "rekey" 步骤。加密时指定接收者公钥即完成了访问控制。

```nix
/* filepath: secrets/secrets.nix */
{ config, lib, pkgs, username, ... }:
let
  # --- Key Definitions ---
  # NOTE: Replace placeholder "age1..." keys with actual keys!
  user_longred_age = "age1...";
  host_nuc_age = "age1...";
  # ... other key definitions ...

  definedUsers = { longred = user_longred_age; };
  definedHosts = { nuc = host_nuc_age; /* ... */ };
  allUsers = [ user_longred_age ];
  allHosts = [ host_nuc_age /* ... */ ];

  # --- Secret Recipient Mapping (Documentation) ---
  secretRecipients = {
    "tmp.age" = [ user_longred_age host_nuc_age ];
    "nuc-db-password.age" = [ host_nuc_age ];
    # ... other mappings ...
  };

  # Helper function to generate comments (optional, for consistency)
  intendedRecipientsComment = secretFileName:
    let
      keys = secretRecipients.${secretFileName} or [ "ERROR: No recipients defined in this file" ];
      # Find names associated with keys (simple reverse lookup for comments)
      findName = key:
        let
          userNames = lib.attrNames (lib.filterAttrs (n: v: v == key) definedUsers);
          hostNames = lib.attrNames (lib.attrNames (lib.filterAttrs (n: v: v == key) definedHosts));
        in if (userNames != []) then "User '${builtins.elemAt userNames 0}'"
           else if (hostNames != []) then "Host '${builtins.elemAt hostNames 0}'"
           else "Unknown Key";
      recipientNames = lib.concatStringsSep ", " (map findName keys);
    in "# Intended Recipients: ${recipientNames}";

in
{
  # 指定目标主机上用于解密的私钥文件路径 (Per Host/User Identities)。
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/home/${username}/.ssh/id_ed25519"
    # ... other identity paths ...
  ];

  # --- Secret Definitions ---
  # Comments reference intended recipients defined in the `let` block above.

  # Example using the existing tmp.age
  age.secrets."test" = {
    # ${intendedRecipientsComment "tmp.age"}
    file = ./tmp.age;
    owner = config.users.users.${username}.name;
    group = config.users.users.${username}.group;
    mode = "600";
    path = "/home/${username}/test";
  };

  # Example: Secret only for 'nuc' host's host key
  age.secrets."nuc-db-password" = {
    # ${intendedRecipientsComment "nuc-db-password.age"}
    file = ./nuc-db-password.age;
    owner = "postgres";
    group = "postgres";
    mode = "400";
  };

  # --- Organization Tip ---
  # For larger configurations, consider splitting secrets into multiple files:
  # imports = [
  #   ./secrets-nuc.nix
  #   ./secrets-webserver.nix
  #   ./secrets-users.nix
  # ];
  # Then define age.secrets within each imported file. NixOS will merge them.
}
```

---

## 5. 在 NixOS 配置中使用机密

根据机密的预期用途，在 NixOS 模块或 Home Manager 配置中引用解密后文件的路径 `config.age.secrets.<secret_name>.path`。

```nix
# 在 hosts/nuc/nixos.nix 或其他 NixOS 模块中
{ config, pkgs, username, ... }: {
  imports = [
    # ... other imports
    inputs.agenix.nixosModules.default
    ../../secrets/secrets.nix # 确保导入了 secrets 定义
  ];

  # 示例：系统服务 (Nginx)
  services.nginx.virtualHosts."example.com" = {
    # ... other config
    sslCertificateKey = config.age.secrets."nginx-cert-key".path;
  };

  # 示例：Nextcloud 管理员密码文件
  # services.nextcloud = {
  #   enable = true;
  #   # ... other config
  #   config.adminpassFile = config.age.secrets.nextcloud-admin-pass.path;
  # };

  # 示例：替换配置文件中的占位符 (适用于不支持从文件读取密码的模块)
  # systemd.services.my-app = {
  #   # ...
  #   serviceConfig.ExecStart = "/path/to/my-app --config /run/my-app/config.yaml";
  # };
  # system.activationScripts."my-app-secret" = ''
  #   # Create config with placeholder
  #   mkdir -p /run/my-app
  #   echo "password: @PASSWORD@" > /run/my-app/config.yaml
  #   # Read secret and replace placeholder
  #   secret=$(cat "${config.age.secrets.my-app-password.path}")
  #   ${pkgs.gnused}/bin/sed -i "s#@PASSWORD@#$secret#" /run/my-app/config.yaml
  #   chown my-app-user:my-app-group /run/my-app/config.yaml
  # '';

  # 示例：将解密文件部署到特定路径 (如 .netrc)
  # age.secrets.netrc = {
  #   file = ./netrc.age;
  #   path = "/home/${username}/.netrc"; # Deploy directly to user home (requires correct owner/group)
  #   owner = username;
  #   group = "users"; # Or config.users.users.${username}.group
  #   mode = "600";
  # };
}

# 在 home-manager/home.nix 或相关模块中
# { config, pkgs, username, ... }: {
#   # 假设 config.age.secrets."user-api-token".path 可用
#   # 方法1: 使用 home.file (创建链接或复制)
#   home.file.".config/my-app/token" = {
#     source = config.age.secrets."user-api-token".path;
#     mode = "600";
#   };
#
#   # 方法2: 某些程序可以直接配置路径
#   # programs.some-app = {
#   #   enable = true;
#   #   tokenFile = config.age.secrets."user-api-token".path;
#   # };
# }
```

---

## 6. 工具命令汇总

- `age-keygen -o key_file`：生成新的 age 密钥对 (文件包含私钥和公钥)。
- `age -r <recipient_age_public_key> -o <output.age> <input>`：使用指定 age 公钥 (`age1...`) 加密文件。
- `age -r <pubkey1> -r <pubkey2> ... -o <output.age> <input>`：使用多个 age 公钥 (`age1...`) 加密文件。
- `age --decrypt -i <private_key_file> <input.age>`：手动解密文件（主要用于测试）。
- `just fmt`：格式化所有 Nix 文件。
- `just switch` / `just build`：重新构建并应用配置（触发 Agenix 解密）。
- `ssh-to-age` (需要 `nix-shell -p ssh-to-age --run '...'`): 从 SSH 公钥获取 age 公钥 (`age1...`)。

---

## 7. 小贴士

*   **身份分离:** 理解用于**加密**的公钥 (`age -r <pubkey>`) 和用于**解密**的私钥 (`age.identityPaths`) 的区别。加密时选择正确的公钥是实现主机/用户限制的关键。
*   **SSH 密钥优先:** 优先使用目标主机的 `/etc/ssh/ssh_host_ed25519_key` 作为解密身份 (Per Host Identity)，并使用 `ssh-to-age` 获取其对应公钥用于加密。
*   **私钥安全:** 确保 `age.identityPaths` 中列出的私钥文件安全地存放在**目标主机**上，并且**不要**将任何私钥文件提交到 Git 仓库。
*   **公钥获取:** 使用 `ssh-to-age` 从 `.pub` 文件可靠地获取 `age1...` 格式的公钥。
*   **CI/CD:** 如果在 CI/CD 环境中构建或部署，需要确保该环境能够访问**用于解密**的私钥 (如果构建过程需要解密) 或确保目标主机拥有正确的私钥 (如果解密发生在目标主机激活时，这是 Agenix 的标准模式)。
*   **`secrets.nix` 的 `let` 块:** 将 `secrets.nix` 文件顶部的 `let` 块视为加密公钥的数据库和秘密文件预期接收者的文档。确保在加密时使用此块中定义的正确公钥。

---

完成上述步骤后，您的机密文件在 Git 仓库中将保持加密状态，系统激活时会自动解密并按配置注入到系统中。