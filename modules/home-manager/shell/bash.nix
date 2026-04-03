{ pkgs, config, lib, ... }:
let
  cfg = config.shell;
in
{
  imports = [ ./common.nix ];

  programs.bash = {
    enable = true;
    enableCompletion = true;

    historyControl = [
      "ignoreboth"
      "erasedups"
    ];
    historyIgnore = [
      "ls"
      "ll"
      "la"
      "cd"
      "pwd"
      "exit"
      "clear"
      "history"
    ];
    historySize = 10000;
    historyFileSize = 10000;
    shellOptions = lib.mkAfter [
      "histappend"
      "checkwinsize"
      "cdspell"
      "dirspell"
      "autocd"
    ];

    initExtra = ''
      is_human_interactive_shell() {
        [[ "$-" == *i* ]] && [[ -t 0 ]] && [[ -t 1 ]]
      }

      if is_human_interactive_shell; then
        set -o vi
        bind 'set show-all-if-ambiguous on'
        bind 'set completion-ignore-case on'

        if command -v any-nix-shell &> /dev/null; then
          eval "$(any-nix-shell bash --info-right)"
        fi

        if command -v direnv &> /dev/null; then
          eval "$(direnv hook bash)"
        fi

        if command -v zoxide &> /dev/null; then
          eval "$(zoxide init bash --cmd cd)"
        fi

        if command -v atuin &> /dev/null; then
          eval "$(atuin init bash)"
        fi

        if command -v starship &> /dev/null; then
          eval "$(starship init bash)"
        fi
      fi

      ttake() { cd "$(mktemp -d)" || return; }
      take() { mkdir -p -- "$1" && cd -- "$1" || return; }
      show_path() { tr ':' '\n' <<< "$PATH"; }
      posix-source() {
        while IFS= read -r line; do
          [[ "$line" =~ ^([^=]+)=(.*)$ ]] && export "''${BASH_REMATCH[1]}"="''${BASH_REMATCH[2]}"
        done < "$1"
      }

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

    shellAliases = cfg.commonAliases // {
      editbash = "$EDITOR ~/.bashrc";
      nixswitch = "cd ~/nixos-configuration && sudo -E nixos-rebuild switch --flake .#$(hostname) && cd -";
      nixhome = "cd ~/nixos-configuration && home-manager switch --flake .#${config.home.username}@$(hostname) && cd -";
    };
  };
}
