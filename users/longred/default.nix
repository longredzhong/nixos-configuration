{ config, pkgs, ... }: {
  home-manager.users.longred = {
    programs = {
      git = {
        userEmail = "longredzhong@outlook.com";
        userName = "longred";
      };
    };
  };
}
