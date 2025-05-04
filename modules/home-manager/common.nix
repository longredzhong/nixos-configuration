{ pkgs, config, ... }: {

  home = {
    homeDirectory = "/home/${config.home.username}";
    stateVersion = "24.11";

  };

}
