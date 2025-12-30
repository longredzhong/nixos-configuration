{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.deeplx;
in
{
  options.services.deeplx = {
    enable = mkEnableOption "DeepLX service";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/owo-network/deeplx:latest";
      description = "Docker image to use for DeepLX.";
    };

    port = mkOption {
      type = types.port;
      default = 1188;
      description = "Port to expose DeepLX on the host.";
    };
  };

  config = mkIf cfg.enable {
    # Ensure Docker is enabled if you use the Docker backend (default)
    virtualisation.docker.enable = true;
    # Or enable podman if you prefer it
    # virtualisation.podman.enable = true;
    # virtualisation.podman.dockerCompat = true; # For compatibility if needed

    virtualisation.oci-containers = {
      backend = "docker";
      containers.deeplx = {
        image = cfg.image;
        ports = [
          "${toString cfg.port}:1188"
        ]; # Map host port to container port 1188
        environment = {
          # Add any environment variables needed for the container
          # e.g., "ENV_VAR_NAME" = "value";
          https_proxy = "http://127.0.1:7890";
        };
        # Optional: Add extra arguments if needed, e.g., environment variables
        # extraOptions = [ "--env" "SOME_VAR=value" ];
        # Optional: Set restart policy
        # autoStart = true; # Already implied by systemd service
        # extraOptions = [ "--restart=always" ]; # Handled by systemd service usually
      };
    };

    # The oci-containers module automatically creates a systemd service
    # named `oci-container-deeplx.service`.
    # You can manage it using: systemctl start/stop/status oci-container-deeplx.service
  };
}
