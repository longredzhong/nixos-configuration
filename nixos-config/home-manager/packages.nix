{ config, lib, pkgs, ... }:

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
    micromamba
    pixi
  ];

  stable-packages = with pkgs; [
    wslu
    nvitop
    ffmpeg-full
    kubectl
    atuin
    gcc
    gnumake
    kubernetes-helm
    envsubst
    cachix
    cmake
    jeezyvim
    
    # 开发工具
    gh
    just
    
    # 语言支持
    rustup
    
    # Rust 工具
    cargo-cache
    cargo-expand
    
    # 本地开发工具
    mkcert
    httpie
    
    # 语法分析
    tree-sitter
    
    # 语言服务器
    nodePackages.vscode-langservers-extracted
    nodePackages.yaml-language-server
    nil
    
    # 格式化和代码检查工具
    alejandra
    deadnix
    nodePackages.prettier
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
