{
  config,
  lib,
  pkgs,
  username,
  ...
}:

{
  config = {
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        atuin init fish | source
        fish_add_path --append /home/$USER/.local/bin /home/$USER/.cargo/bin
        set -gx MAMBA_ROOT_PREFIX "/home/$USER/.local/share/mamba"
        ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
        ${
          pkgs.lib.strings.fileContents (
            pkgs.fetchFromGitHub {
              owner = "rebelot";
              repo = "kanagawa.nvim";
              rev = "de7fb5f5de25ab45ec6039e33c80aeecc891dd92";
              sha256 = "sha256-f/CUR0vhMJ1sZgztmVTPvmsAgp0kjFov843Mabdzvqo=";
            }
            + "/extras/kanagawa.fish"
          )
        }        
        set -U fish_greeting
        
        ${lib.optionalString config.custom.isWsl ''
          fish_add_path --append /mnt/c/Users/${config.home.username}/scoop/apps/win32yank/0.1.1
        ''}
      '';

      functions = {
        refresh = "source $HOME/.config/fish/config.fish";
        take = ''mkdir -p -- "$1" && cd -- "$1"'';
        ttake = "cd $(mktemp -d)";
        show_path = "echo $PATH | tr ' ' '\n'";
        posix-source = ''
          for i in (cat $argv)
            set arr (echo $i |tr = \n)
            set -gx $arr[1] $arr[2]
          end
        '';
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

      # ...其余配置保持不变...
      shellAbbrs = {
        gc = "nix-collect-garbage --delete-old";
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

      plugins = [
        {
          inherit (pkgs.fishPlugins.autopair) src;
          name = "autopair";
        }
        {
          inherit (pkgs.fishPlugins.sponge) src;
          name = "sponge";
        }
      ];
    };
    
    # WSL 特定配置
    home.packages = lib.mkIf config.custom.isWsl [
      pkgs.wslu
    ];

    programs.fish.shellAliases = lib.mkIf config.custom.isWsl {
      pbcopy = "/mnt/c/Windows/System32/clip.exe";
      pbpaste = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -command 'Get-Clipboard'";
      explorer = "/mnt/c/Windows/explorer.exe";
      code = "/mnt/c/Users/${config.home.username}/scoop/apps/vscode/current/bin/code";
    };

  };
}