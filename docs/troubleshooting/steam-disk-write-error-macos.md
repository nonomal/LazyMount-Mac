# Troubleshooting: Steam Disk Write Error on macOS with NAS / Sparsebundle Storage

## Problem Overview

When running Steam game libraries on external network storage (such as Synology, QNAP, TrueNAS, or Unraid via SMB) or within an **APFS sparsebundle** disk image on macOS, games may fail to download, update, or launch, presenting the classic error:

```text
An error occurred while updating [Game] (disk write error)
```

In the macOS Console (`log stream --predicate 'subsystem contains "com.valvesoftware.steam"'`), you will often observe `EACCES (Permission denied)`, `EROFS (Read-only file system)`, or `EBUSY (Resource busy)` errors when Steam attempts to write payload chunks into `steamapps/downloading/`.

---

## Root Causes

1. **Dirty / Inconsistent APFS Sparsebundle Journal**  
   When macOS enters sleep or experiences a transient Wi-Fi disconnect, network SMB file locks drop abruptly. The underlying APFS container inside the sparsebundle becomes marked as "dirty" (journal not committed). Upon reconnection, macOS automatically mounts the container in **read-only mode** to protect against file system corruption.

2. **SMB POSIX Locking & Opportunistic Locks (Oplocks)**  
   Steam uses non-blocking file locking and memory-mapped files (`mmap`) extensively. SMB network shares without proper locking semantics often fail or delay lock grants, causing Steam's multi-threaded download engine to abort with a write error.

3. **Finder / CoreServices File Shadow Locks**  
   Finder metadata indexers (`mds`, `Spotlight`) and `.DS_Store` updates may briefly hold write locks on active game asset folders while Steam is writing shader caches or game blobs.

---

## Step-by-Step Manual Recovery

If you encounter this state before automated self-healing kicks in:

### Step 1: Terminate Steam and Release Locked Processes

Quit Steam completely:
```bash
killall -9 steam_osx 2>/dev/null || true
```

Check if any background process is keeping the mount point busy:
```bash
# Replace /Volumes/SteamGames with your mount path
lsof +D /Volumes/SteamGames
```

### Step 2: Detach the Sparsebundle Device

Unmount the volume:
```bash
# Graceful unmount
diskutil unmount /Volumes/SteamGames

# If busy or unresponsive, force unmount:
diskutil unmount force /Volumes/SteamGames
```

Find and detach the underlying virtual disk node (`/dev/diskX`):
```bash
hdiutil info | grep -B 2 -A 4 "SteamGames"
# Detach the associated virtual disk
hdiutil detach /dev/disk4 -force
```

### Step 3: Attach in Diagnostic Mode Without Auto-Mounting

Attach the raw disk image without mounting the APFS volume:
```bash
# Bypass verification for quick attachment to inspect the block device
hdiutil attach -nomount -noverify "/Volumes/NAS-Share/SteamGames.sparsebundle"
```

Note the assigned disk identifier output by the command (e.g., `/dev/disk4s1` or `/dev/disk4s2`).

### Step 4: Repair APFS Container with `fsck_apfs`

Run the APFS consistency check with the auto-repair flag (`-y`):
```bash
sudo fsck_apfs -y /dev/disk4s1
```

Look for confirmation:
```text
** The volume SteamGames was found to be corrupt and was repaired.
** The container /dev/disk4s1 appears to be OK.
```

### Step 5: Detach and Remount via LazyMount

Detach diagnostic device:
```bash
hdiutil detach /dev/disk4
```

Trigger LazyMount-Mac reconciliation:
```bash
# Execute your local mount manager
~/mount_manager.sh
```

---

## Automated Prevention via LazyMount-Mac

LazyMount-Mac was designed specifically to prevent and auto-resolve this failure loop:

- **Launchd Lifecycle Keep-Alive**: Detects system wake-up from sleep and validates SMB socket health before allowing APFS attach.
- **`-noverify` Attach Optimization**: Bypasses full checksum recalculation across high-latency network links during boot, eliminating 60+ second timeouts that leave images in half-attached states.
- **Non-Destructive Liveness Probe**: Employs lightweight `df` status checking against the volume root rather than deep file read/write loops, preventing false-positive disconnects on high-latency Wi-Fi.
- **Pre-Emptive Sparsebundle Auto-Recovery**: If a volume is reported read-only or unreachable, LazyMount detaches the corrupted node, executes `fsck_apfs`, and remounts with verified read-write privileges.

---

## Verified SMB Server Configuration (Samba)

If you control your NAS Samba configuration (`/etc/samba/smb.conf`), add the following fruit/APFS compatibility options:

```ini
[SteamGames]
    path = /mnt/storage/SteamGames
    read only = no
    guest ok = no
    fruit:model = Macmini
    fruit:time machine = no
    fruit:posix_locking = yes
    vfs objects = catia fruit streams_xattr
```
