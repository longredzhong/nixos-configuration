{
  config,
  lib,
  pkgs,
  ...
}:

let
  unstable-packages = with pkgs.unstable; [
    bat
    bottom
    coreutils
    curl
    du-dust
    fd
    findutils
    fx
    git
    git-crypt
    htop
    jq
    killall
    mosh
    procs
    ripgrep
    sd
    tmux
    tree
    unzip
    wget
    zip
    uv
    devenv
    buildkit
    pixi
    poetry
    pipx
    micromamba
  ];

  stable-packages = with pkgs; [
    wslu
    nvitop
    ffmpeg-full
    kubectl
    atuin
    jeezyvim

    # 开发工具
    gh
    just

    # 本地开发工具
    mkcert
    httpie

    # 语法分析
    tree-sitter

    # 格式化和代码检查工具
    alejandra
    deadnix
    shellcheck
    shfmt
    statix
    nixpkgs-fmt
    nixfmt-rfc-style
  ];
in
{
  home.packages = stable-packages ++ unstable-packages;
}
