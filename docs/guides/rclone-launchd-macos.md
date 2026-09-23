# Rclone Cloud Storage Mount with macOS Launchd & FUSE-T

## Overview: Remote Cloud Drives on macOS

Mounting cloud storage (Google Drive, OneDrive, Cloudflare R2, SFTP, WebDAV) as native local macOS directories provides seamless access for video editors, AI model storage, and offsite archives.

To make rclone mounts persistent, non-blocking, and stable across macOS sleep cycles, you need:
1. A modern user-space FUSE implementation (**FUSE-T**).
2. Proper VFS caching options (`--vfs-cache-mode full`).
3. A resilient `launchd` supervision definition.

---

## 1. Choosing the FUSE Driver: Why FUSE-T on Modern macOS

| Feature | **FUSE-T** (Recommended) | **macFUSE** (Legacy) |
|---|---|---|
| **Kernel Extension (KEXT)** | ❌ No KEXT needed (NFS loopback) | ⚠️ Requires KEXT |
| **Apple Silicon Security** | ✅ Runs in Full Security Mode | ⚠️ Requires Reduced Security in Recovery |
| **macOS Updates** | ✅ Survives major macOS upgrades | ⚠️ Frequently breaks on macOS point updates |
| **Installation** | `brew install macfuse-t` | `brew install macfuse` |

Install FUSE-T via Homebrew:
```bash
brew tap macfuse/fuse-t
brew install fuse-t
```

---

## 2. Optimized VFS Performance Parameters

Standard streaming mounts freeze or error out when applications seek backwards or edit large files. The following flags ensure local SSD speed caching with automatic background synchronization:

```bash
rclone mount remote_name:path/to/bucket /Volumes/CloudDrive \
  --vfs-cache-mode full \
  --vfs-cache-max-size 50G \
  --vfs-cache-max-age 24h \
  --vfs-read-chunk-size 64M \
  --vfs-read-chunk-size-limit 512M \
  --buffer-size 32M \
  --dir-cache-time 72h \
  --poll-interval 15s \
  --attr-timeout 1s \
  --network-mode \
  --daemon
```

### Parameter Breakdown:
- `--vfs-cache-mode full`: Caches entire files locally during read/write. Applications like Final Cut Pro, Ollama, and Steam behave exactly as if reading from local APFS.
- `--network-mode`: Informs macOS Finder that the filesystem is network-backed, preventing heavy thumbnail generation freezes.
- `--dir-cache-time 72h`: Keeps directory structures cached in RAM for instant folder navigation.

---

## 3. Production LaunchAgent Definition

Create `~/Library/LaunchAgents/com.lazymount.rclone.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lazymount.rclone.plist</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/rclone</string>
        <string>mount</string>
        <string>myremote:media</string>
        <string>/Volumes/CloudMedia</string>
        <string>--vfs-cache-mode</string>
        <string>full</string>
        <string>--vfs-cache-max-size</string>
        <string>50G</string>
        <string>--network-mode</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>NetworkState</key>
        <true/>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/rclone-mount.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/rclone-mount.err.log</string>
</dict>
</plist>
```

---

## 4. Unmounting Gracefully

To detach without leaving orphaned FUSE endpoints:

```bash
# Graceful unmount
umount /Volumes/CloudMedia

# Or via diskutil
diskutil unmount /Volumes/CloudMedia
```
