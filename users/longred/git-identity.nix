# Shared Git identity (longred + adtiger per-project identity)
{ config, ... }:
{
  programs.git = {
    settings.user = {
      name = "longred";
      email = "longredzhong@outlook.com";
    };
    includes = [
      {
        path = "~/.gitconfig-adtiger";
        condition = "gitdir:${config.home.homeDirectory}/adtiger-project/";
      }
    ];
  };

  # The included Git config file providing the adtiger identity
  home.file.".gitconfig-adtiger".text = ''
    [user]
      name = zhongchanghong
      email = zhongchanghong@adtiger.hk
  '';
}
