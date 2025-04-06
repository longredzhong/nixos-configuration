{ config, pkgs, ... }:

{
  # Ensure docker is enabled
  virtualisation.docker.enable = true;

  # Define a systemd service that wraps the docker run command
  systemd.services.deeplx = {
    description = "Deeplx service running via Docker";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      # Start the container mapping port 1188
      ExecStart = "${pkgs.docker}/bin/docker run --rm --name deeplx -p 1188:1188 ghcr.longred.work/owo-network/deeplx:latest";
      # Stop the container on service stop
      ExecStop = "${pkgs.docker}/bin/docker stop deeplx";
      Restart = "always";
    };
  };
}
