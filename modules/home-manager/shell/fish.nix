{ pkgs, config, ... }:
let
  cfg = config.shell;
in
{
  imports = [ ./common.nix ];

  # -------- FZF 配置 --------
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--multi"
      "--bind=ctrl-j:accept,ctrl-k:kill-line,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down"
      "--color=dark"
      "--preview-window=right:50%:wrap"
    ];
  };

  # -------- Fish Shell 配置 --------
  programs.fish = {
    enable = true;

    # --- Shell 初始化脚本 ---
    shellInit = ''
      # 设置 PATH
      for p in ${builtins.concatStringsSep " " cfg.extraPaths}
        test -d $p; and fish_add_path $p
      end
    '';

    interactiveShellInit = ''
      # -------- 历史与欢迎 --------
      set -g fish_history_max_length 10000
      set -U fish_greeting

      # -------- Nix Shell 支持 --------
      if status --is-interactive
        ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
      end

      # -------- 环境变量 --------
      set -gx PIXI_CACHE_DIR "${cfg.envVars.PIXI_CACHE_DIR}"
      set -gx UV_CACHE_DIR "${cfg.envVars.UV_CACHE_DIR}"
      set -gx EDITOR "${cfg.envVars.EDITOR}"
      set -gx VISUAL "${cfg.envVars.VISUAL}"

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
    '';

    # --- 自定义函数 ---
    functions = {
      # -------- 基础工具 --------
      refresh = "source $HOME/.config/fish/config.fish";
      take = ''mkdir -p -- "$argv[1]" && cd -- "$argv[1]"'';
      ttake = "cd (mktemp -d)";
      show_path = "string split : $PATH";
      posix-source = ''
        for line in (cat $argv)
          set -l arr (string split -m 1 = $line)
          test (count $arr) -eq 2; and set -gx $arr[1] $arr[2]
        end
      '';

      # -------- FZF 集成 --------
      fe = ''
        set -l file (fd --type f --hidden --exclude .git | fzf --preview "bat --color=always --style=numbers {}")
        test -n "$file"; and $EDITOR $file
      '';
      fcd = ''
        set -l dir (fd --type d --hidden --exclude .git | fzf --preview "eza --tree --level=2 --color=always --icons {}")
        test -n "$dir"; and cd $dir
      '';
      fkill = ''
        set -l pids (ps -ef | sed 1d | fzf -m --header="Select process(es) to kill" | awk '{print $2}')
        test -n "$pids"; and echo $pids | xargs kill -9
      '';
      fenv = ''
        env | fzf --preview "echo {}" --header="Environment Variables"
      '';

      # -------- Git 增强 --------
      gb = ''
        set -l branch (git branch -a --color=always | fzf --ansi --preview "git log --oneline --graph --color=always {1}" | sed 's/^[* ]*//' | sed 's#remotes/origin/##')
        test -n "$branch"; and git checkout $branch
      '';
      gbc = ''
        set -l commit (git log --oneline --color=always | fzf --ansi --preview "git show --color=always {1}" | awk '{print $1}')
        test -n "$commit"; and git checkout $commit
      '';
      gshow = ''
        set -l commit (git log --oneline --color=always | fzf --ansi --preview "git show --color=always {1}" | awk '{print $1}')
        test -n "$commit"; and git show $commit
      '';

      # -------- 代理管理 --------
      set_proxy = ''
        set -l proxy (test (count $argv) -ge 1; and echo $argv[1]; or echo "${cfg.defaultProxy}")
        set -gx http_proxy "http://$proxy"
        set -gx https_proxy "http://$proxy"
        set -gx HTTP_PROXY "http://$proxy"
        set -gx HTTPS_PROXY "http://$proxy"
        set -gx no_proxy "${cfg.noProxyList}"
        set -gx NO_PROXY "${cfg.noProxyList}"
        echo "Proxy set to: $proxy"
      '';
      unset_proxy = ''
        set -e http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY
        echo "Proxy unset"
      '';
      show_proxy = ''
        echo "http_proxy:  $http_proxy"
        echo "https_proxy: $https_proxy"
        echo "no_proxy:    $no_proxy"
      '';
    };

    # --- Shell 缩写（Fish 专属，输入后自动展开）---
    shellAbbrs = {
      # Git 缩写
      gapa = "git add --patch";
      grpa = "git reset --patch";
      gcp = "git cherry-pick";
      grb = "git rebase";
      grbc = "git rebase --continue";
      grba = "git rebase --abort";
      gm = "git merge";
      gf = "git fetch";
      gfa = "git fetch --all";
    };

    # --- Shell 别名（使用共享配置）---
    shellAliases = cfg.commonAliases // {
      # Fish 专属别名
      editfish = "$EDITOR ~/.config/fish/config.fish";
      nixswitch = "cd ~/nixos-configuration && sudo -E nixos-rebuild switch --flake .#(hostname) && cd -";
      nixhome = "cd ~/nixos-configuration && home-manager switch --flake .#${config.home.username}@(hostname) && cd -";
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
