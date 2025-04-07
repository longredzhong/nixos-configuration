{ pkgs, ... }: {
  programs.fish = {
    enable = true;
    package = pkgs.unstable.fish;

    interactiveShellInit = ''
      set -U fish_greeting
      # Increase history limit
      set -g fish_history_max_length 10000
    '';

    functions = {
      refresh = "source $HOME/.config/fish/config.fish";
      take = ''mkdir -p -- "$1" && cd -- "$1"'';
      ttake = "cd (mktemp -d)"; # More idiomatic fish syntax
      show_path = "string split ' ' $PATH"; # More efficient way
      posix-source = ''
        for i in (cat $argv)
          set arr (string split = $i)
          set -gx $arr[1] $arr[2]
        end
      '';

      # 用 fzf 搜索历史记录
      fzf_history = ''
        history | fzf --tiebreak=index --no-sort | read -l cmd
        and commandline -rb $cmd
      '';

      # 快速查找和编辑文件
      fe = ''
        set -l file (fd --type f --hidden --exclude .git | fzf --preview "bat --color=always {}")
        if test -n "$file"
          $EDITOR $file
        end
      '';

      # 快速进入目录
      fcd = ''
        set -l dir (fd --type d --hidden --exclude .git | fzf --preview "ls -la {}")
        if test -n "$dir"
          cd $dir
        end
      '';

      # 快速查看进程和杀死进程
      fkill = ''
        ps -ef | sed 1d | fzf -m | awk '{print $2}' | xargs -r kill -9
      '';

      # 查看当前目录的 git 分支
      gb = ''
        git branch | fzf --preview "git log --oneline --graph --date=short --color=always --pretty='%C(auto)%h %s %C(blue)%cr' {1}" | sed 's/^..//' | cut -d' ' -f1 | tr -d '\n' | read -l branch
        and git checkout $branch
      '';
    };

    shellAbbrs = {
      # Directory navigation
      ".." = "cd ..";
      "..." = "cd ../../";
      "...." = "cd ../../../";
      "....." = "cd ../../../../";

      # Git abbreviations
      gapa = "git add --patch";
      grpa = "git reset --patch";
      gst = "git status";
      gdh = "git diff HEAD";
      gp = "git push";
      gph = "git push -u origin HEAD";
      gco = "git checkout";
      gcob = "git checkout -b";
      gcm = "git checkout master";
      gcd = "git checkout develop";
      gsp = "git stash push -m";
      gsa = "git stash apply stash^{/";
      gsl = "git stash list";
    };

    shellAliases = {
      # 系统信息
      sysfetch = "neofetch";
      sysinfo = "btop";
      diskspace = "duf";
      dirsize = "du -sh * | sort -hr";

      # 快速编辑配置
      conf = "cd ~/configuration";
      editfish = "$EDITOR ~/.config/fish/config.fish";

      # Git 快捷命令
      gs = "git status -sb";
      ga = "git add";
      gc = "git commit";
      gl = "git log --oneline --graph";

      # Docker 快捷命令
      dps = "docker ps";
      dls = "docker container ls";
      dimg = "docker images";
      drun = "docker run -it";
      dexec = "docker exec -it";

      # 网络工具
      myip = "curl ifconfig.me";
      dig = "dog";
    };

    plugins = [
      {
        inherit (pkgs.fishPlugins.autopair) src;
        name = "autopair";
      }
      {
        inherit (pkgs.fishPlugins.sponge) src;
        name = "sponge";
      }
      {
        inherit (pkgs.fishPlugins.wakatime-fish) src;
        name = "wakatime-fish";
      }
      {
        inherit (pkgs.fishPlugins.pure) src;
        name = "pure";
      }
    ];

    shellInit = ''
      # Set PATH
      fish_add_path $HOME/.local/bin
      fish_add_path $HOME/.cargo/bin
    '';
  };
}
