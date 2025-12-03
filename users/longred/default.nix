{ config, pkgs, ... }: {
  home-manager.users.longred = {
    programs = {
      git = {
        settings = {
          user.email = "longredzhong@outlook.com";
          user.name = "longred";
        };
      };
    };
    home.packages = with pkgs; [ gh ];
  };

}
