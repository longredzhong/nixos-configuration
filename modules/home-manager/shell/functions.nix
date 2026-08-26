# Shared navigation / fzf helper functions for both bash.nix and fish.nix.
# These utilities are behaviourally identical in both dialects; only the syntax
# differs, so we define the meat once here.
#
#   let shell = import ./functions.nix { };
#   shell.bash                 -> single interpolatable string for bashrc
#   shell.fish.functions       -> attrset { name = body; } for fish's `functions`
{ ... }:
let
  # `fe`: pick a file with fd+fzf, open it in $EDITOR
  fe = {
    bash = ''
      fe() {
        local file
        file=$(fd --type f --hidden --exclude .git | fzf --preview "bat --color=always --style=numbers {}")
        [[ -n "$file" ]] && ''${EDITOR:-vim} "$file"
      }
    '';
    fish = ''
      set -l file (fd --type f --hidden --exclude .git | fzf --preview "bat --color=always --style=numbers {}")
      test -n "$file"; and $EDITOR $file
    '';
  };

  # `fcd`: pick a directory, cd into it
  fcd = {
    bash = ''
      fcd() {
        local dir
        dir=$(fd --type d --hidden --exclude .git | fzf --preview "eza --tree --level=2 --color=always --icons {}")
        [[ -n "$dir" ]] && cd "$dir"
      }
    '';
    fish = ''
      set -l dir (fd --type d --hidden --exclude .git | fzf --preview "eza --tree --level=2 --color=always --icons {}")
      test -n "$dir"; and cd $dir
    '';
  };

  # `fkill`: select process(es) to kill
  fkill = {
    bash = ''
      fkill() {
        local pids
        pids=$(ps -ef | sed 1d | fzf -m --header="Select process(es) to kill" | awk '{print $2}')
        [[ -n "$pids" ]] && echo "$pids" | xargs kill -9
      }
    '';
    fish = ''
      set -l pids (ps -ef | sed 1d | fzf -m --header="Select process(es) to kill" | awk '{print $2}')
      test -n "$pids"; and echo $pids | xargs kill -9
    '';
  };

  # `fenv`: inspect environment variables via fzf
  fenv = {
    bash = ''
      fenv() { env | fzf --preview "echo {}"; }
    '';
    fish = ''
      env | fzf --preview "echo {}" --header="Environment Variables"
    '';
  };

  # `gb`: switch git branch via fzf
  gb = {
    bash = ''
      gb() {
        local branch
        branch=$(git branch -a --color=always | fzf --ansi --preview "git log --oneline --graph --color=always {1}" | sed 's/^[* ]*//' | sed 's#remotes/origin/##')
        [[ -n "$branch" ]] && git checkout "$branch"
      }
    '';
    fish = ''
      set -l branch (git branch -a --color=always | fzf --ansi --preview "git log --oneline --graph --color=always {1}" | sed 's/^[* ]*//' | sed 's#remotes/origin/##')
      test -n "$branch"; and git checkout $branch
    '';
  };

  # `gbc`: checkout a git commit via fzf
  gbc = {
    bash = ''
      gbc() {
        local commit
        commit=$(git log --oneline --color=always | fzf --ansi --preview "git show --color=always {1}" | awk '{print $1}')
        [[ -n "$commit" ]] && git checkout "$commit"
      }
    '';
    fish = ''
      set -l commit (git log --oneline --color=always | fzf --ansi --preview "git show --color=always {1}" | awk '{print $1}')
      test -n "$commit"; and git checkout $commit
    '';
  };

  # `gshow`: show a git commit via fzf
  gshow = {
    bash = ''
      gshow() {
        local commit
        commit=$(git log --oneline --color=always | fzf --ansi --preview "git show --color=always {1}" | awk '{print $1}')
        [[ -n "$commit" ]] && git show "$commit"
      }
    '';
    fish = ''
      set -l commit (git log --oneline --color=always | fzf --ansi --preview "git show --color=always {1}" | awk '{print $1}')
      test -n "$commit"; and git show $commit
    '';
  };

  # Simple helpers: take / ttake / show_path / posix-source
  simpleBash = ''
    ttake() { cd "$(mktemp -d)" || return; }
    take() { mkdir -p -- "$1" && cd -- "$1" || return; }
    show_path() { tr ':' '\n' <<< "$PATH"; }
    posix-source() {
      while IFS= read -r line; do
        [[ "$line" =~ ^([^=]+)=(.*)$ ]] && export "''${BASH_REMATCH[1]}"="''${BASH_REMATCH[2]}"
      done < "$1"
    }
  '';

  simpleFish = {
    take = "mkdir -p -- \"$argv[1]\" && cd -- \"$argv[1]\"";
    ttake = "cd (mktemp -d)";
    show_path = "string split : $PATH";
    posix-source = ''
      for line in (cat $argv)
        set -l arr (string split -m 1 = $line)
        test (count $arr) -eq 2; and set -gx $arr[1] $arr[2]
      end
    '';
  };
in
{
  # Interpolate into bashrc / bash extraInit
  bash = simpleBash + fe.bash + fcd.bash + fkill.bash + fenv.bash + gb.bash + gbc.bash + gshow.bash;

  # Merge into fish's `functions` attrset
  fish.functions = simpleFish // {
    fe = fe.fish;
    fcd = fcd.fish;
    fkill = fkill.fish;
    fenv = fenv.fish;
    gb = gb.fish;
    gbc = gbc.fish;
    gshow = gshow.fish;
  };
}
