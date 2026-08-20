# 06 · Disk formatting on Fedora

Workflow: identify → unmount → format → mount → fstab (if internal) → verify write.

## Why it matters

- Most "can't write to disk" cases are NOT a broken filesystem — they are a
  dirty NTFS flag or permissions. Reformatting destroys data; the non-destructive
  fix is 30 seconds.
- Correct fstab entries (nofail + timeout) mean an absent disk never hangs boot.

## Safety rules

- **ALWAYS run `lsblk -f` first and confirm the exact device with the user
  before any destructive command.**
- Reformatting erases ALL data. Warn explicitly and list what the user will lose.
- Never format a mounted filesystem or the system disk (check `lsblk -f`
  MOUNTPOINTS: `/`, `/home`, `/boot` are system).
- Double-check that `sdb1` in the plan really is the user's data disk, not the
  installer stick or another disk with data.
- Use `sudo -n` first; if it fails, use plain `sudo` (user's password prompt).
- After `mkfs`, run `sync`.

## Why a disk can't be written to (check BEFORE reformatting)

Reformatting is the LAST resort, not the first fix:

1. **NTFS mounted read-only** (`mount | grep fuseblk` shows `(ro,...)`, journal
   shows ntfs-3g "Read-Only"): the volume has a "dirty" flag from Windows fast
   startup / hibernation / unclean shutdown. Fix WITHOUT data loss:
   - `umount /dev/sdXN` (or `udisksctl unmount -b /dev/sdXN`)
   - `sudo ntfsfix /dev/sdXN` (clears dirty flag, does not touch data)
   - Remount (replug or `udisksctl mount -b /dev/sdXN`) and verify with `touch`.
   - Still read-only? Windows-side fix: disable Fast Startup
     (powercfg /h off), run `chkdsk X: /f`.
2. **vfat/FAT32 file size limits** (file > 4 GB impossible). Fix: exFAT or NTFS.
3. **ext4 "read-only file system"**: `sudo dmesg | tail` for I/O errors; check
   SMART `sudo smartctl -a /dev/sdX`. A dying disk must NOT be reformatted —
   copy data first.
4. **Permissions**: dirs owned by root (`sudo chown -R $USER:$USER <dir>`).

## Identify the disk

```bash
lsblk -f
# FSTYPE shows current fs, MOUNTPOINT shows if mounted
sudo blkid /dev/sdXN          # exact type/UUID
```

## Unmount

```bash
umount /dev/sdXN               # if automounted under /run/media/...
udisksctl unmount -b /dev/sdXN # alternative
```

## Format

| Goal | Command | Notes |
| --- | --- | --- |
| Fedora data disk | `sudo mkfs.ext4 -F -L DATA /dev/sdXN` | recommended for plain storage |
| Fedora system-ish | `sudo mkfs.btrfs -f -L DATA /dev/sdXN` | snapshot/compression (Fedora root is btrfs) |
| NTFS (Windows compat) | `sudo mkfs.ntfs -f -L DATA /dev/sdXN` | needs `ntfs-3g` package |
| exFAT (USB, >4GB files, cross-platform) | `sudo mkfs.exfat -n DATA /dev/sdXN` | needs `exfatprogs` |
| FAT32 (small USB) | `sudo mkfs.fat -F 32 -n DATA /dev/sdXN` | file size limit 4 GB |

**Permission note**: `mkfs.ext4` without sudo fails with permission denied —
always run with sudo.

## Mount + ownership

```bash
sudo mkdir -p /home/$USER/DATA
sudo mount /dev/sdXN /home/$USER/DATA
sudo chown $USER:$USER /home/$USER/DATA
```

Do NOT pass `uid=`/`gid=` to `mount` for ext4 — ext4 rejects unknown options
(`Unknown parameter 'uid'`). chown after mount instead. `uid=1000` belongs to
FAT/exFAT mounts only.

## Auto-mount at boot (internal disks) — /etc/fstab

```bash
UUID=$(sudo blkid -s UUID -o value /dev/sdXN)
echo "UUID=$UUID /home/$USER/DATA ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2" | sudo tee -a /etc/fstab
```

- `nofail` + `x-systemd.device-timeout=10`: no boot hang if the disk is absent.
- Verify: `grep -v "^#" /etc/fstab | tail`, then `sudo systemctl daemon-reload`.

## Verify write

```bash
mkdir -p /home/$USER/DATA/test && touch /home/$USER/DATA/test/file.txt && echo OK && rm -rf /home/$USER/DATA/test
lsblk -f /dev/sdX
```

## NTFS quirks after formatting

- ntfs-3g (FUSE) automounts via udisks2 under `/run/media/<user>/<UUID>`; if the
  dirty flag is set it mounts read-only — see "Why a disk can't be written to".
- `ntfsfix -n` is a dry-run check; the real fix is `ntfsfix` without `-n`.
