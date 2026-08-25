# Garage UI dashboard as a rootless Podman user service.
{
  config,
  pkgs,
  ...
}:
let
  garageUiImage = "docker.io/noooste/garage-ui:latest";
  garageUiSecretPath = config.age.secrets.garage-admin-token.path;
in
{
  age.secrets.garage-admin-token.file = ../../secrets/garage-admin-token.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  systemd.user.services.garage-ui = {
    Unit = {
      Description = "Garage UI dashboard";
      After = [ "agenix.service" "garage.service" ];
      Requires = [ "agenix.service" "garage.service" ];
    };
    Service = {
      ExecStartPre = "${pkgs.podman}/bin/podman rm -f garage-ui || true";
      ExecStart = pkgs.writeShellScript "garage-ui-start" ''
        exec ${pkgs.podman}/bin/podman run \
          --name garage-ui \
          --network host \
          --pull missing \
          --security-opt label=disable \
          --user 0:0 \
          --env GARAGE_UI_SERVER_HOST=100.100.10.1 \
          --env GARAGE_UI_SERVER_PORT=8080 \
          --env GARAGE_UI_GARAGE_ENDPOINT=http://127.0.0.1:3900 \
          --env GARAGE_UI_GARAGE_ADMIN_ENDPOINT=http://127.0.0.1:3903 \
          --env GARAGE_UI_GARAGE_ADMIN_TOKEN_FILE=/run/secrets/garage-admin-token \
          --volume ${garageUiSecretPath}:/run/secrets/garage-admin-token:ro \
          ${garageUiImage}
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 garage-ui";
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}