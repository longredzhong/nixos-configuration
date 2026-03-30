{
  # KDE 默认快捷键模板（面向 Plasma 6 / KWin 6）
  # 说明：
  # 1) 这里保留常用且稳定的默认动作。
  # 2) 默认“无快捷键”的动作不写入（避免引入非默认绑定）。
  # 3) 后续你可直接在对应 action 的值里改成自定义按键。

  ksmserver = {
    # 默认锁屏动作：保留 Screensaver 触发键，并使用常见默认 Ctrl+Alt+L。
    "Lock Session" = [
      "Screensaver"
      "Ctrl+Alt+L"
    ];

    # 默认显示注销界面（常见默认）。
    "Log Out" = "Ctrl+Alt+Del";
  };

  kwin = {
    # 当前桌面窗口平铺（Present Windows）。
    "Expose" = "Ctrl+F9";

    # 窗口遍历（KDE 默认）。
    "Walk Through Windows" = "Alt+Tab";
    "Walk Through Windows (Reverse)" = "Alt+Shift+Tab";

    # 窗口菜单与显示桌面（KDE 默认）。
    "Window Operations Menu" = "Alt+F3";
    "Show Desktop" = "Ctrl+F12";

    # 方向窗口切换（KDE 默认：Meta+Alt+方向键）。
    "Switch Window Left" = "Meta+Alt+Left";
    "Switch Window Right" = "Meta+Alt+Right";
    "Switch Window Up" = "Meta+Alt+Up";
    "Switch Window Down" = "Meta+Alt+Down";

    # 桌面切换默认保留 1-4（KDE 默认通常只对前 4 个桌面预置）。
    "Switch to Desktop 1" = "Ctrl+F1";
    "Switch to Desktop 2" = "Ctrl+F2";
    "Switch to Desktop 3" = "Ctrl+F3";
    "Switch to Desktop 4" = "Ctrl+F4";

    # KDE 6 默认桌面总览动作。
    "Overview" = "Meta+W";
  };
}
