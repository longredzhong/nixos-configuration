{ pkgs, ... }:
{
  # Rime 输入法配置文件
  xdg.dataFile = {
    "fcitx5/rime" = {
      source = "${pkgs.unstable.rime-ice}/share/rime-data";
      # source = "${pkgs.unstable.rime-frost}/share/rime-data";
      recursive = true;
    };
    "fcitx5/rime/default.custom.yaml".text = ''
      # default.custom.yaml

      patch:
        __include: rime_ice_suggestion:/
        "menu/page_size": 6
        "switcher/hotkeys":
          - "F4"
    '';
  };
}
