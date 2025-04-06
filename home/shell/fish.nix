{ pkgs, ... }:
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
      set -U fish_greeting
      # 提高历史记录限制
      set -g fish_history_max_length 10000
      ${pkgs.micromamba}/bin/micromamba shell init --shell fish --prefix $HOME/.share/mamba
      ${pkgs.pixi}/bin/pixi completion --shell fish | source
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
    };
    shellAbbrs =
      {
        ".." = "cd ..";
        "..." = "cd ../../";
        "...." = "cd ../../../";
        "....." = "cd ../../../../";
      }
      // {
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
    shellInit = ''
      # 设置PATH
      fish_add_path $HOME/.local/bin
      fish_add_path $HOME/.cargo/bin
    '';
  };
}
