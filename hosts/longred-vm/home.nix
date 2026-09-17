{ pkgs, inputs, username, hostname, ... }:
let
  hmOverlays = (import ../../modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
in
{
  home-manager.backupFileExtension = "backups";
  home-manager.extraSpecialArgs = { inherit hostname; };
  home-manager.users.${username} = {
    imports = [
      # CLI-only environment: this guest is a clean base, not a workstation.
      ../../modules/home-manager/profiles/minimal.nix
      # Host telemetry: host metrics and journald logs for OpenObserve. This is
      # imported here rather than in configuration.nix because the agent is a
      # user service, which is what lets it be the same module the Fedora hosts
      # use. The `dev` account is in `systemd-journal`, so it can read the
      # journal, and `linger` is set so it keeps exporting without a login.
      ../../modules/host-services/openobserve-agent.nix
      # The agent module declares an agenix secret conditionally; Home Manager
      # agenix has to be imported for those options to exist even though this
      # host declares no user secret (it reads the system one instead).
      inputs.agenix.homeManagerModules.default
    ];
    nixpkgs.overlays = hmOverlays;

    # The token is decrypted at system level in configuration.nix: a user
    # service cannot read the root-only host key that agenix would need as its
    # identity, so this host reads the already-decrypted file instead.
    hostServices.openobserveAgent = {
      secretFile = null;
      authHeaderFile = "/run/agenix/openobserve-agent-token";
    };

    home.packages = with pkgs; [
      git
      jq
    ];
  };
}
