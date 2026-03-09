{ pkgs, ... }:
{
  home.packages = [ pkgs.unstable.ghostty ];

  xdg.configFile."ghostty/config".text = ''
    # --- 字体 ---
    font-family = "FiraCode Nerd Font Mono"
    font-size = 13

    # --- 外观 ---
    window-theme = ghostty
    window-decoration = auto
    gtk-titlebar = true
    gtk-titlebar-style = tabs
    window-subtitle = working-directory
    window-padding-x = 8
    window-padding-y = 8
    window-padding-balance = true
    background-opacity = 0.95
    background-opacity-cells = true
    background-blur = true

    # --- 交互 ---
    copy-on-select = clipboard
    shell-integration = detect
    shell-integration-features = cursor,sudo,title,ssh-env
    cursor-style = block
    mouse-hide-while-typing = true
    confirm-close-surface = false
    window-inherit-working-directory = true
    window-inherit-font-size = true
    app-notifications = no-clipboard-copy,config-reload
  '';
}