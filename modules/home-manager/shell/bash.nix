{ pkgs, config, ... }:
let
  cfg = config.shell;
in
{
  imports = [ ./common.nix ];

  programs.bash = {
    enable = false; # Disable the default bash program module

    # --- Bash 初始化脚本 ---
    profileExtra = ''
      # 设置 PATH
      for p in ${builtins.concatStringsSep " " cfg.extraPaths}; do
        [[ -d "$p" ]] && export PATH="$p:$PATH"
      done

      # 环境变量
      export PIXI_CACHE_DIR="${cfg.envVars.PIXI_CACHE_DIR}"
      export UV_CACHE_DIR="${cfg.envVars.UV_CACHE_DIR}"
      export EDITOR="${cfg.envVars.EDITOR}"
      export VISUAL="${cfg.envVars.VISUAL}"

      # 代理设置函数
      set_proxy() {
        local proxy="''${1:-${cfg.defaultProxy}}"
        export http_proxy="http://$proxy"
        export https_proxy="http://$proxy"
        export HTTP_PROXY="http://$proxy"
        export HTTPS_PROXY="http://$proxy"
        export no_proxy="${cfg.noProxyList}"
        export NO_PROXY="${cfg.noProxyList}"
        echo "Proxy set to: $proxy"
      }

      unset_proxy() {
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY
        echo "Proxy unset"
      }

      show_proxy() {
        echo "http_proxy:  $http_proxy"
        echo "https_proxy: $https_proxy"
        echo "no_proxy:    $no_proxy"
      }

      # 加载 nix-shell 支持
      if command -v any-nix-shell &> /dev/null; then
        eval "$(any-nix-shell bash --info-right)"
      fi
    '';

    initExtra = ''
      # -------- Shell 选项 --------
      shopt -s histappend     # 追加历史而非覆盖
      shopt -s checkwinsize   # 调整窗口大小后更新 LINES/COLUMNS
      shopt -s cdspell        # 自动修正 cd 拼写错误
      shopt -s dirspell       # 自动修正目录拼写
      shopt -s autocd         # 输入目录名自动 cd

      # -------- 历史设置 --------
      export HISTSIZE=10000
      export HISTFILESIZE=10000
      export HISTCONTROL=ignoreboth:erasedups
      export HISTIGNORE="ls:ll:la:cd:pwd:exit:clear:history"
      export HISTTIMEFORMAT="%F %T "

      # -------- 命令行编辑 --------
      set -o vi
      bind 'set show-all-if-ambiguous on'
      bind 'set completion-ignore-case on'

      # -------- 基础工具函数 --------
      ttake() { cd "$(mktemp -d)" || return; }
      take() { mkdir -p -- "$1" && cd -- "$1" || return; }
      show_path() { tr ':' '\n' <<< "$PATH"; }
      posix-source() {
        while IFS= read -r line; do
          [[ "$line" =~ ^([^=]+)=(.*)$ ]] && export "''${BASH_REMATCH[1]}"="''${BASH_REMATCH[2]}"
        done < "$1"
      }

      # -------- FZF 增强函数 --------
      fe() {
        local file
        file=$(fd --type f --hidden --exclude .git | fzf --preview "bat --color=always --style=numbers {}")
        [[ -n "$file" ]] && ''${EDITOR:-vim} "$file"
      }

      fcd() {
        local dir
        dir=$(fd --type d --hidden --exclude .git | fzf --preview "eza --tree --level=2 --color=always --icons {}")
        [[ -n "$dir" ]] && cd "$dir"
      }

      fkill() {
        local pids
        pids=$(ps -ef | sed 1d | fzf -m --header="Select process(es) to kill" | awk '{print $2}')
        [[ -n "$pids" ]] && echo "$pids" | xargs kill -9
      }

      fenv() { env | fzf --preview "echo {}"; }

      # -------- Git 增强函数 --------
      gb() {
        local branch
        branch=$(git branch -a --color=always | fzf --ansi --preview "git log --oneline --graph --color=always {1}" | sed 's/^[* ]*//' | sed 's#remotes/origin/##')
        [[ -n "$branch" ]] && git checkout "$branch"
      }

      gshow() {
        local commit
        commit=$(git log --oneline --color=always | fzf --ansi --preview "git show --color=always {1}" | awk '{print $1}')
        [[ -n "$commit" ]] && git show "$commit"
      }
    '';

    # --- Bash 别名（使用共享配置）---
    shellAliases = cfg.commonAliases // {
      # Bash 专属别名
      editbash = "$EDITOR ~/.bashrc";
      nixswitch = "cd ~/nixos-configuration && sudo -E nixos-rebuild switch --flake .#$(hostname) && cd -";
      nixhome = "cd ~/nixos-configuration && home-manager switch --flake .#${config.home.username}@$(hostname) && cd -";
    };

    # --- Bash 补全 ---
    bashrcExtra = ''
      # 加载补全脚本
      for f in /etc/bash_completion.d/git ~/.nix-profile/etc/profile.d/nix.sh; do
        [[ -f "$f" ]] && source "$f"
      done

      # 加载 bash-completion（如果可用）
      if [[ -r /usr/share/bash-completion/bash_completion ]]; then
        source /usr/share/bash-completion/bash_completion
      fi
    '';
  };
}
