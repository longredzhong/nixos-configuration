{ ... }:
{
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;

    settings = {
      # -------- 同步设置 --------
      auto_sync = true;
      sync.records = true;
      sync_frequency = "5m";
      dotfiles.enabled = true;

      # -------- 搜索与显示 --------
      search_mode = "fuzzy";
      filter_mode = "global";
      style = "compact";
      inline_height = 15;
      show_preview = true;
      show_help = true;
      prefers_reduced_motion = false;

      # -------- 交互行为 --------
      exit_mode = "return-original";
      enter_accept = true;
      filter_mode_shell_up_key_binding = "directory";
      ctrl_n_shortcuts = true;

      # -------- 工作区与上下文 --------
      workspaces = true;
      cwd_filter = [
        "^/tmp"
        "^/private/tmp"
      ];

      # -------- 历史记录过滤 --------
      # 排除简单/敏感命令
      history_filter = [
        "^ls$"
        "^ll$"
        "^la$"
        "^cd$"
        "^cd \\.\\./?$"
        "^pwd$"
        "^exit$"
        "^clear$"
        "^history$"
        "^fg$"
        "^bg$"
        "^jobs$"
        # 敏感命令
        "password"
        "secret"
        "token"
        "api.key"
        "AWS_SECRET"
      ];

      # -------- 命令统计 --------
      stats.common_subcommands = [
        "cargo"
        "docker"
        "git"
        "go"
        "just"
        "kubectl"
        "nix"
        "npm"
        "pixi"
        "systemctl"
      ];

      # -------- 快捷键 --------
      keys = {
        scroll_exits = false;
      };
    };
  };
}
