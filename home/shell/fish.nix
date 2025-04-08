{ pkgs, ... }: {
  programs.fish = {
    enable = true;
    package = pkgs.unstable.fish;

    interactiveShellInit = ''
      # Increase history limit
      set -g fish_history_max_length 10000

      ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
      set -U fish_greeting

      # CD 补全样式优化
      # 基础颜色设置
      set -g fish_color_normal normal
      set -g fish_color_command blue --bold
      set -g fish_color_param cyan
      set -g fish_color_redirection yellow
      set -g fish_color_comment brblack
      set -g fish_color_error red --bold
      set -g fish_color_escape magenta
      set -g fish_color_operator green
      set -g fish_color_end green
      set -g fish_color_quote yellow
      set -g fish_color_autosuggestion brblack
      set -g fish_color_valid_path --underline
      set -g fish_color_cwd green
      set -g fish_color_cwd_root red

      # 目录补全菜单样式优化
      set -g fish_pager_color_prefix blue --bold  # 前缀匹配部分
      set -g fish_pager_color_completion normal   # 补全条目
      set -g fish_pager_color_description yellow  # 补全描述
      set -g fish_pager_color_progress brwhite --background=blue  # 分页指示器

      # 选中项样式优化
      set -g fish_pager_color_selected_background --background=brblack  # 选中项背景色
      set -g fish_pager_color_selected_prefix blue --bold --background=brblack  # 选中项的前缀
      set -g fish_pager_color_selected_completion white --background=brblack  # 选中项的补全文本

      # 增强 CD 补全的特殊处理
      function __enhanced_cd_complete
          # 使用标准的目录补全，但添加额外的格式化
          __fish_complete_directories $argv
      end

      # 为 cd 命令注册自定义补全
      complete -c cd -e
      complete -c cd -f -a "(__enhanced_cd_complete)"
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
