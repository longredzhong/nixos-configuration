{ pkgs, ... }: {
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      # Increase history limit
      set -g fish_history_max_length 10000

      ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
      set -U fish_greeting

      # CD 补全样式优化
      # 基础颜色设置优化
      set -g fish_color_normal normal
      set -g fish_color_command cyan --bold  # 命令颜色更醒目
      set -g fish_color_param green          # 参数颜色柔和
      set -g fish_color_redirection yellow   # 重定向颜色保持
      set -g fish_color_comment brgray       # 注释颜色更柔和
      set -g fish_color_error red --bold     # 错误颜色保持
      set -g fish_color_escape magenta       # 转义字符颜色保持
      set -g fish_color_operator blue        # 操作符颜色调整为蓝色
      set -g fish_color_end green            # 结束符颜色保持
      set -g fish_color_quote yellow         # 引号颜色保持
      set -g fish_color_autosuggestion brblack  # 自动补全颜色保持
      set -g fish_color_valid_path cyan --underline  # 有效路径颜色更醒目
      set -g fish_color_cwd green --bold     # 当前目录颜色加粗
      set -g fish_color_cwd_root red --bold  # 根目录颜色加粗

      # 目录补全菜单样式优化
      set -g fish_pager_color_prefix magenta --bold  # 前缀匹配部分更醒目
      set -g fish_pager_color_completion normal      # 补全条目保持
      set -g fish_pager_color_progress white --background=cyan  # 分页指示器更柔和

      # 选中项样式优化
      set -g fish_pager_color_selected_background --background=brblue  # 选中项背景色柔和
      set -g fish_pager_color_selected_prefix yellow --bold --background=brblue  # 选中项的前缀更醒目
      set -g fish_pager_color_selected_completion white --background=brblue  # 选中项的补全文本保持

      # 增强 CD 补全的特殊处理
      function __enhanced_cd_complete
          # 使用标准的目录补全，但移除描述信息
          __fish_complete_directories $argv | cut -f1
      end

      # 为 cd 命令注册自定义补全
      complete -c cd -e
      complete -c cd -f -a "(__enhanced_cd_complete)"

      # >>> mamba initialize >>>
      # !! Contents within this block are managed by 'micromamba shell init' !!
      set -gx MAMBA_EXE "/home/longred/.pixi/envs/micromamba/bin/micromamba"
      set -gx MAMBA_ROOT_PREFIX "/home/longred/.local/share/mamba"
      $MAMBA_EXE shell hook --shell fish --root-prefix $MAMBA_ROOT_PREFIX | source
      # <<< mamba initialize <<<

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

      # Add common proxy functions moved from wsl.nix
      set_proxy = ''
        if test (count $argv) -eq 1
          set proxy $argv[1]
        else
          set proxy "127.0.0.1:7890"
        end
        set -gx http_proxy http://$proxy
        set -gx https_proxy http://$proxy
        set -gx no_proxy "localhost,100.64.0.0/10,172.16.100.10"
        set -gx HTTP_PROXY http://$proxy
        set -gx HTTPS_PROXY http://$proxy
        set -gx NO_PROXY "localhost,100.64.0.0/10,172.16.100.10"
      '';
      unset_proxy = ''
        set -e http_proxy
        set -e https_proxy
        set -e no_proxy
        set -e HTTP_PROXY
        set -e HTTPS_PROXY
        set -e NO_PROXY
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
