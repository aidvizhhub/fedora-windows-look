# 05 · zram swap optimization (universal)

Verified: Fedora (systemd-zram-generator, 16G RAM). Works on any systemd-Linux.
Result: zram RAM/2 on zstd (~3.4:1), swappiness 150, page-cluster 0 — cold
pages are compressed in RAM, free memory goes to page cache.

## Why it matters

- Compressed swap in RAM is **10+× faster than NVMe** (kernel docs) — the
  kernel happily pushes cold anonymous pages into zram, RAM goes to cache.
- The default Fedora zram works, but with disk-oriented sysctls
  (swappiness=10, page-cluster=3) — it is under-used.
- zstd compresses ~3.4:1 vs 2.7 of lzo-rle — ~20% more effective memory.

## Size formula (the main thing)

```
zram-size (MB) = RAM (MB) / 2
```

| RAM | zram-size | example |
|---|---|---|
| 8G | 4096 | laptop |
| 16G | 8192 | desktop |
| 32G | 16384 | power desktop |
| 64G | 32768 | (Fedora default caps at 8192 — explicit config required) |

- **Real memory when fully used** ≈ zram-size / ratio: zstd ~3.37 → 8192MB
  ≈ 2.4G real (lzo-rle 2.74, lz4 2.63).
- Fedora default (zram-generator-defaults): `zram-size = min(ram, 8192)` with
  **lzo-rle** — for ≤16G it is already RAM/2, but with the weaker algorithm.
- Desktop/laptop — RAM/2. VPS/server with big RAM — RAM/2 is fine too; if CPU
  is scarce — RAM/4.

## Values (and why)

| Parameter | Value | Rationale |
|---|---|---|
| `compression-algorithm` | `zstd` | ratio 3.37 vs 2.74 lzo-rle (+~20% memory); slower to decompress but reads less. lz4 — weak CPU (faster, ratio 2.63) |
| `vm.swappiness` | `150` (up to 180) | kernel docs: for in-memory swap (zram/zswap) values >100 are allowed; "random I/O faster than NVMe 10+×" → the kernel happily evicts anon pages to zram, RAM frees for cache. CachyOS reference uses 150; kernel maintainers recommend 180 |
| `vm.page-cluster` | `0` | default 3 is disk swap-readahead from 2005. For zram: read one page at a time (ChromeOS default, Android practice). Readahead gives nothing for zstd |
| `swap-priority` | `100` | above disk swap (usually -2/10) — zram used first |

## Steps (ready script — below)

1. `bash scripts/apply-zram.sh [--dry-run] [zram_size_mb]` — detects the
   mechanism (zram-generator vs zram-tools), computes RAM/2, writes config +
   sysctl, applies sysctl immediately. Needs sudo.
2. If zram is not enabled at all: install `systemd-zram-generator` (dnf/pacman)
   or `zram-tools` (apt) — the script says what is missing.
3. **Reboot** to change size/algorithm (the generator recreates /dev/zram0 at boot).
4. Verify: `zramctl` (algorithm/size/usage), `swapon --show`,
   `cat /proc/sys/vm/swappiness /proc/sys/vm/page-cluster`, `free -h`.

## Safety of applying (important)

- **Do NOT restart zram on a live system** if swap holds data and free RAM is
  low: `swapoff` pulls 2G+ back into RAM → OOM-kill. Algorithm/size change by
  reboot only.
- sysctl (swappiness/page-cluster) applies **immediately** — `sysctl -w` or
  `sysctl --system` after writing the file into /etc/sysctl.d/.
- swappiness 150 is NOT for disk swap (only zram/zswap — there it's a disaster:
  disk thrash).
- page-cluster 0 is NOT for disk swap (loses readahead on HDD/SSD).

## Diagnose current state

```bash
zramctl                    # algorithm/size/usage
swapon --show              # swap devices, priorities
cat /proc/sys/vm/swappiness /proc/sys/vm/page-cluster
cat /etc/systemd/zram-generator.conf /usr/lib/systemd/zram-generator.conf 2>/dev/null
```

Common Fedora picture: zram exists (default, lzo-rle, min(ram,8192)) but
swappiness=10 and page-cluster=3 — disk-swap parameters, zram under-used.

## When NOT to use

- Machine with disk swap and no zram → different solution (swappiness 10, page-cluster 3).
- Weak CPU + very loaded memory (VPS 1 vCPU): zstd eats CPU — consider lz4.
- zswap with active disk spill → swappiness 50-100, not 150.

## References

- Kernel docs (zram, swappiness >100 for in-memory swap, page-cluster):
  https://docs.kernel.org/admin-guide/blockdev/zram.html and
  https://www.kernel.org/doc/html/latest/admin-guide/sysctl/vm.html
- ArchWiki Zram (high swappiness ideal for zram): https://wiki.archlinux.org/title/Zram
- Algorithm benchmarks + page-cluster (zstd 3.37, lz4 2.63, lzo-rle 2.74):
  https://www.reddit.com/r/Fedora/comments/mzun99/new_zram_tuning_benchmarks/
- zram-generator config: https://github.com/systemd/zram-generator
- Ubuntu zram-tools (/etc/default/zramswap): ALGO/PERCENT/PRIORITY
