# Automounting SMB Shares on macOS Using Launchd

## Why Native macOS Login Items Fall Short

Many macOS users configure SMB network shares by adding them to **System Settings → General → Login Items**. While simple, this approach presents significant operational shortcomings:

1. **GUI Popup Clutter**: Finder opens a separate GUI window for every mounted volume upon login.
2. **Network Race Conditions**: At system boot or wake, Wi-Fi or VPN (Tailscale, WireGuard) often connects several seconds *after* login items fire, leading to "Server connection failed" modal dialogs.
3. **Zero Self-Healing**: If the NAS reboots, Wi-Fi drops, or the Mac changes access points, native mounts silently freeze or disconnect without reconnecting.

---

## The Launchd Solution Architecture

Using a macOS **LaunchAgent** (`~/Library/LaunchAgents/com.lazymount.plist`) combined with an idempotent mount script provides:

- **Silent background execution** (no Finder popups).
- **Pre-mount network socket verification** (`ping` / `nc` before issuing `mount_smbfs`).
- **Sleep/Wake monitoring** via `KeepAlive` or `WatchPaths`.
- **Decoupled credential management** via macOS Keychain.

---

## 1. Secure Credential Storage in macOS Keychain

Never hardcode plain-text NAS passwords in scripts. Use macOS's built-in `security` CLI to store and retrieve credentials securely:

### Store Credential
```bash
security add-internet-password \
  -a "nas_user" \
  -s "nas.local" \
  -w "SecretPassword123" \
  -r "smb " \
  -D "Network Password" \
  -l "LazyMount SMB NAS"
```

### Retrieve Credential Inside Mount Scripts
```bash
NAS_PASS=$(security find-internet-password -s "nas.local" -a "nas_user" -w)
```

---

## 2. Idempotent SMB Mount Routine

Create a robust mount function that verifies whether the target directory is already an active mount point:

```bash
#!/usr/bin/env bash
set -euo pipefail

MOUNT_DIR="/Volumes/NAS_Games"
SERVER="nas.local"
SHARE="Games"
USER="nas_user"

# 1. Verify network socket is reachable on SMB port 445
if ! nc -z -G 2 "${SERVER}" 445; then
    echo "[WARN] Server ${SERVER}:445 unreachable. Skipping mount."
    exit 0
fi

# 2. Check if already mounted
if mount | grep -q "on ${MOUNT_DIR} (smbfs"; then
    echo "[INFO] ${MOUNT_DIR} is already mounted."
    exit 0
fi

# 3. Create mount point directory
mkdir -p "${MOUNT_DIR}"

# 4. Fetch password securely
PASS=$(security find-internet-password -s "${SERVER}" -a "${USER}" -w)

# 5. Mount via native mount_smbfs
mount_smbfs "//${USER}:${PASS}@${SERVER}/${SHARE}" "${MOUNT_DIR}"
echo "[SUCCESS] Mounted ${SHARE} to ${MOUNT_DIR}"
```

---

## 3. Configuring LaunchAgent Plist

Place this file at `~/Library/LaunchAgents/com.lazymount.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lazymount.plist</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOUR_USERNAME/mount_manager.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>StandardOutPath</key>
    <string>/tmp/lazymount.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/lazymount.stderr.log</string>
</dict>
</plist>
```

### Load and Activate LaunchAgent

```bash
# Validate plist syntax
plutil -lint ~/Library/LaunchAgents/com.lazymount.plist

# Load daemon into launchd
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.lazymount.plist
```
