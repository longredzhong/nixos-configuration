{ pkgs, ... }: {
  programs.atuin = {
    enable = true;
    settings = {
      auto_sync = true;
      record = true;
      sync_frequency = "5m";
      dotfiles.enabled = true;
      search_mode = "fuzzy";  # 模糊搜索模式
      filter_mode = "global";  # 全局过滤
      style = "compact";  # 紧凑显示
      inline_height = 15;  # 内联显示高度
      show_preview = true;  # 显示预览
      exit_mode = "return-original";  # 退出时返回原命令
      enter_accept = true;  # 按回车直接执行
      filter_mode_shell_up_key_binding = "directory";  # 上键只搜索当前目录
      workspaces = true;  # 启用工作区感知
      ctrl_n_shortcuts = true;  # Ctrl+1-9 快速选择
      # 历史记录管理
      max_history_length = 100000;
      history_filter = [
        "^ls"
        "^cd"
        "^pwd"
        "^exit"
      ];  # 过滤简单命令
      
      # 统计和搜索
      stats.common_subcommands = [
        "docker"
        "git"
        "kubectl"
        "nix"
      ];
    };
    enableFishIntegration = true; # 启用fish集成
  };

}
