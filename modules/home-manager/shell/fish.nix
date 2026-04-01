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
