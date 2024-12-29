{ services
, pkgs
, ...
}: 
let
  mihomo_config = pkgs.fetchurl {
    url = "https://proxy.longred.work/proxy/https://gist.githubusercontent.com/longredzhong/1a8655edb00bad16cfb6890904fef602/raw/mihomo-party.yaml";
  };
in {
  services.mihomo = {
    enable = true;
    configFile = mihomo_config;
    webui = pkgs.metacubexd;
  };
}
