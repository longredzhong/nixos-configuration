{
  pkgs,
  config,
  lib,
  ...
}:
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

      if is_human_interactive_shell && [[ -z "$FISH_VERSION" ]] && [[ -z "$BASH_NO_EXEC_FISH" ]]; then
        if command -v fish &> /dev/null; then
          exec fish
        fi
      fi

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

      _proxy_url() {
        local proxy="''${1:-${cfg.defaultProxy}}"
        [[ "$proxy" == *://* ]] || proxy="http://$proxy"
        case "''${proxy%%://*}" in
          http|https|socks4|socks4a|socks5|socks5h)
            printf '%s\n' "$proxy"
            ;;
          *)
            printf 'Unsupported proxy protocol: %s\n' "''${proxy%%://*}" >&2
            printf 'Supported protocols: http, https, socks4, socks4a, socks5, socks5h\n' >&2
            return 2
            ;;
        esac
      }

      _proxy_display_url() {
        local proxy="$1"
        local scheme="''${proxy%%://*}"
        local rest="''${proxy#*://}"
        if [[ "$rest" == *@* ]]; then
          local auth="''${rest%@*}"
          local host="''${rest#*@}"
          if [[ "$auth" == *:* ]]; then
            auth="''${auth%%:*}:***"
          else
            auth="***"
          fi
          printf '%s://%s@%s\n' "$scheme" "$auth" "$host"
        else
          printf '%s\n' "$proxy"
        fi
      }

      show_proxy() {
        local proxy="''${all_proxy:-''${http_proxy:-}}"
        if [[ -z "$proxy" ]]; then
          echo "Proxy mode: disabled"
        else
          echo "Proxy mode: ''${proxy%%://*}"
          printf 'Proxy URL:  %s\n' "$(_proxy_display_url "$proxy")"
        fi
        printf 'No proxy:   %s\n' "''${no_proxy:-${cfg.noProxyList}}"
      }

      unset_proxy() {
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
        echo "Proxy disabled"
      }

      set_proxy() {
        case "''${1:-}" in
          help|-h|--help)
            printf '%s\n' \
              '用法: set_proxy [http|https|socks5|socks5h|URL|off|status]' \
              '示例:' \
              '  set_proxy                         使用默认代理' \
              '  set_proxy socks5 127.0.0.1:7891' \
              '  set_proxy socks5h://127.0.0.1:7891' \
              '  set_proxy off                     禁用代理' \
              '  set_proxy status                  查看当前代理'
            return 0
            ;;
          status)
            show_proxy
            return $?
            ;;
          off|none|disable)
            unset_proxy
            return 0
            ;;
        esac

        local proxy="''${1:-${cfg.defaultProxy}}"
        if [[ "$proxy" == http || "$proxy" == https || "$proxy" == socks4 || "$proxy" == socks4a || "$proxy" == socks5 || "$proxy" == socks5h ]]; then
          local address="''${2:-${cfg.defaultProxy}}"
          proxy="$proxy://$address"
        fi
        local proxy_url
        proxy_url="$(_proxy_url "$proxy")" || return
        if [[ "$proxy_url" == socks4://* || "$proxy_url" == socks4a://* || "$proxy_url" == socks5://* || "$proxy_url" == socks5h://* ]]; then
          export all_proxy="$proxy_url"
          export ALL_PROXY="$proxy_url"
          unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
        else
          export http_proxy="$proxy_url"
          export https_proxy="$proxy_url"
          export HTTP_PROXY="$proxy_url"
          export HTTPS_PROXY="$proxy_url"
          unset all_proxy ALL_PROXY
        fi
        export no_proxy="${cfg.noProxyList}"
        export NO_PROXY="${cfg.noProxyList}"
        printf '\n'
        show_proxy
        printf '\n'
        echo "Proxy enabled"
      }

      with_proxy() {
        if [[ $# -lt 2 ]]; then
          echo "Usage: with_proxy <proxy> <command> [args...]" >&2
          return 2
        fi
        local proxy="$1"
        shift
        if [[ "$proxy" == http || "$proxy" == https || "$proxy" == socks4 || "$proxy" == socks4a || "$proxy" == socks5 || "$proxy" == socks5h ]]; then
          if [[ $# -lt 2 ]]; then
            echo "Usage: with_proxy <protocol> <address> <command> [args...]" >&2
            return 2
          fi
          local address="$1"
          shift
          proxy="$proxy://$address"
        fi
        local proxy_url
        proxy_url="$(_proxy_url "$proxy")" || return
        local -a proxy_env=(env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY)
        if [[ "$proxy_url" == socks4://* || "$proxy_url" == socks4a://* || "$proxy_url" == socks5://* || "$proxy_url" == socks5h://* ]]; then
          proxy_env+=(all_proxy="$proxy_url" ALL_PROXY="$proxy_url")
        else
          proxy_env+=(http_proxy="$proxy_url" https_proxy="$proxy_url" HTTP_PROXY="$proxy_url" HTTPS_PROXY="$proxy_url")
        fi
        proxy_env+=(no_proxy="${cfg.noProxyList}" NO_PROXY="${cfg.noProxyList}")
        "''${proxy_env[@]}" "$@"
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
