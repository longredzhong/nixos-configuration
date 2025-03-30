{ config, lib, pkgs, secrets, ... }:

{
  environment.systemPackages = [ pkgs.dufs ];
  users.users.dufs = {
    group = "dufs";
    isSystemUser = true;
  };
  users.groups.dufs = { };
  systemd.services.dufs = {
    description = "DUFS Service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.dufs}/bin/dufs -A -p 5000 -a ${secrets.minio.accessKey}:${secrets.minio.secretKey}@/:rw /var/lib/dufs";
      Restart = "always";
      RestartSec = "10s";
      User = "dufs";  # Added User directive
      Group = "dufs"; # Added Group directive
    };
  };
}