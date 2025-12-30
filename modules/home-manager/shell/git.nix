{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings = {
      push = {
        default = "current";
        autoSetupRemote = true;
      };
      merge = {
        conflictstyle = "diff3";
      };
      diff = {
        colorMoved = "default";
      };
      init.defaultBranch = "main";
      pull.rebase = true; # 拉取时自动 rebase
      rebase.autoStash = true; # rebase 时自动 stash
      fetch.prune = true; # 自动清理远程分支

      # 性能优化
      core.preloadindex = true;
      core.fscache = true;
      gc.auto = 256;
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
