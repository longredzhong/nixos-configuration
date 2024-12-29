{ services
, pkgs
, ...
}: {
  services.mihomo = {
    enable = true;
    configFile = fetchurl {
      url = "https://proxy.longred.work/proxy/https://gist.githubusercontent.com/longredzhong/1a8655edb00bad16cfb6890904fef602/raw/mihomo-party.yaml";
    };
    webui = pkgs.metacubexd;
  };
}
