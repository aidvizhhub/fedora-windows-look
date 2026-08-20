#!/usr/bin/env bash
# Universal zram swap optimization (systemd + zram-generator; Ubuntu: zram-tools).
# Idempotent, non-interactive, agent-safe. Needs root (sudo).
# Usage:
#   bash scripts/apply-zram.sh [--dry-run] [zram_size_mb]
#   ZRAM_SIZE_MB=8192 bash scripts/apply-zram.sh     # explicit size
set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }
ZRAM_MB="${1:-}"
[ -z "$ZRAM_MB" ] && ZRAM_MB="${ZRAM_SIZE_MB:-}"

say()  { printf '[zram] %s\n' "$*"; }
run()  { say "> $*"; [ "$DRY" -eq 0 ] && "$@"; }

# --- RAM ----------------------------------------------------------------
MEM_KB=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
MEM_MB=$((MEM_KB / 1024))
if [ -z "$ZRAM_MB" ]; then
  ZRAM_MB=$((MEM_MB / 2))     # formula: RAM/2
fi
say "RAM: ${MEM_MB}MB ($((MEM_MB / 1024))G) -> zram-size = ${ZRAM_MB}MB ($((ZRAM_MB / 1024))G)"
say "Real memory when fully used ≈ ${ZRAM_MB}MB / 3.4 (zstd) ≈ $((ZRAM_MB * 100 / 340))MB"

# --- which mechanism does the distro use --------------------------------
if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-zram-setup@'; then
  MODE=zram-generator
elif [ -x /usr/bin/zramswap ] || [ -f /etc/default/zramswap ]; then
  MODE=zram-tools
else
  MODE=unknown
fi
say "mechanism: $MODE"

# --- 1. zram config ------------------------------------------------------
case "$MODE" in
  zram-generator)
    run sudo tee /etc/systemd/zram-generator.conf >/dev/null <<EOF
# zram: RAM/2, zstd (compression ~3.4:1 vs 2.7 lzo-rle), priority above disk swap
[zram0]
zram-size = $ZRAM_MB
compression-algorithm = zstd
swap-priority = 100
EOF
    say "Applies at REBOOT (size/algorithm). Live zram restart is dangerous when swap is in use (OOM) - do not do it with low free RAM."
    ;;
  zram-tools)
    run sudo tee /etc/default/zramswap >/dev/null <<EOF
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF
    say "Applies on zramswap service restart (systemctl restart zramswap)."
    ;;
  *)
    say "Neither zram-generator nor zram-tools found. Install: dnf install systemd-zram-generator (Fedora) / pacman -S zram-generator (Arch) / apt install zram-tools (Ubuntu)."
    ;;
esac

# --- 2. sysctl (applies IMMEDIATELY) ------------------------------------
run sudo tee /etc/sysctl.d/99-zram-vm.conf >/dev/null <<'EOF'
# zram optimizations: high swappiness (compressed swap in RAM is faster than
# disk — the kernel allows >100 for in-memory swap), single-page reads
vm.swappiness = 150
vm.page-cluster = 0
EOF
if [ "$DRY" -eq 0 ]; then
  sudo sysctl -w vm.swappiness=150 vm.page-cluster=0
fi

# --- 3. verify -----------------------------------------------------------
say "verify: zramctl; cat /proc/sys/vm/swappiness /proc/sys/vm/page-cluster"
if [ "$DRY" -eq 0 ]; then
  zramctl || true
  printf 'swappiness=%s page-cluster=%s\n' "$(cat /proc/sys/vm/swappiness)" "$(cat /proc/sys/vm/page-cluster)"
fi
say "done. swappiness/page-cluster work immediately; zstd algorithm after reboot."
