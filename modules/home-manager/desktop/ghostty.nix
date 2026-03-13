{ pkgs, ... }:
let
  ghostty = pkgs.unstable.ghostty;
in
{
  home.packages = [ ghostty ];

  home.sessionVariables.GHOSTTY_RESOURCES_DIR = "${ghostty}/share/ghostty";

  xdg.configFile."ghostty/config".text = ''
# --- 字体 ---
# 字体族，可通过 ghostty +list-fonts 查看可用字体
font-family = FiraCode Nerd Font Mono
# 字号（单位: pt），高 DPI 下会自动缩放
font-size = 13

# --- 窗口外观 ---
# 窗口主题：ghostty 表示用配置中的前景/背景色渲染标题栏（仅 Linux GTK）
# 可选值: auto | system | light | dark | ghostty
window-theme = ghostty
# 窗口装饰偏好：auto 自动选择 CSD/SSD
# 可选值: none | auto | client | server
window-decoration = auto
# 显示完整 GTK 标题栏（而非窗口管理器的简单标题栏）
gtk-titlebar = true
# GTK 标题栏风格：tabs 将标签栏合并进标题栏，节省垂直空间
# 可选值: native | tabs
gtk-titlebar-style = tabs
# 窗口副标题显示当前工作目录（仅 GTK，1.1.0+）
# 可选值: false | working-directory
window-subtitle = working-directory
# 窗口内边距（单位: pt，会根据 DPI 缩放）
window-padding-x = 8
window-padding-y = 8
# 自动平衡四边多余的像素间距，使网格居中
window-padding-balance = true
# 内边距区域颜色：extend 使用最近网格单元的背景色填充
# 可选值: background | extend | extend-always
window-padding-color = extend
# 背景不透明度（0 全透明 ~ 1 全不透明）
background-opacity = 0.95
# 将背景不透明度也应用到有显式背景色的单元格（如 Neovim/Tmux 重绘区域）
background-opacity-cells = true
# 背景模糊（需要合成器支持，KDE Plasma 上生效；true = 默认强度 20）
background-blur = true

# --- 交互行为 ---
# 选中即复制：clipboard 同时写入 selection 和 system 剪贴板
# 可选值: true | false | clipboard
copy-on-select = clipboard
# Shell 集成自动注入方式
# 可选值: none | detect | bash | elvish | fish | zsh
shell-integration = detect
# Shell 集成功能开关（逗号分隔，前缀 no- 禁用）
# cursor: 提示符处光标变为闪烁竖线
# sudo: 保留 terminfo 的 sudo 包装
# title: 通过 shell 集成设置窗口标题
# ssh-env: SSH 时自动转换 TERM 并传播环境变量
# ssh-terminfo: SSH 时自动在远端安装 Ghostty terminfo
shell-integration-features = cursor,sudo,title,ssh-env,ssh-terminfo
# 默认光标样式
# 可选值: block | bar | underline | block_hollow
cursor-style = block
# 打字时自动隐藏鼠标指针
mouse-hide-while-typing = true
# 关闭终端面板时不弹确认对话框
# 可选值: true | false | always
confirm-close-surface = false
# 新窗口/标签继承上一个窗口的工作目录
window-inherit-working-directory = true
# 新窗口/标签继承上一个窗口的字号
window-inherit-font-size = true
# 应用内通知控制（GTK toast）
# clipboard-copy: 复制时通知 | config-reload: 配置重载时通知
# 前缀 no- 禁用对应通知
app-notifications = no-clipboard-copy,config-reload
# 回滚缓冲区大小（单位: 字节，非行数！含当前屏幕，按面板独立计算）
# 10000000 ≈ 10 MB，内存按需分配不会立即占满
scrollback-limit = 10000000

# --- 快捷键 ---
# 格式: keybind = 触发键=动作
# 触发键用 + 连接修饰符和按键；动作用 : 传参
# 对齐 Windows Terminal 默认快捷键风格
# 自动方向分屏（Alt+Shift+D），Ghostty 无 auto 方向，用向右分屏代替
keybind = alt+shift+d=new_split:right
# 向下分屏（Alt+Shift+-）
keybind = alt+shift+minus=new_split:down
# 分屏间导航（Alt+方向键，与 Windows Terminal 一致）
keybind = alt+left=goto_split:left
keybind = alt+right=goto_split:right
keybind = alt+up=goto_split:top
keybind = alt+down=goto_split:bottom
  '';
}