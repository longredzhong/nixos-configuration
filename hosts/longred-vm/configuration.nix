# NixOS system for the longred-vm KVM guest.
#
# This machine is a single-disk QEMU/KVM guest on the adtiger virtualization
# host. It boots with legacy BIOS, so GRUB is installed to the whole disk and
# ./disko.nix provides a BIOS boot partition instead of an EFI system
# partition.
#
# It is deliberately a clean base: no application services and no data
# directories. The previous Fedora installation, and everything that ran on
# it, was removed on purpose.
#
# Note on installation: the guest is only reachable from the Tailscale
# side of the network, and a reinstall destroys the Tailscale identity that
# provides that path. It is therefore installed with nixos-anywhere from a
# host on the same LAN; the tailnet identity is carried over separately so the
# guest returns with its original node name and address.
{
  config,
  pkgs,
  lib,
  inputs,
  username,
  hostname,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.agenix.nixosModules.default
    ./disko.nix
    ./garage-backup.nix
    ./ntfy.nix
  ];

  system.stateVersion = "26.05";
  networking.hostName = hostname;

  # --- boot ---------------------------------------------------------------
  boot.loader.grub = {
    enable = true;
    useOSProber = false;
    # The target disk is not set here: disko derives
    # `boot.loader.grub.devices` from the EF02 partition declared in
    # ./disko.nix. Setting the singular `device` as well would append the same
    # path a second time and trip the "duplicated devices in mirroredBoots"
    # assertion.
  };
  boot.loader.systemd-boot.enable = false;

  # Only the virtio drivers plus ext4 are needed in the initrd; this is the
  # full set of storage and network devices the guest has.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "ahci"
    "sd_mod"
    "ext4"
  ];

  # Keep a serial console available so the virtualization host can attach with
  # `virsh console longred-vm` even when networking is broken.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];
  systemd.services."serial-getty@ttyS0".enable = true;

  # --- filesystem ---------------------------------------------------------
  # The root filesystem is declared by disko, not here.
  zramSwap.enable = true;

  # --- networking ---------------------------------------------------------
  # Both NICs get their addresses over DHCP: enp1s0 on the libvirt NAT network
  # and enp2s0 on the LAN.
  networking.useDHCP = true;

  # enp1s0 is only a management link: the libvirt NAT network on this host has
  # no working route to the internet. enp2s0 is the LAN that does. dhcpcd
  # derives route metrics from the interface index, which put the NAT link
  # first and left the guest with no outbound connectivity at all — DNS
  # resolved, but nothing else left the machine. Pin the LAN to the lower
  # metric so it owns the default route, matching the layout this guest had
  # before the reinstall.
  networking.dhcpcd.extraConfig = ''
    interface enp2s0
      metric 100
    interface enp1s0
      metric 500
  '';

  networking.firewall = {
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
    # The binary cache is published on the tailnet only. The rule is attached
    # to the interface rather than allowedTCPPorts so the LAN and the libvirt
    # NAT network cannot reach it.
    interfaces.tailscale0.allowedTCPPorts = [ 5000 ];
  };

  # --- secrets ------------------------------------------------------------
  # agenix decrypts with the machine's SSH host key. That key was carried over
  # from the previous installation by nixos-anywhere --copy-host-keys, so the
  # recipient below matches this host; the account key is a second recipient
  # so the secret stays recoverable if the host key is ever regenerated.
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets.nix-binary-cache-key = {
    file = ../../secrets/nix-binary-cache-key.age;
    owner = "root";
    mode = "0400";
  };

  # --- remote build -------------------------------------------------------
  # Other machines in the lab use this host as a remote builder. Nix connects
  # over SSH and drives nix-daemon there, and the daemon has to write to
  # /nix/store, so the builder has to accept a root login — by key only. That
  # is the standard arrangement for a build machine and the tailnet ACL is what
  # actually decides who may reach it.
  services.openssh = {
    enable = true;
    settings = {
      # Key-only, including for root: remote builds need a root login because
      # the Nix daemon writes to /nix/store.
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [
    # longred@nuc — the workstation that builds and deploys this repository
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBFpBt+r7xL1vyE1A2pUn72DEQy7wQ4hW6qhqYnZz2Fi longred@nuc"
    # root@fedora-thinkbook — the LAN-local client, which is the fast path to
    # this builder (the NUC reaches it only over a relayed tailnet link)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQSbxOhZstBps0KgTKARVN8brPnmU26bjmcXYFlAQGU root@fedora-thinkbook"
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # The daemon trusts root (implicitly) and wheel; that is what lets the
    # connecting client request builds and extra substituters.
    trusted-users = [
      "root"
      "@wheel"
    ];
    max-jobs = "auto";
    cores = 0;
    # Advertised to clients so they only schedule work this host can run.
    system-features = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
  };

  # --- binary cache -------------------------------------------------------
  # harmonia serves this host's store and signs the narinfos it hands out with
  # the key above, so clients can verify what they substitute.
  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [ config.age.secrets.nix-binary-cache-key.path ];
  };

  # The tailscaled state from the previous installation is restored into the
  # new root before the first boot, so the guest rejoins the tailnet under the
  # same node identity without an auth key.
  #
  # services.tailscale.extraUpFlags is deliberately not set: nixpkgs only
  # applies it together with services.tailscale.authKeyFile, which this host
  # does not use.
  services.tailscale.enable = true;

  services.qemuGuest.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "systemd-journal"
    ];
    # The key that already reaches this machine over the tailnet. Keeping it
    # here means `ssh dev@longred-vm` does not depend on Tailscale SSH being
    # enabled for this node.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBFpBt+r7xL1vyE1A2pUn72DEQy7wQ4hW6qhqYnZz2Fi longred@nuc"
      # The LAN-local workstation. Deployments to this guest go over the LAN
      # rather than the relayed tailnet link.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICw0USk2+Qy2+RJjNTinq8R293JmEpKJT1FUIKn0GWTf longred@fedora-thinkbook"
    ];
  };

  # nixos-anywhere drives the installation over SSH and needs passwordless
  # sudo; the account is in `wheel`.
  security.sudo.wheelNeedsPassword = false;

  programs.fish.enable = true;
}
