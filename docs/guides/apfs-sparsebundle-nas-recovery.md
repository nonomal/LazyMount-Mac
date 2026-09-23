# APFS Sparsebundle Recovery on Network Attached Storage (NAS)

## Introduction to APFS Sparsebundles over Network Shares

An **APFS sparsebundle** is Apple's segmented virtual disk format. Rather than a single monolithic file, it divides disk storage into 8MB chunks (called **bands**) stored in a directory structure:

```text
VolumeName.sparsebundle/
├── Info.bckup
├── Info.plist
├── bands/
│   ├── 0
│   ├── 1
│   └── ... (8MB band files)
├── token
└── lock
```

When stored on a remote NAS via SMB or NFS, this architecture allows dynamic capacity expansion without pre-allocating hundreds of gigabytes. However, network interruptions or unscheduled macOS reboots can leave lock markers and incomplete band commits, causing mounting errors like:

- `hdiutil: attach failed - Resource temporarily unavailable`
- `hdiutil: attach failed - Image not recognized`
- `Volume mounted as Read-Only (EROFS)`

---

## Technical Recovery Workflow

### 1. Clear Orphaned Token and Lock Files

When a client Mac disconnects abruptly, the SMB server or local cache may retain stale lock flags.

Navigate to the sparsebundle bundle root on your NAS:
```bash
cd "/Volumes/NAS-Share/VolumeName.sparsebundle"

# Check for lock files
ls -la token lock 2>/dev/null

# Safely remove stale lock tokens (ensure no other Mac is actively mounted!)
rm -f token lock
```

### 2. Inspect and Restore `Info.plist`

If the main `Info.plist` was truncated during a network drop:
```bash
# Verify Info.plist integrity
plutil -lint Info.plist

# If corrupted, restore from backup:
if [ $? -ne 0 ] && [ -f Info.bckup ]; then
    cp -v Info.bckup Info.plist
    plutil -lint Info.plist
fi
```

### 3. Attach Container in Non-Mounting Raw Mode

Attach the sparsebundle without mounting file systems to allow block-level repair:

```bash
hdiutil attach -nomount -noverify -noautofsck "/Volumes/NAS-Share/VolumeName.sparsebundle"
```

Output example:
```text
/dev/disk3          GUID_partition_scheme
/dev/disk3s1        Apple_APFS             7053534B-0000-11AA-AA11-00306543ECAC
/dev/disk4          Apple_APFS_Container
/dev/disk4s1        Apple_APFS_Volume      GameStorage
```

### 4. Run `fsck_apfs` File System Integrity Repair

Target the synthesized container node or specific APFS volume:

```bash
# Repair container and all member volumes
sudo fsck_apfs -y -x /dev/disk3s1
```

Flags explained:
- `-y`: Automatically respond 'yes' to repair inquiries
- `-x`: Mount container read-only if repairs fail, preventing cascading damage

If `fsck_apfs` returns exit code `0`, the container superblocks, object maps, and snapshot checkpoints are consistent.

### 5. Detach Block Device

```bash
hdiutil detach /dev/disk3
```

---

## Best Practices for Network Sparsebundles

1. **Optimize Band Size for SMB Performance**  
   The default 8MB band size generates thousands of network metadata requests for large files. When creating new sparsebundles for NAS gaming or 4K video, use **64MB bands**:
   ```bash
   hdiutil create -size 1000g -type SPARSEBUNDLE -fs APFS -volname "FastStorage" -imagekey sparse-band-size=131072 FastStorage.sparsebundle
   ```

2. **Network MTU & SMB Multipath**  
   Ensure your local Ethernet / Wi-Fi supports 1500 MTU (or 9000 Jumbo Frames if end-to-end Gigabit switches and NAS NICs support it) to avoid packet fragmentation during high-throughput APFS writes.

3. **Deploy LazyMount-Mac for Continuous Watchdogging**  
   LazyMount-Mac tracks network availability before attempting mount, executes clean detach during shutdowns, and automatically detects dirty states before they impact user applications.
