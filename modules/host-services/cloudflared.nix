# Cloudflare Tunnel for Fedora NUC user-level services.
{
  config,
  pkgs,
  ...
}:
let
  tunnelToken = config.age.secrets.cloudflare-tunnel-nuc.path;
  cloudflaredConfig = "${config.xdg.configHome}/cloudflared/config.yml";

  # ExecStart names this store path so a config-only change changes the systemd
  # unit and Home Manager's sd-switch restarts cloudflared. The stable ~/.config
  # path remains as a human-readable symlink.
  cloudflaredConfigFile = pkgs.writeText "cloudflared-config.yml" ''
    ingress:
      - hostname: s3-alex.longred.work
        service: http://127.0.0.1:3900
      - hostname: webdav-alex.longred.work
        service: http://127.0.0.1:5000
      - service: http_status:404
  '';
in
{
  age.secrets.cloudflare-tunnel-nuc.file = ../../secrets/cloudflare-tunnel-nuc.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  home.file."${cloudflaredConfig}".source = cloudflaredConfigFile;

  systemd.user.services.cloudflared = {
    Unit = {
      Description = "Cloudflare Tunnel for NUC services";
      After = [ "agenix.service" "garage.service" "dufs.service" ];
      Requires = [ "agenix.service" "garage.service" "dufs.service" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "cloudflared-start" ''
        exec ${pkgs.cloudflared}/bin/cloudflared tunnel \
          --config ${cloudflaredConfigFile} \
          run \
          --token-file "${tunnelToken}"
      '';
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
