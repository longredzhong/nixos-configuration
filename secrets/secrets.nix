# 密钥定义和映射配置
{
  lib ? { },
}:
let
  # --- 公钥定义 ---
  publicKeys = {
    users = {
      # 用户密钥
      longred = {
        nuc = {
          type = "ssh-ed25519";
          key = "AAAAC3NzaC1lZDI1NTE5AAAAIBFpBt+r7xL1vyE1A2pUn72DEQy7wQ4hW6qhqYnZz2Fi";
          identityPath = "/home/longred/.ssh/id_ed25519";
        };
        fedora-thinkbook = {
          type = "ssh-ed25519";
          key = "AAAAC3NzaC1lZDI1NTE5AAAAICw0USk2+Qy2+RJjNTinq8R293JmEpKJT1FUIKn0GWTf";
          identityPath = "/home/longred/.ssh/id_ed25519";
        };
        metacube-wsl = {
          type = "ssh-ed25519";
          key = "AAAAC3NzaC1lZDI1NTE5AAAAIFjn1fjQIAWN6VGEWa6z9uIbJg9i4HN9F+cUJlJVnYB6";
          identityPath = "/home/longred/.ssh/id_ed25519";
        };
      };
    };

    hosts = {
      # 主机密钥
      nuc = {
        type = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIGuM7T6aOCr2MNS3Js7uP+t5rEpAjjxK4+SlAdGQueUv";
        identityPath = "/etc/ssh/ssh_host_ed25519_key";
      };
      fedora-thinkbook = {
        type = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIFrhflLIvpEW9r3AiH45tt93FBjyg+B8U4afJcUic2Nh";
        identityPath = "/etc/ssh/ssh_host_ed25519_key";
      };
      metacube-wsl = {
        type = "ssh-ed25519";
        key = "AAAAC3NzaC1lZDI1NTE5AAAAIPIRrBqrTEPFhywJcRB/PO1TzFJsyOgcKWb0nBloo7c1";
        identityPath = "/etc/ssh/ssh_host_ed25519_key";
      };
    };
  };

  # --- 密钥组定义 ---
  keyGroups = {
    allUsers = [
      publicKeys.users.longred.nuc
      publicKeys.users.longred.fedora-thinkbook
    ];
    allHosts = [
      publicKeys.hosts.nuc
      publicKeys.hosts.fedora-thinkbook
      publicKeys.hosts.metacube-wsl
    ];
    # 指定机器需要的密钥组
    nuc = [ publicKeys.hosts.nuc ];
    longred = [
      publicKeys.users.longred.nuc
      publicKeys.users.longred.fedora-thinkbook
    ];
  };

  # --- 分配密钥接收者 ---
  secretMappings = {
    "tmp.age" = {
      recipients = keyGroups.allUsers ++ keyGroups.allHosts;
      targetPath = "/tmp/tmp";
      owner = "longred";
      group = "users";
      mode = "600";
    };

    "minio-credentials.age" = {
      recipients = keyGroups.longred ++ keyGroups.nuc;
      owner = "root";
      group = "root";
      mode = "600";
    };

    "dufs-admin-credentials.age" = {
      recipients = keyGroups.longred ++ keyGroups.nuc;
      owner = "root";
      group = "dufs";
      mode = "640";
    };

    "cloudflare-tunnel-nuc.age" = {
      recipients = keyGroups.longred ++ keyGroups.nuc;
      owner = "root";
      group = "root";
      mode = "600";
    };

    "garage-rpc-secret.age" = {
      recipients = keyGroups.longred ++ keyGroups.nuc;
      owner = "longred";
      group = "users";
      mode = "600";
    };
  };

  # --- 辅助函数 ---
  keyToString = key: "${key.type} ${key.key}";

  recipientComment =
    secretName:
    let
      info = secretMappings.${secretName} or null;
      keys = if info == null then [ ] else info.recipients;

      # 查找密钥所属用户/主机
      findKeyOwner =
        k:
        let
          findUser = lib.concatMapStrings (
            u:
            lib.concatMapStrings (h: if publicKeys.users.${u}.${h} == k then "User '${u}@${h}'" else "") (
              lib.attrNames publicKeys.users.${u}
            )
          ) (lib.attrNames publicKeys.users);

          findHost = lib.concatMapStrings (h: if publicKeys.hosts.${h} == k then "Host '${h}'" else "") (
            lib.attrNames publicKeys.hosts
          );
        in
        if findUser != "" then
          findUser
        else if findHost != "" then
          findHost
        else
          "Unknown key";

      names = map findKeyOwner keys;
    in
    "# Recipients: ${lib.concatStringsSep ", " names}";

in
{
  # 输出数据供 agenix-config.nix 使用
  inherit publicKeys keyGroups secretMappings;

  # 获取指定主机应该有的私钥路径
  getIdentityPaths =
    hostname:
    let
      relevantSecrets = lib.filterAttrs (
        name: mapping:
        lib.any (key: key.identityPath != "" && key == publicKeys.hosts.${hostname}) mapping.recipients
      ) secretMappings;

      paths = lib.unique (
        lib.concatMap (mapping: lib.catAttrs "identityPath" mapping.recipients) (
          lib.attrValues relevantSecrets
        )
      );
    in
    paths;

  # 密钥组转换为公钥字符串
  groupToKeys = group: map keyToString group;

  # 获取接收者注释
  getRecipientComment = recipientComment;
}
