{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.custom;
in {
  options.custom = {
    isWsl = mkOption {
      type = types.bool;
      default = false;
      description = "是否在 WSL 环境中运行";
    };
    
    isHeadless = mkOption {
      type = types.bool;
      default = false;
      description = "是否为无图形界面环境";
    };
  };
}
