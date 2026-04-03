{ ... }:
{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = false;

    settings = {
      # -------- 全局设置 --------
      add_newline = true;
      scan_timeout = 10;
      command_timeout = 500;

      # -------- 提示符格式 --------
      format = builtins.concatStringsSep "" [
        "$username"
        "$hostname"
        "$directory"
        "$git_branch"
        "$git_status"
        "$python"
        "$rust"
        "$nodejs"
        "$golang"
        "$nix_shell"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];

      # -------- 字符提示符 --------
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
        vimcmd_symbol = "[V](bold green)";
      };

      # -------- 目录 --------
      directory = {
        style = "bold cyan";
        truncate_to_repo = true;
        truncation_length = 5;
        truncation_symbol = "…/";
        read_only = " 󰌾";
      };

      # -------- Git --------
      git_branch = {
        style = "bold purple";
        symbol = " ";
        truncation_length = 20;
      };
      git_status = {
        style = "bold red";
        ahead = "⇡$count";
        behind = "⇣$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
        conflicted = "=";
        untracked = "?";
        stashed = "\\$";
        modified = "!";
        staged = "+";
        renamed = "»";
        deleted = "✘";
      };

      # -------- 命令时长 --------
      cmd_duration = {
        min_time = 500;
        format = "took [$duration](bold yellow) ";
        show_milliseconds = false;
      };

      # -------- Nix Shell --------
      nix_shell = {
        disabled = false;
        symbol = "❄️ ";
        impure_msg = "[impure](bold red)";
        pure_msg = "[pure](bold green)";
        format = "via [$symbol$state( \\($name\\))]($style) ";
      };

      # -------- 编程语言 --------
      python = {
        symbol = "🐍 ";
        format = "via [$symbol$pyenv_prefix($version )(\\($virtualenv\\) )]($style)";
      };
      rust = {
        symbol = "🦀 ";
        format = "via [$symbol($version )]($style)";
      };
      nodejs = {
        symbol = "⬢ ";
        format = "via [$symbol($version )]($style)";
      };
      golang = {
        symbol = "🐹 ";
        format = "via [$symbol($version )]($style)";
      };

      # -------- 主机信息 --------
      username = {
        style_user = "bold green";
        style_root = "bold red";
        format = "[$user]($style)";
        show_always = false;
      };
      hostname = {
        ssh_only = true;
        style = "bold green";
        format = "@[$hostname]($style) ";
      };

      # -------- 禁用模块 --------
      aws.disabled = true;
      gcloud.disabled = true;
      azure.disabled = true;
      kubernetes.disabled = true;
      ruby.disabled = true;
      php.disabled = true;
      java.disabled = true;
      package.disabled = true;
    };
  };
}
