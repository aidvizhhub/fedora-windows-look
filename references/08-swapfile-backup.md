# 08 · Disk swapfile as the OOM safety net (zram + disk combo)

Verified live: CachyOS (Fedora-based, btrfs on LUKS, 16G RAM). Result: 16G
swapfile on disk at priority 10 behind zram
(priority 100) — total swap capacity 24G; Linux degrades gracefully instead
of dying when RAM + zram run out.

## Why it matters

- zram alone has **no overflow**: it is compressed RAM, not a bottomless pit.
  When RAM + zram fill up, the kernel hits OOM — systemd-oomd kills the
  fattest process, or the system freezes.
- A disk swapfile is the **pressure-relief valve**: the kernel pages cold
  data out to disk, the system slows down but stays alive (no-swap "for
  speed" is the persistent bad advice that ends in random OOM kills).
- Tiered priorities do the right thing automatically: zram (fast, compressed
  RAM) fills first, the disk swapfile is used only when zram is exhausted.
- Bonus on LUKS root: the swapfile lives inside the encrypted filesystem →
  swap data is encrypted automatically, no separate crypttab setup needed.

## The setup (what was applied)

| Device | Type | Size | Priority | Role |
|---|---|---|---|---|
| /dev/zram0 | zram (zstd) | 8G | 100 | fast layer, used first |
| /swapfile | file, btrfs | 16G | 10 | overflow safety net |

Sizing: RAM (16G) + zram (8G) = 24G total — also the recommended size for
hibernation support (Manjaro guide). Red Hat's rule for 16G RAM is 8–16G of
swap; 16G disk + 8G zram fits.

### Sizing rule by RAM (owner's, verified on this host)

| RAM | disk swapfile | zram (RAM/2) | total swap |
|---|---|---|---|
| 8G | 32G | 4G | 36G |
| 16G | 16G (2x smaller — the "меньше в 2 раза" rule) | 8G | 24G |

This host: 16G RAM → 16G swapfile + 8G zram = 24G — exactly the rule.
Do NOT inflate swap beyond the rule: disk swap is an overflow valve, not
RAM — more swap means more OOM slack, not more speed. Re-size later in
one command anytime (225G free on this host).

## Steps (exactly what was run)

```bash
# 1. Create the swapfile on btrfs (preallocated + NODATACOW handled by the tool)
sudo btrfs filesystem mkswapfile --size 16G /swapfile
#    (btrfs-progs >= 6.1; supported by kernel >= 5.0)

# 2. Enable with priority BELOW zram (100) so zram is used first
sudo swapon -p 10 /swapfile

# 3. Persist across reboots
echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab
```

Verify:

```bash
swapon --show        # zram pri 100, /swapfile pri 10
free -h              # Swap total ~24G
```

Rollback (reversible):

```bash
sudo swapoff /swapfile
sudo rm /swapfile                       # remove the line from /etc/fstab too
```

## btrfs caveats (checked, all fine here)

- Swapfile must be **NODATACOW** and preallocated — `btrfs filesystem
  mkswapfile` does both (do NOT use `fallocate`).
- Single-device filesystem only — OK on a single LUKS disk.
- A subvolume containing an active swapfile **cannot be snapshotted** —
  snapper/timeshift must not snapshot the root subvolume while the swapfile
  is in it, or put the swapfile in its own subvolume (`/swap/swapfile`,
  `subvol=swap` in fstab). Verified on the target: snapper/timeshift
  inactive → root subvolume swapfile is fine.
- Active swapfile blocks `btrfs balance` on those block groups — cosmetic.

## When NOT to use / alternatives

- **Weak CPU + zstd already busy**: zram + disk swap is fine; nothing extra.
- **Swap on LUKS freeze reports (NixOS forum)**: a known edge case where
  swap-on-LUKS froze the system — rare, distro-specific; verify with a
  `stress-ng --vm` test if paranoid.
- **zswap instead of zram**: if you run zswap (compressed cache in front of
  disk swap), the disk swapfile is the backing store — different layout,
  keep swappiness ~50–100, not 150.
- Hibernation: btrfs swapfile hibernation is not reliably supported — use a
  dedicated swap partition if suspend-to-disk is required.

## Diagnose current state

```bash
swapon --show && zramctl && free -h
cat /proc/sys/vm/swappiness            # 150 = CachyOS default for zram, keep
grep swapfile /etc/fstab
```

## References

- BTRFS docs — swapfile support, limits (NODATACOW, single device, snapshots):
  https://btrfs.readthedocs.io/en/latest/Swapfile.html
- Oracle Linux 9 — swap files on btrfs (recommended placement in subvolume):
  https://docs.oracle.com/en/operating-systems/oracle-linux/9/btrfs/btrfs-CreatingSwapFilesonaBtrfsFileSystem.html
- Guy Rutenberg — mkswapfile (btrfs-progs 6.1+), encrypted swap notes:
  https://www.guyrutenberg.com/2024/12/14/setting-up-a-swap-file-on-btrfs/
- Manjaro forum — zram pri 100 + backing swapfile pri 0, sizing = RAM + zram:
  https://forum.manjaro.org/t/howto-add-a-backing-swap-device-to-zram-and-enable-hibernation/168639
- devopsaitoolkit — tiered swap: kernel fills higher-priority swap first:
  https://devopsaitoolkit.com/blog/tuning-linux-swap-and-zram-for-better-memory-performance/
- Big Iron — "Linux swap in 2026: zram vs NVMe vs no swap" (no-swap backfires):
  https://www.bigiron.cc/guides/linux-swap-in-2026-zram-vs-nvme-vs-no-swap
- enricopesce.it — zram vs zswap vs disk swap, when each fits:
  https://www.enricopesce.it/zram-zswap-linux-swap-configuration/
- linuxmind.dev — zram + swap best practices:
  https://linuxmind.dev/2025/09/02/optimize-memory-usage-with-zram-and-swap/
- Red Hat sizing (via Ask Ubuntu) — swap for 16G RAM:
  https://askubuntu.com/questions/49109/i-have-16gb-ram-do-i-need-32gb-swap
- NixOS discourse — swap file on LUKS edge case (freeze reports):
  https://discourse.nixos.org/t/swap-file-on-luks-partition/72234

## Related notes (from the same session, not applied)

- **nvidia-tweaks (ventureoo)** — reviewed, NOT applied: mostly redundant on
  CachyOS (modeset=1 already default; DynamicPowerManagement is laptop-only).
  The one interesting flag, `NVreg_InitializeSystemMemoryAllocations=0`,
  trades security for a small perf gain — not worth it. Sources:
  https://github.com/ventureoo/nvidia-tweaks
- **Discrete NVIDIA GPU with soldered VRAM** — cannot be increased. 2026
  verdict: keep textures Medium + FSR upscaling at 1080p; upgrade path is a
  used RTX 3060 12G (+59% 3DMark) or RX 6600 8G.
