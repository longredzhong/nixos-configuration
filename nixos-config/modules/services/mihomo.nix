{ services
, pkgs
, ...
}:
let
  mihomo_config_file = pkgs.fetchurl {
    url = "https://gist.githubusercontent.com/longredzhong/1a8655edb00bad16cfb6890904fef602/raw/7524eeae2d0989e8f8816e24b8855009f538349c/mihomo-party.yaml";
    # You'll need to add a sha256 hash. You can get it with:
    # nix-prefetch-url https://gist.githubusercontent.com/longredzhong/1a8655edb00bad16cfb6890904fef602/raw/7524eeae2d0989e8f8816e24b8855009f538349c/mihomo-party.yaml
    sha256 = "0nabmkzbv3m6dvrvp94iq4zj2lw69cwz9x3yx7whvyr5jzmnka1p"; # Replace with actual hash
  };
in
{
  services.mihomo = {
    enable = true;
    configFile = mihomo_config_file;
    webui = pkgs.metacubexd;
    tunMode = false;
  };
}
