# NixOS 模块，配置 agenix 密钥和解密路径
{ config, lib, pkgs, username, hostname ? "nuc", ... }:

let
  # 导入密钥和映射数据
  secretsInfo = import ./secrets.nix { inherit lib; };
  
  # 获取当前主机应使用的私钥路径
  hostIdentityPaths = secretsInfo.getIdentityPaths hostname;
  
  # 获取用户私钥路径
  userIdentityPaths = [
    "/home/${username}/.ssh/id_ed25519"
  ];
  
  # 动态生成密钥配置
  generateSecrets = let
    # 处理所有 .age 文件
    secretFiles = lib.filterAttrs (name: _: lib.hasSuffix ".age" name) 
                                  secretsInfo.secretMappings;
    
    # 将每个 .age 文件映射到 age.secrets.* 配置（关键修改：使用 mapAttrs' 并移除 .age 后缀）
    mkSecrets = lib.mapAttrs' (name: info: {
      # 去掉 .age 后缀作为属性名
      name = lib.removeSuffix ".age" name;
      value = {
        # ${secretsInfo.getRecipientComment name}
        file = ./. + "/${name}";
        owner = info.owner;
        group = info.group;
        mode = info.mode;
        path = info.targetPath;
      };
    }) secretFiles;
  in mkSecrets;

in {
  # 配置 agenix 模块
  age.identityPaths = hostIdentityPaths ++ userIdentityPaths;
  age.secrets = generateSecrets;
  
  # 确保配置的一致性 (在系统激活时检查)
  system.activationScripts.checkSecrets = ''
    echo "Verifying secret configurations..."
    # 这里可添加验证脚本
  '';
}