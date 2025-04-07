{ pkgs, ... }:
let
  win32yankPath = "/mnt/c/Users/longred/scoop/apps/win32yank/0.1.1";
  commonShellAliases = {
    pbcopy = "/mnt/c/Windows/System32/clip.exe";
    pbpaste =
      "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -command 'Get-Clipboard'";
    explorer = "/mnt/c/Windows/explorer.exe";
    code = "/mnt/c/Users/longred/scoop/apps/vscode/current/bin/code";
  };
in {
  programs = {
    fish = {
      interactiveShellInit = ''
        fish_add_path --append ${win32yankPath}
        # 让 WSL 使用 Windows 的 Chrome
        set -gx BROWSER "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"

        # SSH agent 集成
        if test -z "$SSH_AUTH_SOCK"
          set SSH_AUTH_SOCK /tmp/ssh-agent.sock
          if not pgrep -f "socat.*npipe" >/dev/null
            nohup socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"/mnt/c/Users/longred/wsl-ssh-agent/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork >/dev/null 2>&1 &
          end
        end
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
        wopen = "/mnt/c/Windows/explorer.exe .";
        wslpath = ''
          set -l path $argv[1]
          if string match -q '/mnt/*' $path
            set -l drive (string sub -s 6 -l 1 $path | tr '[:lower:]' '[:upper:]')
            set -l winpath (string sub -s 8 $path | string replace -a '/' '\\')
            echo "$drive:$winpath"
          else
            echo "Path must start with /mnt/"
          end
        '';
        winpath = ''
          set -l path $argv[1]
          if string match -q '*:*' $path
            set -l drive (string sub -l 1 $path | tr '[:upper:]' '[:lower:]')
            set -l wslpath (string sub -s 3 $path | string replace -a '\\' '/')
            echo "/mnt/$drive$wslpath"
          else
            echo "Path must include a drive letter"
          end
        '';
        wslopen = ''
          /mnt/c/Windows/System32/cmd.exe /c start $argv
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
