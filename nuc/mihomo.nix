{ services
, pkgs
, ...
}: {
  services.mihomo = {
    enable = true;
    configFile = "/home/longred/configuration/mihomo.yaml";
    webui = pkgs.metacubexd;
  };
}
