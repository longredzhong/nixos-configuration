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
    ../../modules/host-services/affine.nix
    ../../modules/host-services/tailscale-services.nix
    ../../modules/host-services/mihomo.nix
    ../../modules/host-services/homelab-portal.nix
  ];

  # Read-only portal listing the services on this host, how to reach them, and
  # their live state. It binds to the Tailscale address only and is published
  # as the svc:portal Tailscale Service.
  hostServices.homelabPortal.enable = true;

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

  # longred-vm is the home lab's Nix remote builder and signed binary cache,
  # but this host cannot be pointed at it from this repository.
  #
  # The settings that matter (`substituters`, `trusted-public-keys`, `builders`)
  # are restricted: Nix ignores them for an untrusted user. They therefore have
  # to go in the daemon's own configuration, and the NUC runs Determinate Nix
  # whose /etc/nix/nix.conf is root-owned and says to use nix.custom.conf — a
  # file this repository cannot write (the account has no passwordless sudo).
  #
  # Worse, putting `substituters` in ~/.config/nix/nix.conf is actively harmful:
  # the value replaces the default list, and then the single untrusted entry is
  # dropped, leaving the machine with no substituter at all and building
  # everything from source. So nothing is written here on purpose.
  #
  # Apply it by hand as root (see docs/nix-build-cache.md):
  #
  #   printf 'trusted-users = root longred\nbuilders = ssh-ng://root@longred-vm x86_64-linux /home/longred/.ssh/id_ed25519 8 1 big-parallel,kvm,nixos-test,benchmark\nbuilders-use-substitutes = true\n' >> /etc/nix/nix.custom.conf
  #   systemctl restart nix-daemon

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
