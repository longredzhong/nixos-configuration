{ ... }:
{
  programs.git = {
    enable = true;

    # -------- 用户信息（由用户配置覆盖）--------
    # userName = "Your Name";
    # userEmail = "your@email.com";

    settings = {
      # -------- 核心设置 --------
      core = {
        editor = "vim";
        autocrlf = "input";
        whitespace = "trailing-space,space-before-tab";
        preloadindex = true;
        fscache = true;
      };

      # -------- 初始化 --------
      init.defaultBranch = "main";

      # -------- 推送/拉取 --------
      push = {
        default = "current";
        autoSetupRemote = true;
        followTags = true;
      };
      pull.rebase = true;
      fetch = {
        prune = true;
        pruneTags = true;
      };

      # -------- Rebase --------
      rebase = {
        autoStash = true;
        autoSquash = true;
      };

      # -------- 合并 --------
      merge = {
        conflictstyle = "diff3";
        ff = "only";
      };

      # -------- 差异 --------
      diff = {
        colorMoved = "default";
        algorithm = "histogram";
      };

      # -------- 日志 --------
      log = {
        abbrevCommit = true;
        date = "relative";
      };

      # -------- 状态 --------
      status = {
        showUntrackedFiles = "all";
        submoduleSummary = true;
      };

      # -------- 分支 --------
      branch = {
        autoSetupMerge = "always";
        sort = "-committerdate";
      };

      # -------- 标签 --------
      tag.sort = "-version:refname";

      # -------- 性能优化 --------
      gc.auto = 256;
      pack.threads = 0;

      # -------- 颜色 --------
      color = {
        ui = "auto";
        branch = {
          current = "yellow bold";
          local = "green";
          remote = "cyan";
        };
        status = {
          added = "green";
          changed = "yellow";
          untracked = "red";
        };
      };

      # -------- URL 别名 --------
      url = {
        "git@github.com:".insteadOf = "gh:";
        "git@gitlab.com:".insteadOf = "gl:";
      };

      # -------- 别名 --------
      alias = {
        st = "status -sb";
        co = "checkout";
        br = "branch";
        ci = "commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        lg = "log --oneline --graph --decorate -20";
        lga = "log --oneline --graph --decorate --all";
        amend = "commit --amend --no-edit";
        undo = "reset --soft HEAD~1";
        wip = "!git add -A && git commit -m 'WIP'";
        contributors = "shortlog --summary --numbered";
      };
    };
  };

  # -------- Delta (美化 diff)--------
  programs.delta = {
    enable = true;
    options = {
      features = "decorations";
      line-numbers = true;
      side-by-side = true;
      navigate = true;
      syntax-theme = "Dracula";
      plus-style = "syntax #003800";
      minus-style = "syntax #3f0001";
      decorations = {
        commit-decoration-style = "bold yellow box ul";
        file-style = "bold yellow ul";
        file-decoration-style = "none";
        hunk-header-decoration-style = "cyan box ul";
      };
    };
  };
}
