{
  config,
  pkgs,
  lib,
  hostname,
  username,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];
  networking.hostName = "${hostname}";
  # 基本系统配置
  system.stateVersion = "24.11";

  # 虚拟机特定设置
  virtualisation.vmVariant = {
    # 这些设置只在虚拟机模式下生效
    virtualisation.memorySize = 2048; # MB
    virtualisation.cores = 2;
    virtualisation.graphics = true;
  };

  # 启用 QEMU Guest Agent
  services.qemuGuest.enable = true;

  # 默认用户设置
  users.users.${hostname} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    password = "";
  };

  # 允许无密码sudo (测试环境)
  security.sudo.wheelNeedsPassword = false;

  # 安装基本工具
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
  ];
}
