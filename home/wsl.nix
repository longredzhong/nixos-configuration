{ pkgs, ... }:
let
  win32yankPath = "/mnt/c/Users/longred/scoop/apps/win32yank/0.1.1";
  commonShellAliases = {
    pbcopy = "/mnt/c/Windows/System32/clip.exe";
    pbpaste = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -command 'Get-Clipboard'";
    explorer = "/mnt/c/Windows/explorer.exe";
    code = "/mnt/c/Users/longred/scoop/apps/vscode/current/bin/code";
  };
in
{
  programs = {
    fish = {
      interactiveShellInit = ''
        fish_add_path --append ${win32yankPath}
      '';
      shellAliases = commonShellAliases;
      functions = {
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
    };
    bash = {
      bashrcExtra = ''
        export PATH=$PATH:${win32yankPath}
      '';
      shellAliases = commonShellAliases;
    };
    zsh = {
      initExtra = ''
        export PATH=$PATH:${win32yankPath}
      '';
      shellAliases = commonShellAliases;
    };
  };
}
