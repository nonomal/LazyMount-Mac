#!/bin/bash

# ==========================================
# 本地覆盖配置文件 (mount_manager.local.sh)
# ==========================================

# --- Rclone 配置 ---
# RCLONE_ENABLED="true"                        # 如果不想启用 Rclone，改为 "false"
RCLONE_REMOTE="your-remote:/path/to/folder"    # 替换为你实际的 Rclone remote 名字和路径
RCLONE_MOUNT_POINT="$HOME/Mounts/CloudStorage" # 本地挂载点路径

# --- SMB 配置 ---
# SMB_ENABLED="true"                           # 如果不想启用 SMB，改为 "false"
SMB_IP="192.168.1.100"                         # 你的 NAS 或服务器 IP
SMB_USER="your_username"                       # 你的 SMB 用户名
SMB_SHARE="SharedFolder"                       # 共享文件夹的名称

# --- 稀疏磁盘映像 (Sparse Bundle) 配置 (可选) ---
# 如果你不需要挂载加密镜像，这两行留空或注释掉即可
BUNDLE_PATH="/Volumes/$SMB_SHARE/my_secure_disk.sparsebundle"
BUNDLE_VOLUME_NAME="MyPrivateDisk"