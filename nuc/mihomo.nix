{ services
, pkgs
, ...
}:
let
  mihomo_config_file = pkgs.runCommand "mihomo-config.yaml" {} ''
    ${pkgs.curl}/bin/curl -L "https://proxy.longred.work/proxy/https://gist.githubusercontent.com/longredzhong/1a8655edb00bad16cfb6890904fef602/raw/mihomo-party.yaml" -o $out
  '';
in
{
  services.mihomo = {
    enable = true;
    configFile = mihomo_config_file;
    webui = pkgs.metacubexd;
    tunMode = false;
  };
}
