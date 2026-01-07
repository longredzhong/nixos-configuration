{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    keyMode = "vi";
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 50000;
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
      {
        plugin = power-theme;
        extraConfig = "set -g @tmux_power_theme 'moon'";
      }
      tmux-fzf
      vim-tmux-navigator
    ];

    extraConfig = ''
      # -------- 前缀键 --------
      set -g prefix C-a
      unbind C-b
      bind C-a send-prefix

      # -------- 窗口分割 --------
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # -------- 窗格导航（vim 风格）--------
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # -------- 窗格大小调整 --------
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # -------- 窗口切换 --------
      bind -r C-h previous-window
      bind -r C-l next-window

      # -------- 配置重载 --------
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # -------- 复制模式 --------
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel
      bind -T copy-mode-vi Escape send -X cancel

      # -------- 终端颜色 --------
      set -ga terminal-overrides ",*256col*:Tc"
      set -ga terminal-overrides ",xterm-256color:Tc"

      # -------- 状态栏 --------
      set -g status-position top
      set -g status-interval 5

      # -------- 其他设置 --------
      set -g focus-events on
      set -g set-clipboard on
      setw -g aggressive-resize on
    '';
  };
}
