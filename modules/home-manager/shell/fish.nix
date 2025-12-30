{ pkgs, config, ... }:
{
  programs.fish = {
    enable = true;

    # --- Shell 初始化脚本 ---
    shellInit = ''
      set -l paths \
        $HOME/.local/bin \
        $HOME/.cargo/bin \
        $HOME/.pixi/bin \
        $HOME/go/bin

      for p in $paths
        test -d $p; and fish_add_path $p
      end
    '';

    interactiveShellInit = ''
      # -------- 历史与提示 --------
      set -g fish_history_max_length 10000
      set -U fish_greeting

      if status --is-interactive
        ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
      end

      # -------- 颜色主题 --------
      set -g fish_color_normal normal
      set -g fish_color_command cyan --bold
      set -g fish_color_param green
      set -g fish_color_redirection yellow
      set -g fish_color_comment brgray
      set -g fish_color_error red --bold
      set -g fish_color_escape magenta
      set -g fish_color_operator blue
      set -g fish_color_end green
      set -g fish_color_quote yellow
      set -g fish_color_autosuggestion brblack
      set -g fish_color_valid_path cyan --underline
      set -g fish_color_cwd green --bold
      set -g fish_color_cwd_root red --bold
      set -g fish_pager_color_prefix magenta --bold
      set -g fish_pager_color_completion normal
      set -g fish_pager_color_progress white --background=cyan
      set -g fish_pager_color_selected_background --background=brblue
      set -g fish_pager_color_selected_prefix yellow --bold --background=brblue
      set -g fish_pager_color_selected_completion white --background=brblue

      # -------- Pixi 优化 --------
      set -gx PIXI_CACHE_DIR "$HOME/.cache/rattler/cache"
      set -gx UV_CACHE_DIR "$PIXI_CACHE_DIR/uv-cache"
    '';

    # --- 自定义函数 ---
    functions = {
      # 重新加载 fish 配置
      refresh = "source $HOME/.config/fish/config.fish";
      # 创建目录并进入
      take = ''mkdir -p -- "$1" && cd -- "$1"'';
      # 进入临时目录
      ttake = "cd (mktemp -d)";
      # 显示 PATH 变量（每行一个）
      show_path = "string split ' ' $PATH";
      # 从文件加载 POSIX 环境变量
      posix-source = ''
        for i in (cat $argv)
          set arr (string split = $i)
          set -gx $arr[1] $arr[2]
        end
      '';

      # --- FZF 集成函数 ---
      # 使用 fzf 搜索历史记录
      fzf_history = ''
        history | fzf --tiebreak=index --no-sort | read -l cmd
        and commandline -rb $cmd
      '';
      # 使用 fzf 查找并编辑文件
      fe = ''
        set -l file (fd --type f --hidden --exclude .git | fzf --preview "bat --color=always {}")
        if test -n "$file"
          $EDITOR $file # 使用 $EDITOR 环境变量指定的编辑器
        end
      '';
      # 使用 fzf 快速进入目录 (使用 zoxide 后可能较少使用)
      fcd = ''
        set -l dir (fd --type d --hidden --exclude .git | fzf --preview "eza --tree --level=1 --color=always {}") # 使用 eza 预览
        if test -n "$dir"
          cd $dir
        end
      '';
      # 使用 fzf 查看并杀死进程
      fkill = ''
        ps -ef | sed 1d | fzf -m | awk '{print $2}' | xargs -r kill -9
      '';
      # 使用 fzf 切换 git 分支
      gb = ''
        git branch | fzf --preview "git log --oneline --graph --date=short --color=always --pretty='%C(auto)%h %s %C(blue)%cr' {1}" | sed 's/^..//' | cut -d' ' -f1 | tr -d '\n' | read -l branch
        and git checkout $branch
      '';

      # --- 代理设置函数 ---
      # 设置代理 (默认 127.0.0.1:7890)
      set_proxy = ''
        if test (count $argv) -eq 1
          set proxy $argv[1]
        else
          set proxy "127.0.0.1:7890"
        end
        set -gx http_proxy http://$proxy
        set -gx https_proxy http://$proxy
        set -gx no_proxy "localhost,127.0.0.1,::1,100.64.0.0/10,172.16.100.10" # 添加 127.0.0.1 和 ::1
        set -gx HTTP_PROXY http://$proxy
        set -gx HTTPS_PROXY http://$proxy
        set -gx NO_PROXY "localhost,127.0.0.1,::1,100.64.0.0/10,172.16.100.10" # 添加 127.0.0.1 和 ::1
      '';
      # 取消代理设置
      unset_proxy = ''
        set -e http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY
      '';
    };

    # --- Shell 缩写 ---
    shellAbbrs = {
      # Git 缩写
      gapa = "git add --patch";
      grpa = "git reset --patch";
      gst = "git status";
      gdh = "git diff HEAD";
      gp = "git push";
      gph = "git push -u origin HEAD";
      gco = "git checkout";
      gcob = "git checkout -b";
      gcm = "git checkout master"; # 根据需要调整为 main 或其他默认分支
      gcd = "git checkout develop"; # 根据需要调整
      gsp = "git stash push -m";
      gsa = "git stash apply stash^{/";
      gsl = "git stash list";

      # 其他常用缩写
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "....." = "cd ../../../..";
      ll = "eza -l -g --icons"; # 使用 eza 替代 ls
      la = "eza -la -g --icons";
      lt = "eza --tree --level=2 --icons";
      l = "eza -1 --icons";
      # cat = "bat"; # 使用 bat 替代 cat
      # grep = "rg"; # 使用 ripgrep 替代 grep
      # find = "fd"; # 使用 fd 替代 find
      # df = "duf"; # 使用 duf 替代 df
      # top = "btop"; # 使用 btop 替代 top/htop
      # dig = "dog"; # 使用 dog 替代 dig
    };

    # --- Shell 别名 ---
    shellAliases = {
      # 系统信息
      sysfetch = "fastfetch";
      sysinfo = "btop";
      diskspace = "duf";
      dirsize = "ncdu"; # 使用 ncdu 替代 du -sh

      # 快速编辑配置
      conf = "cd ~/nixos-configuration"; # 修正路径
      editfish = "$EDITOR ~/.config/fish/config.fish";
      edithosts = "sudo $EDITOR /etc/hosts";
      editflake = "$EDITOR ~/nixos-configuration/flake.nix"; # 修正路径

      # Git 快捷命令 (部分已通过缩写实现)
      gs = "git status -sb";
      ga = "git add";
      gc = "git commit";
      gl = "git log --oneline --graph --decorate --all"; # 更详细的 log
      glog = "lazygit"; # 使用 lazygit

      # Docker 快捷命令
      dps = "docker ps";
      dpsa = "docker ps -a";
      dls = "docker container ls";
      dimg = "docker images";
      drun = "docker run -it --rm"; # 默认添加 --rm
      dexec = "docker exec -it";
      dlogs = "docker logs -f";
      dstop = "docker stop";
      drm = "docker rm";
      drmi = "docker rmi";
      dprune = "docker system prune -af --volumes"; # 清理 docker

      # 网络工具
      myip = "curl -s ifconfig.me/ip"; # 只显示 IP
      myipinfo = "curl -s ifconfig.me/all.json | jq"; # 显示详细信息
      ports = "ss -tulnp"; # 查看监听端口

      # Nix 相关
      nixgc = "sudo nix-collect-garbage -d";
      nixoptimize = "sudo nix-store --optimise";
      nixupdate = "cd ~/nixos-configuration && nix flake update && cd -"; # 修正路径
      nixswitch = "cd ~/nixos-configuration && sudo -E nixos-rebuild switch --flake .#$(hostname) && cd -"; # 修正路径
      nixhome = "cd ~/nixos-configuration && home-manager switch --flake .#${config.home.username}@$(hostname) && cd -"; # 修正路径
    };

    # --- Fish 插件 ---
    plugins = [
      {
        name = "autopair";
        src = pkgs.fishPlugins.autopair.src;
      }
      {
        name = "sponge";
        src = pkgs.fishPlugins.sponge.src;
      }
      {
        name = "fzf-fish"; # FZF 集成插件
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "puffer-fish"; # 更好的 Buffer 编辑
        src = pkgs.fishPlugins.puffer.src;
      }
      {
        name = "colored-man-pages"; # 彩色 man 手册
        src = pkgs.fishPlugins.colored-man-pages.src;
      }
      {
        name = "done"; # 长时间任务完成时通知
        src = pkgs.fishPlugins.done.src;
      }
      {
        name = "bass"; # 运行 bash 脚本并导入环境
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
