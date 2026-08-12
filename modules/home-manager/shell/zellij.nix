{ ... }:
{
  programs.zellij = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;

    settings = {
      default_shell = "fish";
      unlock_first = true;
      pane_frames = false;
      mouse_mode = true;
      copy_on_select = true;
      scroll_buffer_size = 10000;
      simplified_ui = true;
      session_serialization = true;
      pane_viewport_serialization = true;
    };
  };
}
