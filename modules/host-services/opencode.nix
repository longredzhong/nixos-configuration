# opencode headless server as an HM user-level systemd service (Fedora NUC)
# Binds 0.0.0.0:4096 so both localhost and Tailscale hosts can reach it.
# The opencode binary is provided by a pixi environment installed on the host.
{
  config,
  pkgs,
  ...
}:
let
  opencodeBin = "${config.home.homeDirectory}/.pixi/envs/opencode/bin/opencode";
in
{
  systemd.user.services.opencode = {
    Unit = {
      Description = "opencode headless server (port 4096)";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "opencode-start" ''
        exec ${opencodeBin} serve --hostname 0.0.0.0 --port 4096
      '';
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
