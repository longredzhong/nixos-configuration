# Garage S3-compatible object storage as HM user-level systemd service
# Runs on Fedora host (NUC). Data lives on /data (1.8T btrfs data disk).
{
  config,
  pkgs,
  lib,
  ...
}:
let
  garageDataDir = "/data/garage/data";
  garageMetaDir = "/data/garage/meta";
  garageCfgDir = "${config.xdg.configHome}/garage";
in
{
  # RPC secret shared by cluster nodes (single node here), decrypted via agenix
  age.secrets.garage-rpc-secret.file = ../../secrets/garage-rpc-secret.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  home.file."${garageCfgDir}/garage.toml".text = ''
    metadata_dir = "${garageMetaDir}"
    data_dir = "${garageDataDir}"

    db_engine = "lmdb"
    replication_factor = 1

    rpc_bind_addr = "[::]:3901"
    rpc_public_addr = "127.0.0.1:3901"
    rpc_secret_file = "${config.age.secrets.garage-rpc-secret.path}"

    [s3_api]
    api_bind_addr = "[::]:3900"
    s3_region = "garage"

    [s3_web]
    bind_addr = "[::]:3902"
    root_domain = ".web.garage"

    [admin]
    api_bind_addr = "127.0.0.1:3903"
  '';

  systemd.user.services.garage = {
    Unit = {
      Description = "Garage S3-compatible object storage server";
      After = [ "agenix.service" ];
      Requires = [ "agenix.service" ];
    };
    Service = {
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p ${garageDataDir} ${garageMetaDir}"
      ];
      ExecStart = "${pkgs.garage}/bin/garage -c ${garageCfgDir}/garage.toml server";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
