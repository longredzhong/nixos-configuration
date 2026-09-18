# Standalone Home Manager config for NUC (Fedora 44 host)
{
  pkgs,
  config,
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
    ../../modules/host-services/deepseek-harness-acp.nix
    ../../modules/host-services/affine.nix
    ../../modules/host-services/tailscale-services.nix
    ../../modules/host-services/mihomo.nix
    ../../modules/host-services/homelab-portal.nix
  ];

  # Harness API credentials, encrypted to this host and to the thinkbook.
  # Recipients are SSH public keys because age.identityPaths point at SSH private
  # keys — see secrets/README.md.
  age.secrets = {
    deepseek-api-key.file = ../../secrets/deepseek-api-key.age;
    # One credential, two variable names: OpenCode Go and OpenCode Zen accept
    # the same key, so it is stored once and read under both names.
    opencode-api-key.file = ../../secrets/opencode-api-key.age;
    ten-rings-api-key.file = ../../secrets/ten-rings-api-key.age;
  };

  # The DeepSeek Harness web profile. Both it and the ACP profile below are
  # published without host-specific overrides: the web module's defaults already
  # name this host (service host, app capability, OpenObserve streams) and its
  # service config file already defaults to config/tailscale/nuc-services.hujson.
  hostServices.deepseekHarness = {
    enable = true;

    # The ACP profile below owns the module's default runtime directory and
    # patches the same bundle files, so the web service gets its own npm tree.
    # Its DSH_HOME stays at the module default and is therefore separate from
    # the ACP home as well.
    runtimeDir = "${config.home.homeDirectory}/.local/share/deepseek-harness/web-runtime";
  };

  # DeepSeek Harness as an ACP stdio server, for an editor on this host or over
  # SSH. It is deliberately independent of the web profile above: the
  # `storages/` JSON backend has no cross-process lock, so two harnesses sharing
  # one `$DSH_HOME` is not a supported arrangement.
  hostServices.deepseekHarnessAcp = {
    enable = true;

    # Stay on the shipped bridge; see docs/deepseek-harness-acp.md for why the
    # enhanced one is packaged but not used.
    bridge = "official";

    # Kept next to the web home but distinct from it, so the two profiles never
    # share settings, credentials or session storage.
    dshHome = "${config.home.homeDirectory}/.local/share/deepseek-harness/acp-home";

    # Both gateways are directly reachable from this host (verified), and this
    # host is the one whose model routes the web profile already uses. Starting
    # on the same route keeps an editor session equivalent to a web session;
    # the model selector can switch to any of the shared routes below.
    provider = "ten-rings";
    model = "gpt-5.6-terra";

    # The launch environment has the highest precedence in the credential seam.
    credentialsFiles = {
      DEEPSEEK_API_KEY = config.age.secrets.deepseek-api-key.path;
      OPENCODE_GO_API_KEY = config.age.secrets.opencode-api-key.path;
      OPENCODE_API_KEY = config.age.secrets.opencode-api-key.path;
      TEN_RINGS_API_KEY = config.age.secrets.ten-rings-api-key.path;
    };

    extraSettingsSeeds = [ ../../config/deepseek-harness/settings.seed.ten-rings.yaml ];

    openCodeRoutes.enable = true;

    # The automation-only ACP bridge advertises no permission selector, so this
    # is a launch fact rather than something switchable per thread.
    permissionMode = "workspace-write";
  };

  # Publish this host's endpoints (svc:deepseek-harness and the other services
  # declared in config/tailscale/nuc-services.hujson) from the repository-owned
  # service config.
  hostServices.tailscaleServices.enable = true;

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
