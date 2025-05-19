{ pkgs, config, ... }: {

  home = {
    homeDirectory = "/home/${config.home.username}";
    stateVersion = "25.05";

  };

}
