{
  config,
  lib,
  pkgs,
  secrets,
  ...
}:

with lib;

let
  cfg = config.services.dufs;

  # 拼接完整的 dufs 命令行（包含 exec 以接管 PID 1）
  dufsCmd = ''
    ${cfg.package}/bin/dufs \
      -p ${toString cfg.port} \
      ${if cfg.allowAll then "-A" else ""} \
      ${
        lib.concatMapStringsSep " " (
          auth: "-a " + auth.credentials + "@" + auth.path + ":" + auth.permissions
        ) cfg.auth
      } \
      ${lib.concatStringsSep " " cfg.extraArgs} \
      ${cfg.servePath}
  '';
in
{
  options.services.dufs = {
    enable = mkEnableOption "dufs - A file server that supports static serving, uploading, searching, accessing control, webdav...";

    package = mkOption {
      type = types.package;
      default = pkgs.dufs;
      defaultText = literalExpression "pkgs.dufs";
      description = "The dufs package to use.";
    };

    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Port number dufs will listen on.";
    };

    user = mkOption {
      type = types.str;
      default = "dufs";
      description = "User to run dufs as.";
    };

    group = mkOption {
      type = types.str;
      default = "dufs";
      description = "Group to run dufs as.";
    };

    servePath = mkOption {
      type = types.path;
      default = "/var/lib/dufs";
      description = "The path to the directory to serve.";
    };

    allowAll = mkOption {
      type = types.bool;
      default = true;
      description = "Allow all operations (read, write, search). Corresponds to the -A flag.";
    };

    auth = mkOption {
      type =
        with types;
        listOf (submodule {
          options = {
            credentials = mkOption {
              type = str;
              description = "Credentials in the format 'username:password' or just 'token'.";
              example = "user:pass";
            };
            path = mkOption {
              type = str;
              default = "/";
              description = "Path prefix for which the authentication applies.";
              example = "/private";
            };
            permissions = mkOption {
              type = enum [
                "r"
                "rw"
              ];
              default = "rw";
              description = "Permissions for the authenticated user ('r' for read, 'rw' for read-write).";
            };
          };
        });
      default = [ ];
      example = literalExpression ''
        [
          { credentials = "admin:\${secrets.dufs.adminPassword}"; path = "/"; permissions = "rw"; }
          { credentials = "\${secrets.dufs.readToken}"; path = "/public"; permissions = "r"; }
        ]
      '';
      description = ''
        List of authentication rules. Each rule specifies credentials,
        an optional path prefix, and permissions.
        Use secrets management (like sops-nix) for passwords/tokens.
      '';
    };

    extraArgs = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "Extra command line arguments passed to dufs.";
      example = [ "--enable-cors" ];
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the firewall port for dufs.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.servePath; # Set home to servePath for consistency
      createHome = false; # Let tmpfiles create it
    };
    users.groups.${cfg.group} = { };

    # Ensure the serve path exists and has correct permissions
    systemd.tmpfiles.rules = [ "d ${cfg.servePath} 0750 ${cfg.user} ${cfg.group} - -" ];

    systemd.services.dufs = {
      description = "DUFS Service serving ${cfg.servePath}";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        RestartSec = "10s";
        WorkingDirectory = cfg.servePath;
      };

      # 将 dufsCmd 写入单独脚本，避免引号嵌套问题
      # 注意：shebang 必须从文件第一列开始，前面不能有空格
      script = ''
        set -euo pipefail
        ${dufsCmd}
      '';
    };

    # Open the firewall port if configured
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
