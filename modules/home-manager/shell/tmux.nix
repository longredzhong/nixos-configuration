{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      resurrect
      continuum
      {
        plugin = power-theme;
        extraConfig = ''
          set -g @tmux_power_theme 'default'
        '';
      }
    ];
    extraConfig = ''
      # 设置前缀键
      set -g prefix C-a
      unbind C-b
      bind C-a send-prefix

      # 窗口分割快捷键
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # 启用256色
      set -g default-terminal "screen-256color"
      set -ga terminal-overrides ",*256col*:Tc"

      # 自动保存会话
      set -g @continuum-restore 'on'
    '';
  };
}
