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
    
    development = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "是否启用开发环境配置";
      };
      
      languages = mkOption {
        type = types.listOf types.str;
        default = [ "nix" ];
        description = "要启用的开发语言";
      };
    };
  };
}
