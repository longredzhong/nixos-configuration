{ pkgs, ... }: {
  programs.starship = {
    enable = true;
    settings = {
      aws.disabled = true;
      gcloud.disabled = true;
      kubernetes.disabled = false;
      git_branch.style = "242";
      directory.style = "blue";
      directory.truncate_to_repo = true;
      directory.truncation_length = 8;
      python.disabled = false;
      ruby.disabled = true;
      hostname.ssh_only = false;
      hostname.style = "bold green";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };
      cmd_duration = {
        min_time = 500;
        format = "took [$duration](bold yellow)";
      };
      nix_shell = {
        symbol = " ";
        format = "via [$symbol$state]($style) ";
      };
      format = "$all";
      add_newline = true;
      line_break.disabled = false;
      package.disabled = false;
      rust.format = "via [🦀 $version](red bold)";
      nodejs.format = "via [⬢ $version](green bold)";
    };
  };
}
