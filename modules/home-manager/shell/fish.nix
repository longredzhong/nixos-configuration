{ pkgs, config, ... }:
let
  cfg = config.shell;
in
{
  imports = [ ./common.nix ];

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

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -g fish_history_max_length 10000
      set -U fish_greeting

      if status --is-interactive
        ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
      end

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

    functions = {
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

      set_proxy = ''
        switch "$argv[1]"
          case help -h --help
            printf '%s\n' \
              '用法: set_proxy [http|https|socks5|socks5h|URL|off|status]' \
              '示例:' \
              '  set_proxy                         使用默认代理' \
              '  set_proxy socks5 127.0.0.1:7891' \
              '  set_proxy socks5h://127.0.0.1:7891' \
              '  set_proxy off                     禁用代理' \
              '  set_proxy status                  查看当前代理'
            return 0
          case status
            show_proxy
            return $status
          case off none disable
            unset_proxy
            return 0
        end

        set -l proxy (test (count $argv) -ge 1; and echo $argv[1]; or echo "${cfg.defaultProxy}")
        if contains -- $proxy http https socks4 socks4a socks5 socks5h
          set proxy "$proxy://"(test (count $argv) -ge 2; and echo $argv[2]; or echo "${cfg.defaultProxy}")
        end
        string match -q '*://*' -- $proxy; or set proxy "http://$proxy"
        set -l protocol (string split -m1 '://' -- $proxy)[1]
        if not contains -- $protocol http https socks4 socks4a socks5 socks5h
          printf 'Unsupported proxy protocol: %s\n' $protocol >&2
          printf 'Supported protocols: http, https, socks4, socks4a, socks5, socks5h\n' >&2
          return 2
        end
        if string match -q -r '^socks4a?://|^socks5h?://' -- $proxy
          set -gx all_proxy $proxy
          set -gx ALL_PROXY $proxy
          set -e http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
        else
          set -gx http_proxy $proxy
          set -gx https_proxy $proxy
          set -gx HTTP_PROXY $proxy
          set -gx HTTPS_PROXY $proxy
          set -e all_proxy ALL_PROXY
        end
        set -gx no_proxy "${cfg.noProxyList}"
        set -gx NO_PROXY "${cfg.noProxyList}"
        printf '\n'
        show_proxy
        printf '\n'
        echo "Proxy enabled"
      '';
      unset_proxy = ''
        set -e http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
        echo "Proxy disabled"
      '';
      show_proxy = ''
        set -l proxy (test -n "$all_proxy"; and echo $all_proxy; or echo $http_proxy)
        if test -z "$proxy"
          echo "Proxy mode: disabled"
        else
          set -l display $proxy
          set -l scheme (string split -m1 '://' -- $proxy)[1]
          set -l authority (string split -m1 '://' -- $proxy)[2]
          if string match -q '*@*' -- $authority
            set -l auth (string split -m1 '@' -- $authority)[1]
            set -l host (string split -m1 '@' -- $authority)[2]
            if string match -q '*:*' -- $auth
              set auth (string split -m1 ':' -- $auth)[1]:***
            else
              set auth '***'
            end
            set display "$scheme://$auth@$host"
          end
          echo "Proxy mode: "(string split -m1 '://' -- $proxy)[1]
          echo "Proxy URL:  $display"
        end
        echo "No proxy:   "(test -n "$no_proxy"; and echo $no_proxy; or echo "${cfg.noProxyList}")
      '';
      with_proxy = ''
        if test (count $argv) -lt 2
          echo "Usage: with_proxy <proxy> <command> [args...]" >&2
          return 2
        end
        set -l proxy $argv[1]
        set -e argv[1]
        if contains -- $proxy http https socks4 socks4a socks5 socks5h
          if test (count $argv) -lt 2
            echo "Usage: with_proxy <protocol> <address> <command> [args...]" >&2
            return 2
          end
          set proxy "$proxy://"$argv[1]
          set -e argv[1]
        end
        string match -q '*://*' -- $proxy; or set proxy "http://$proxy"
        set -l protocol (string split -m1 '://' -- $proxy)[1]
        if not contains -- $protocol http https socks4 socks4a socks5 socks5h
          printf 'Unsupported proxy protocol: %s\n' $protocol >&2
          return 2
        end
        set -l proxy_env http_proxy=$proxy https_proxy=$proxy HTTP_PROXY=$proxy HTTPS_PROXY=$proxy
        if string match -q -r '^socks4a?://|^socks5h?://' -- $proxy
          set proxy_env all_proxy=$proxy ALL_PROXY=$proxy
        end
        env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY $proxy_env no_proxy="${cfg.noProxyList}" NO_PROXY="${cfg.noProxyList}" $argv
      '';
    };

    shellAbbrs = {
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

    shellAliases = cfg.commonAliases // {
      editfish = "$EDITOR ~/.config/fish/config.fish";
      nixswitch = "cd ~/nixos-configuration && sudo -E nixos-rebuild switch --flake .#(hostname) && cd -";
      nixhome = "cd ~/nixos-configuration && home-manager switch --flake .#${config.home.username}@(hostname) && cd -";
    };

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
        name = "puffer-fish";
        src = pkgs.fishPlugins.puffer.src;
      }
      {
        name = "colored-man-pages";
        src = pkgs.fishPlugins.colored-man-pages.src;
      }
      {
        name = "done";
        src = pkgs.fishPlugins.done.src;
      }
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
