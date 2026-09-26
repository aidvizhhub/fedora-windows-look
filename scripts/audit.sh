#!/usr/bin/env bash
# Read-only audit of a Linux desktop before optimization.
# CHANGES NOTHING. Usage: bash scripts/audit.sh [--help]
# Works on any systemd Linux (Fedora and similar).
set -uo pipefail

show_help() {
  cat <<'EOF'
usage: bash scripts/audit.sh [--help]

Read-only audit for speeding up a Linux desktop (Fedora/GNOME and similar):
OS, boot time, slow units, enabled services (mask candidates), failed
services, fstab vs real disks, memory/swap, GPU, boot errors.

Changes nothing; no privileges required (sudo only if present, for GPU).
See SKILL.md — "Speedup" section and its gotchas (how to read output).
EOF
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { show_help; exit 0; }

sec() { printf '\n===== %s =====\n' "$1"; }

sec "OS"
grep -E "^PRETTY_NAME" /etc/os-release 2>/dev/null || cat /etc/fedora-release 2>/dev/null

sec "BOOT (overall)"
systemd-analyze 2>/dev/null || echo "systemd-analyze unavailable"

sec "BOOT (blame, top-12)"
systemd-analyze blame 2>/dev/null | head -12

sec "BOOT (critical-chain)"
systemd-analyze critical-chain 2>/dev/null | head -12

sec "SERVICES: enabled (mask candidates)"
systemctl list-unit-files --state=enabled --no-pager 2>/dev/null \
  | grep -vE "dbus|getty|systemd-|user@|remote-fs" | awk '{print $1}' | sort | head -60

sec "SERVICES: failed"
systemctl --failed --no-pager 2>/dev/null | head -10

sec "FSTAB (cross-check UUIDs with lsblk -f!)"
grep -vE "^#|^$" /etc/fstab 2>/dev/null

sec "DISKS (lsblk -f)"
lsblk -f 2>/dev/null | head -14

sec "MEMORY"
free -h | head -2
swapon --show 2>/dev/null
echo "swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null) page-cluster=$(cat /proc/sys/vm/page-cluster 2>/dev/null)"

sec "VIRTUAL MACHINE?"
systemd-detect-virt 2>/dev/null || echo "unknown"

sec "CPU/GPU"
lspci 2>/dev/null | grep -iE "vga|3d|display" || echo "lspci unavailable"
sudo -n true 2>/dev/null && nvidia-smi --query-gpu=name,driver_version --format=csv 2>/dev/null

sec "x86_64_v3 SUPPORT (for custom kernels)"
/lib64/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -E "x86-64-v[23]" || echo "check manually"

sec "BOOT ERRORS (journal, tail)"
journalctl -b -p err --no-pager 2>/dev/null | tail -15 || echo "journalctl unavailable"

sec "DEVICE TIME-OUTS (journal)"
journalctl -b --no-pager 2>/dev/null | grep -iE "timed out|waiting for device" | head -5 \
  || echo "no timeouts found"

sec "LUKS (if any): how long did we wait for the password"
journalctl -b --no-pager 2>/dev/null | grep -E "systemd-cryptsetup@.*(Starting|Finished)" | head -4 \
  || echo "LUKS not used or journal unavailable"

sec "GNOME: extensions (each one = shell load)"
gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "not GNOME"

sec "DONE"
echo "Next — SKILL.md: Speedup §1 (timeouts), §2 (service masks), §3 (GNOME)."
echo "CHANGE NOTHING without the owner's consent; every change must have a rollback."
