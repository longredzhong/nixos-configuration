{ pkgs, ... }: {
  programs.atuin = {
    enable = true;
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      dotfiles.enabled = true;
    };
    enableFishIntegration = true; # 启用fish集成
  };

}
