{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = {
    home.packages = lib.mkMerge [
      # Python 包
      (lib.mkIf (builtins.elem "python" config.custom.development.languages) (
        with pkgs;
        [
          # Python 解释器和基础工具
          python312
          python312Packages.pip
          python312Packages.setuptools
          python312Packages.wheel

          # 语言服务器和编辑器集成
          pyright
          python311Packages.python-lsp-server

          # 有用的库和工具
          poetry
          pipx
          micromamba
          uv
        ]
      ))

      # Rust 包
      (lib.mkIf (builtins.elem "rust" config.custom.development.languages) (
        with pkgs;
        [
          # Rust 编译器和包管理器
          rustup

          # 构建工具和实用程序
          cmake
          pkg-config

          # 额外的 cargo 工具
          cargo-edit
          cargo-update
          cargo-audit
          cargo-watch
        ]
      ))

      # Node.js/JavaScript 包
      (lib.mkIf (builtins.elem "node" config.custom.development.languages) (
        with pkgs;
        [
          # Node.js 运行时和包管理器
          nodejs_20
          nodePackages.npm
          nodePackages.yarn
          nodePackages.pnpm

          # 语言服务器和开发工具
          nodePackages.typescript
          nodePackages.typescript-language-server
          nodePackages.eslint
          nodePackages.prettier

          # 构建工具
          nodePackages.webpack
        ]
      ))

      # Go 包
      (lib.mkIf (builtins.elem "go" config.custom.development.languages) (
        with pkgs;
        [
          # Go 编译器和工具
          go
          gopls
          goreleaser
          golangci-lint

          # 开发工具
          delve # Go 调试器
          go-tools # 包含各种开发工具
          gotools # 官方工具集
        ]
      ))

      # Java 包
      (lib.mkIf (builtins.elem "java" config.custom.development.languages) (
        with pkgs;
        [
          # JDK 和构建工具
          jdk17
          maven
          gradle

          # 语言服务器
          jdt-language-server

          # 开发工具
          spring-boot-cli
          checkstyle
        ]
      ))

      # C/C++ 包
      (lib.mkIf (builtins.elem "cpp" config.custom.development.languages) (
        with pkgs;
        [
          # 编译器和构建工具
          gcc
          clang
          clang-tools
          cmake
          gnumake
          ninja

          # 语言服务器和开发工具
          ccls
          bear # 生成 compilation database
          gdb
          lldb

          # 静态分析和格式化工具
          cppcheck
        ]
      ))

      # Nix 包
      (lib.mkIf (builtins.elem "nix" config.custom.development.languages) (
        with pkgs;
        [
          # Nix 语言支持：nix 包管理器、格式化工具和语言服务器
          nix
        ]
      ))
    ];

    programs.bash.initExtra = lib.concatStrings [
      # Python bash hooks
      (lib.optionalString (builtins.elem "python" config.custom.development.languages) ''
        export PYTHONPATH="$HOME/.local/lib/python3.11/site-packages:$PYTHONPATH"
      '')

      # Rust bash hooks
      (lib.optionalString (builtins.elem "rust" config.custom.development.languages) ''
        export CARGO_HOME="$HOME/.cargo"
        export PATH="$CARGO_HOME/bin:$PATH"
      '')

      # Node.js bash hooks
      (lib.optionalString (builtins.elem "node" config.custom.development.languages) ''
        export NPM_CONFIG_PREFIX="$HOME/.npm-global"
        export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
      '')

      # Go bash hooks
      (lib.optionalString (builtins.elem "go" config.custom.development.languages) ''
        export GOPATH="$HOME/go"
        export PATH="$GOPATH/bin:$PATH"
      '')

      # Java bash hooks
      (lib.optionalString (builtins.elem "java" config.custom.development.languages) ''
        export JAVA_HOME="${pkgs.jdk17.home}"
        export MAVEN_OPTS="-Xmx2048m"
      '')
    ];

    programs.fish.interactiveShellInit = lib.concatStrings [
      # Python fish hooks
      (lib.optionalString (builtins.elem "python" config.custom.development.languages) ''
        set -x PYTHONPATH $HOME/.local/lib/python3.11/site-packages $PYTHONPATH
      '')

      # Rust fish hooks
      (lib.optionalString (builtins.elem "rust" config.custom.development.languages) ''
        set -x CARGO_HOME $HOME/.cargo
        set -p PATH $CARGO_HOME/bin
      '')

      # Node.js fish hooks
      (lib.optionalString (builtins.elem "node" config.custom.development.languages) ''
        set -x NPM_CONFIG_PREFIX $HOME/.npm-global
        set -p PATH $NPM_CONFIG_PREFIX/bin
      '')

      # Go fish hooks
      (lib.optionalString (builtins.elem "go" config.custom.development.languages) ''
        set -x GOPATH $HOME/go
        set -p PATH $GOPATH/bin
      '')

      # Java fish hooks
      (lib.optionalString (builtins.elem "java" config.custom.development.languages) ''
        set -x JAVA_HOME ${pkgs.jdk17.home}
        set -x MAVEN_OPTS "-Xmx2048m"
      '')
    ];
  };
}
