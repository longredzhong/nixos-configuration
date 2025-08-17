{ pkgs, ... }: {
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  environment.systemPackages = with pkgs; [
    gnome-tweaks
    gnome-extension-manager
  ];

  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    epiphany # GNOME Web
  ];
}
