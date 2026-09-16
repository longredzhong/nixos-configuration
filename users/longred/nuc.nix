# Standalone Home Manager config for NUC (Fedora 44 host)
{
  pkgs,
  ...
}:
{
  imports = [
    ./common.nix
    # Full desktop profile: shell toolchain + desktop apps/fonts/input method
    ../../modules/home-manager/profiles/desktop.nix
    # Services running as HM user-level systemd units
    ../../modules/host-services/garage.nix
    ../../modules/host-services/openobserve.nix
    ../../modules/host-services/openobserve-agent.nix
    ../../modules/host-services/garage-ui.nix
    ../../modules/host-services/dufs-webdav.nix
    ../../modules/host-services/cloudflared.nix
    ../../modules/host-services/opencode.nix
    ../../modules/host-services/deepseek-harness.nix
    ../../modules/host-services/anytype.nix
    ../../modules/host-services/affine.nix
    ../../modules/host-services/tailscale-services.nix
    ../../modules/host-services/mihomo.nix
  ];

  # Local rule-based proxy with a dashboard and OpenObserve metrics. The
  # dashboard binds to the tailnet address; the metrics collector follows it.
  # The mixed port accepts LAN clients, but only from the tailnet and the
  # local host, so an untrusted LAN neighbour cannot use the proxy.
  hostServices.mihomo.enable = true;
  hostServices.mihomo.controllerHost = "100.100.10.1";
  hostServices.mihomo.allowLan = true;
  hostServices.mihomo.lanAllowedIps = [
    "127.0.0.0/8"
    "100.64.0.0/10"
  ];

  # Fedora NUC-specific packages
  home.packages =
    with pkgs;
    [
      garage_2
    ]
    ++ (with pkgs.unstable; [
      vivaldi
    ]);

  # Input method environment (system-side fcitx5 installed via dnf)
  home.sessionVariables = {
    XIM = "fcitx";
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    INPUT_METHOD = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };
}
