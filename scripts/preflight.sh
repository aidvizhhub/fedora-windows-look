#!/usr/bin/env bash
# preflight.sh — read-only карта железа/ОС перед любым переносом на новый ПК.
# CHANGES NOTHING. Без sudo (--deep включает только sudo-ЧТЕНИЕ фактов).
# Сверяй результат с references/00-preflight.md (таблица гейтов по категориям).
# Usage: bash scripts/preflight.sh [--json] [--deep]
set -uo pipefail

JSON=0; DEEP=0
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    --deep) DEEP=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) ;;
  esac
done

K=()   # КЛЮЧ=VALUE
V=()   # КЛЮЧ=VALUE|группа (для вердиктов)

say(){ [ "$JSON" = 0 ] && printf '[preflight] %s\n' "$*"; }
kv(){ K+=("$1=$2"); say "$1=$2"; }
jline(){ [ "$JSON" = 1 ] && printf '{"%s":"%s"}\n' "$1" "$2"; }

get_key(){ # get_key KEY fallback-команда...
  local key="$1"; shift
  local out
  out="$("$@" 2>/dev/null | head -1 | tr -d '\r\n')"
  if [ -n "$out" ]; then kv "$key" "$out"; jline "$key" "$out"; else kv "$key" "UNKNOWN"; jline "$key" "UNKNOWN"; fi
}

sec(){ say ""; say "===== $1 ====="; }

# ---------- 1. ОС и сессия ------------------------------------------------
sec "OS / SESSION"
DISTRO=$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
VERSION=$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
DE="${XDG_CURRENT_DESKTOP:-UNKNOWN}"
SESSION_TYPE="${XDG_SESSION_TYPE:-UNKNOWN}"
kv "DISTRO" "${DISTRO:-UNKNOWN}"; jline "DISTRO" "${DISTRO:-UNKNOWN}"
kv "VERSION" "${VERSION:-UNKNOWN}"; jline "VERSION" "${VERSION:-UNKNOWN}"
kv "DE" "$DE"; jline "DE" "$DE"
kv "SESSION_TYPE" "$SESSION_TYPE"; jline "SESSION_TYPE" "$SESSION_TYPE"

# ---------- 2. Железо -----------------------------------------------------
sec "HARDWARE"
# GPU_VENDOR: nvidia/amd/intel/unknown
GPU_LINE=""
command -v lspci >/dev/null 2>&1 && GPU_LINE=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 || true)
GPU_VENDOR=UNKNOWN
echo "$GPU_LINE" | grep -qi nvidia && GPU_VENDOR=nvidia
echo "$GPU_LINE" | grep -qiE 'advanced micro devices|amd/ati|radeon' && GPU_VENDOR=amd
echo "$GPU_LINE" | grep -qiE 'intel corporation' && GPU_VENDOR=intel
kv "GPU_VENDOR" "$GPU_VENDOR"; jline "GPU_VENDOR" "$GPU_VENDOR"
echo "$GPU_LINE" | grep -qiE 'NVIDIA|AMD|Intel' && kv "GPU_MODEL" "$(echo "$GPU_LINE" | sed -E 's/^[^:]*:[[:space:]]*//')" || kv "GPU_MODEL" "UNKNOWN"

# GPU_DRIVER: nvidia-smi (nvidia), lspci -k (amd/intel), UNKNOWN
GPU_DRIVER=UNKNOWN
if [ "$GPU_VENDOR" = nvidia ]; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || true)
    [ -z "$GPU_DRIVER" ] && GPU_DRIVER=installed-no-smi
  else
    GPU_DRIVER=no-nvidia-smi
  fi
elif [ "$GPU_VENDOR" != UNKNOWN ]; then
  DRV=$(lspci -k 2>/dev/null | grep -A2 -iE 'vga|3d' | grep -i 'Kernel driver' | head -1 | awk '{print $NF}' || true)
  [ -n "$DRV" ] && GPU_DRIVER=$DRV
fi
kv "GPU_DRIVER" "$GPU_DRIVER"; jline "GPU_DRIVER" "$GPU_DRIVER"

# RAM_MB
if [ -r /proc/meminfo ]; then
  RAM_KB=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
  RAM_MB=$((RAM_KB / 1024))
  kv "RAM_MB" "$RAM_MB"; jline "RAM_MB" "$RAM_MB"
  kv "RAM_G" "$((RAM_MB / 1024))"; jline "RAM_G" "$((RAM_MB / 1024))"
else
  kv "RAM_MB" "UNKNOWN"; jline "RAM_MB" "UNKNOWN"
  kv "RAM_G" "UNKNOWN"; jline "RAM_G" "UNKNOWN"
fi

# CPU_X86_64_V3
V3=UNKNOWN
command -v /lib64/ld-linux-x86-64.so.2 >/dev/null 2>&1 && \
  /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q 'x86-64-v3' && V3=yes || V3=no
kv "CPU_X86_64_V3" "$V3"; jline "CPU_X86_64_V3" "$V3"

# SECURE_BOOT
SB=UNKNOWN
if command -v mokutil >/dev/null 2>&1; then
  SB_OUT=$(mokutil --sb-state 2>/dev/null | head -1 || true)
  if echo "$SB_OUT" | grep -qiE 'secure boot.*enabled'; then
    SB=on
  elif echo "$SB_OUT" | grep -qiE 'secure boot.*disabled|not enabled'; then
    SB=off
  else
    SB="unknown (${SB_OUT:-пустой вывод mokutil})"
  fi
else
  SB=no-mokutil
fi
kv "SECURE_BOOT" "$SB"; jline "SECURE_BOOT" "$SB"

# VIRT
VIRT=UNKNOWN
if command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT=$(systemd-detect-virt 2>/dev/null | head -1 || true)
  [ -z "$VIRT" ] && VIRT=none
fi
kv "VIRT" "$VIRT"; jline "VIRT" "$VIRT"

# CPU model (контекст)
command -v lscpu >/dev/null 2>&1 && kv "CPU_MODEL" "$(lscpu 2>/dev/null | awk -F': *' '/^Model name/{print $2; exit}')" || kv "CPU_MODEL" "UNKNOWN"

# ---------- 3. Система ----------------------------------------------------
sec "SYSTEM"
# ROOT_FS
ROOT_FS=UNKNOWN
command -v findmnt >/dev/null 2>&1 && ROOT_FS=$(findmnt -no FSTYPE / 2>/dev/null | head -1 || true)
[ -z "$ROOT_FS" ] && ROOT_FS=UNKNOWN
kv "ROOT_FS" "$ROOT_FS"; jline "ROOT_FS" "$ROOT_FS"

# SWAP_STATUS
SWAP_STATUS=UNKNOWN
HAVE_DISK=$([ "$(swapon --noheadings 2>/dev/null | wc -l)" -gt 0 ] && echo yes || echo no)
HAVE_ZRAM=$([ -n "$(zramctl --noheadings 2>/dev/null)" ] && echo yes || echo no)
case "$HAVE_ZRAM$HAVE_DISK" in
  yesyes) SWAP_STATUS=both ;;
  yesno)  SWAP_STATUS=zram ;;
  noyes)  SWAP_STATUS=disk ;;
  nono)   SWAP_STATUS=none ;;
esac
kv "SWAP_STATUS" "$SWAP_STATUS"; jline "SWAP_STATUS" "$SWAP_STATUS"
[ "$SWAP_STATUS" != none ] && say "  detail: $(swapon --show 2>/dev/null | tr '\n' ';' | cut -c1-120)" && zramctl --noheadings -o NAME,SIZE,ALGO 2>/dev/null | awk '{print "  zram: "$1" size="$2" algo="$3}' | head -2

# SHELL_VER (GNOME; для расширений EGO)
SHELL_VER=UNKNOWN
command -v gnome-shell >/dev/null 2>&1 && SHELL_VER=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
[ -z "$SHELL_VER" ] && SHELL_VER=UNKNOWN
kv "SHELL_VER" "$SHELL_VER"; jline "SHELL_VER" "$SHELL_VER"

# AUDIO_CODEC (первый HDA-кодек: перебор всех карт)
AUDIO_CODEC=UNKNOWN
for f in /proc/asound/card*/codec#*; do
  [ -r "$f" ] || continue
  C=$(grep -m1 'Codec:' "$f" 2>/dev/null | sed 's/Codec:[[:space:]]*//' || true)
  if [ -n "$C" ] && [ "$C" != UNKNOWN ]; then AUDIO_CODEC="$C"; break; fi
done
kv "AUDIO_CODEC" "$AUDIO_CODEC"; jline "AUDIO_CODEC" "$AUDIO_CODEC"

# MONITOR_INFO
MONITOR_INFO=UNKNOWN
if [ -d /sys/class/drm ]; then
  CONNECTED=$(ls /sys/class/drm/ 2>/dev/null | grep -E '^card[0-9]+-[^0-9]' | head -3 | tr '\n' ',' | sed 's/,$//' || true)
  [ -n "$CONNECTED" ] && MONITOR_INFO="$CONNECTED"
fi
kv "MONITOR_INFO" "$MONITOR_INFO"; jline "MONITOR_INFO" "$MONITOR_INFO"
# Модель монитора из EDID (первый подключённый; строки-маркеры в 54..71 байтах)
if command -v strings >/dev/null 2>&1; then
  EDID_MODEL=""
  for e in /sys/class/drm/*/edid; do
    [ -s "$e" ] || continue
    EDID_MODEL=$(strings "$e" 2>/dev/null | grep -vE '^[A-Z0-9]{4,}$' | awk 'length>2 && length<20' | head -1 || true)
    [ -n "$EDID_MODEL" ] && break
  done
  kv "MONITOR_MODEL" "${EDID_MODEL:-UNKNOWN}"; jline "MONITOR_MODEL" "${EDID_MODEL:-UNKNOWN}"
else
  kv "MONITOR_MODEL" "UNKNOWN"; jline "MONITOR_MODEL" "UNKNOWN"
fi

# ---------- 4. Сеть -------------------------------------------------------
sec "NETWORK"
NET=UNKNOWN
if command -v nmcli >/dev/null 2>&1; then
  NM_STATE=$(nmcli -t -f STATE general 2>/dev/null | head -1 || true)
  [ "$NM_STATE" = connected ] && NET=yes || NET=no
else
  ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && NET=yes || NET=no
fi
kv "NETWORK_ONLINE" "$NET"; jline "NETWORK_ONLINE" "$NET"

# ---------- 5. Дополнительно (--deep: sudo-чтение фактов) ----------------
if [ "$DEEP" = 1 ]; then
  sec "DEEP (sudo, только чтение)"
  if sudo -n true 2>/dev/null; then
    [ "$GPU_VENDOR" = nvidia ] && kv "NVIDIA_SMI" "$(sudo nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1)"
  else
    say "sudo без пароля недоступен — пропускаю DEEP-факты (или добавь право временно)"
  fi
fi

# ---------- 6. Вердикты по категориям ------------------------------------
sec "VERDICTS (по 00-preflight.md)"
verdict(){ # verdict <категория> <OK|ADAPT|SKIP> [причина]
  kv "VERDICT_$1" "$2${3:+: $3}"
}

# A. Внешний вид
case "$DE" in
  *GNOME*) verdict A-внешний-вид OK "DE=$DE" ;;
  *Cinnamon*) verdict A-внешний-вид ADAPT "DE=$DE: часть шагов устарела — см. 03 §Same look on Mint" ;;
  *) verdict A-внешний-вид ADAPT "DE=$DE: gsettings-шаги только для GNOME-подобных" ;;
esac

# B. Производительность
if [ "$VIRT" = kvm ] || [ "$VIRT" = qemu ] || [ "$VIRT" = oracle ]; then
  verdict B-производительность ADAPT "VIRT=$VIRT: НЕ маскировать qemu-агента и виртуальные службы (01)"
elif [ "$V3" != yes ]; then
  verdict B-производительность ADAPT "CPU_X86_64_V3=$V3: шаги до ядра OK, ядро CachyOS SKIP"
else
  verdict B-производительность OK "VIRT=$VIRT, CPU_X86_64_V3=$V3"
fi

# C. Железо и периферия
case "$AUDIO_CODEC" in
  *Realtek*) verdict C-железо-периферия OK "AUDIO_CODEC=$AUDIO_CODEC (11 применим)" ;;
  UNKNOWN)  verdict C-железо-периферия ADAPT "AUDIO_CODEC=UNKNOWN: 11 — только после ручной проверки /proc/asound" ;;
  *) verdict C-железо-периферия ADAPT "AUDIO_CODEC=$AUDIO_CODEC: 11 описан для Realtek, пути hda-verb могут отличаться" ;;
esac

# D. Софт и инструменты
[ "$NET" = yes ] && verdict D-софт-инструменты OK "NETWORK_ONLINE=$NET" \
                  || verdict D-софт-инструменты SKIP "NETWORK_ONLINE=$NET: 17 требует сети (npm-установка)"

# E. Сеть и удалённый доступ
if [ "$NET" != yes ]; then
  verdict E-сеть-удалёнка SKIP "NETWORK_ONLINE=$NET"
elif [ "$SESSION_TYPE" != wayland ]; then
  verdict E-сеть-удалёнка ADAPT "SESSION_TYPE=$SESSION_TYPE: 14 (хоткеи Wayland) — X11/other → другие механизмы"
else
  verdict E-сеть-удалёнка OK "SESSION_TYPE=$SESSION_TYPE (09 — только при наличии своего VPS; 19 — только с согласием владельца)"
fi

# F. Игры и контент
case "$GPU_VENDOR" in
  nvidia) verdict F-игры-контент OK "GPU_VENDOR=$GPU_VENDOR: 07 (direct scanout), 10 (NVENC) применимы" ;;
  amd|intel) verdict F-игры-контент ADAPT "GPU_VENDOR=$GPU_VENDOR: 10 → VAAPI вместо NVENC; 07 → свой путь (не nvidia)" ;;
  *) verdict F-игры-контент ADAPT "GPU_VENDOR=$GPU_VENDOR: проверить вручную перед 07/10/12" ;;
esac

# G. Аудит
verdict G-аудит OK "preflight+audit.sh (00) — фундамент, всегда применим"

# ---------- 7. Итог -------------------------------------------------------
sec "NEXT"
say "Итог: сравни свои VERDICT_* с таблицей гейтов в references/00-preflight.md."
say "Правило: референсы — ТОЛЬКО примеры; числа пересчитывай из фактов (RAM/2 для zram и т.д.)."
[ "$JSON" = 1 ] && printf '{"preflight_done":true,"keys":%d}\n' "${#K[@]}"
true
