{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];

  # 使用通用的 Linux 内核
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
  # 使用 GRUB 引导程序
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  
  # 使用简单的分区方案
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # 启用网络管理
  networking.networkmanager.enable = true;
  
  # 启用 SSH 服务以便远程访问
  services.openssh.enable = true;
}
