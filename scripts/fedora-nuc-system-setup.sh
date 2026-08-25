#!/usr/bin/env bash
# Fedora NUC 系统级初始化脚本（需 sudo 执行）
# 用法: sudo bash scripts/fedora-nuc-system-setup.sh
set -euo pipefail

DATA_DISK_UUID="2744660f-022d-43c2-a15d-515a924eac03"
USERNAME="longred"

echo "==> 1. 挂载数据盘到 /data"
mkdir -p /data
if ! grep -q "UUID=${DATA_DISK_UUID}" /etc/fstab; then
    echo "UUID=${DATA_DISK_UUID} /data btrfs defaults,noatime,compress=zstd 0 0" >> /etc/fstab
fi
mountpoint -q /data || mount /data

echo "==> 2. 创建服务数据目录并授权"
mkdir -p /data/garage/data /data/garage/meta /data/dufs
chown -R "${USERNAME}:${USERNAME}" /data

echo "==> 3. 启用 linger（用户服务开机自启，无需登录会话）"
loginctl enable-linger "${USERNAME}"

echo "==> 4. 安装输入法等系统级包（dnf）"
dnf install -y \
    fcitx5 fcitx5-chinese-addons fcitx5-configtool \
    fcitx5-gtk fcitx5-qt fcitx5-rime \
    podman-docker || true

echo "==> 完成。重启后用户级 systemd 服务（garage/dufs）将自动运行。"
echo "    验证: systemctl --user status garage dufs"
