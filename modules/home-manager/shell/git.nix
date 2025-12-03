{ pkgs, ... }: {
  programs.git = {
    enable = true;
    settings = {
      push = {
        default = "current";
        autoSetupRemote = true;
      };
      merge = { conflictstyle = "diff3"; };
      diff = { colorMoved = "default"; };
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      line-numbers = true;
      side-by-side = true;
      navigate = true;
    };
  };
}
