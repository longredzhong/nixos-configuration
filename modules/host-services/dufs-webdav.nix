# dufs WebDAV/file server as HM user-level systemd service
# Serves /data/dufs with admin credentials from agenix secret.
{
  config,
  pkgs,
  ...
}:
{
  age.secrets.dufs-admin-credentials.file = ../../secrets/dufs-admin-credentials.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  systemd.user.services.dufs = {
    Unit = {
      Description = "DUFS WebDAV server serving /data/dufs";
      After = [ "agenix.service" ];
      Requires = [ "agenix.service" ];
    };
    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /data/dufs";
      # Shell wrapper so $(cat ...) resolves the password at runtime
      ExecStart = pkgs.writeShellScript "dufs-start" ''
        exec ${pkgs.dufs}/bin/dufs \
          -p 5000 \
          -A \
          -a "admin:$(cat ${config.age.secrets.dufs-admin-credentials.path})@/:rw" \
          /data/dufs
      '';
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
