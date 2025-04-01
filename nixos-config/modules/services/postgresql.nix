{ config, lib, pkgs, ... }:

{
  options.services.postgresql.enable = lib.mkEnableOption "Enable PostgreSQL service";

  config = lib.mkIf config.services.postgresql.enable {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_17;
      enableTCPIP = true;
      settings.port = 5432;
      authentication = pkgs.lib.mkOverride 10 ''
        #type database  DBuser  auth-method
        local all       all     trust
        # ipv4
        host  all      all     127.0.0.1/32   trust
        # ipv6
        host all       all     ::1/128        trust
      '';
      extensions = [ pkgs.postgresql17Packages.pgvector ];
    };
  };
}
