# 共享的 Shell 配置（别名、环境变量等）
# 被 fish.nix 和 bash.nix 共同引用
{ config, lib, ... }:
let
  # -------- 共享路径 --------
  extraPaths = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/.pixi/bin"
    "$HOME/go/bin"
  ];

  # -------- 共享环境变量 --------
  envVars = {
    PIXI_CACHE_DIR = "$HOME/.cache/rattler/cache";
    UV_CACHE_DIR = "$HOME/.cache/rattler/cache/uv-cache";
    # 让 micromamba / conda 使用与 pixi/rattler 同一缓存根目录（但使用独立子目录以避免布局冲突）
    CONDA_PKGS_DIRS = "$HOME/.cache/rattler/cache/conda-pkgs";
    MAMBA_ROOT_PREFIX = "$HOME/.cache/rattler/cache/micromamba";
    EDITOR = "nano";
    VISUAL = "nano";
  };

  # -------- 代理配置 --------
  defaultProxy = "127.0.0.1:7890";
  noProxyList = "localhost,127.0.0.1,::1,100.64.0.0/10,172.16.100.10";

  # -------- 共享别名 --------
  commonAliases = {
    # 系统信息
    sysfetch = "fastfetch";
    sysinfo = "btop";
    diskspace = "duf";
    dirsize = "ncdu";

    # 目录导航
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";
    "....." = "cd ../../../..";

    # eza 替代 ls
    l = "eza -1 --icons";
    ll = "eza -l -g --icons";
    la = "eza -la -g --icons";
    lt = "eza --tree --level=2 --icons";
    lta = "eza --tree --level=2 --icons -a";

    # Git 快捷命令
    gs = "git status -sb";
    ga = "git add";
    gaa = "git add -A";
    gc = "git commit";
    gcm = "git commit -m";
    gca = "git commit --amend";
    gco = "git checkout";
    gcob = "git checkout -b";
    gst = "git status";
    gdh = "git diff HEAD";
    gd = "git diff";
    gds = "git diff --staged";
    gp = "git push";
    gpl = "git pull";
    gph = "git push -u origin HEAD";
    gl = "git log --oneline --graph --decorate -20";
    gla = "git log --oneline --graph --decorate --all";
    glog = "lazygit";
    gsl = "git stash list";
    gsp = "git stash push -m";
    gsa = "git stash apply";
    gsd = "git stash drop";

    # Docker 快捷命令
    dps = "docker ps";
    dpsa = "docker ps -a";
    dls = "docker container ls";
    dimg = "docker images";
    drun = "docker run -it --rm";
    dexec = "docker exec -it";
    dlogs = "docker logs -f";
    dstop = "docker stop";
    drm = "docker rm";
    drmi = "docker rmi";
    dprune = "docker system prune -af --volumes";
    dc = "docker compose";
    dcu = "docker compose up -d";
    dcd = "docker compose down";
    dcl = "docker compose logs -f";

    # 网络工具
    myip = "curl -s ifconfig.me/ip";
    myipinfo = "curl -s ifconfig.me/all.json | jq";
    ports = "ss -tulnp";
    pingg = "ping -c 5 google.com";

    # 快速编辑配置
    conf = "cd ~/nixos-configuration";
    edithosts = "sudo $EDITOR /etc/hosts";
    editflake = "$EDITOR ~/nixos-configuration/flake.nix";

    # Nix 相关
    nixgc = "sudo nix-collect-garbage -d";
    nixoptimize = "sudo nix-store --optimise";
    nixupdate = "cd ~/nixos-configuration && nix flake update && cd -";

    # 安全相关
    rm = "rm -i";
    cp = "cp -i";
    mv = "mv -i";

    # 其他实用命令
    cls = "clear";
    h = "history";
    df = "df -h";
    du = "du -h";
    free = "free -h";
    grep = "grep --color=auto";
  };
in
{
  # 导出变量供其他模块使用
  options.shell = {
    extraPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = extraPaths;
      description = "Extra paths to add to PATH";
    };
    envVars = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = envVars;
      description = "Environment variables";
    };
    defaultProxy = lib.mkOption {
      type = lib.types.str;
      default = defaultProxy;
      description = "Default proxy address";
    };
    noProxyList = lib.mkOption {
      type = lib.types.str;
      default = noProxyList;
      description = "No proxy list";
    };
    commonAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = commonAliases;
      description = "Common shell aliases";
    };
  };
}
