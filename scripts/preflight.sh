#!/usr/bin/env bash
# preflight.sh — read-only карта железа/ОС перед любым переносом на новый ПК.
# CHANGES NOTHING. Без sudo (--deep включает только sudo-ЧТЕНИЕ фактов).
# Сверяй результат с references/00-preflight.md (таблица гейтов по категориям).
# Usage: bash scripts/preflight.sh [--json] [--deep]
set -uo pipefail
export LC_ALL=C   # стабильный разбор подписей (pactl/nvidia-smi/lspci) на любой локали

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

# SECURE_BOOT (Secure Boot существует ТОЛЬКО в UEFI)
SB=UNKNOWN
if [ ! -d /sys/firmware/efi ]; then
  SB="off (legacy BIOS)"
else
  SBVAR=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -1 || true)
  if [ -n "$SBVAR" ]; then
    SBV=$(od -An -tu1 -j4 -N1 "$SBVAR" 2>/dev/null | tr -d ' ' || true)
    case "$SBV" in 1) SB=on ;; 0) SB=off ;; *) SB="unknown (efivar)" ;; esac
  elif command -v mokutil >/dev/null 2>&1; then
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

# Аудио-обвязка для референсов 11/20: дефолтный выход, сколько выходов,
# Auto-Mute (11 №5) и наличие RustDesk (20).
AUDIO_DEFAULT_SINK=UNKNOWN
AUDIO_SINKS=UNKNOWN
AUDIO_AUTOMUTE=NA
RUSTDESK=absent
if command -v pactl >/dev/null 2>&1; then
  AUDIO_DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null || true)
  [ -z "$AUDIO_DEFAULT_SINK" ] && AUDIO_DEFAULT_SINK=$(LC_ALL=C pactl info 2>/dev/null | awk -F': ' '/Default Sink/{print $2; exit}')
  [ -z "$AUDIO_DEFAULT_SINK" ] && AUDIO_DEFAULT_SINK=UNKNOWN
  AUDIO_SINKS=$(pactl list short sinks 2>/dev/null | wc -l | tr -d ' ')
else
  AUDIO_DEFAULT_SINK=no-pactl; AUDIO_SINKS=no-pactl
fi
if command -v amixer >/dev/null 2>&1; then
  for n in $(sed -n 's/^ *\([0-9]\+\) \[.*/\1/p' /proc/asound/cards 2>/dev/null); do
    v=$(amixer -c "$n" get 'Auto-Mute Mode' 2>/dev/null | sed -n "s/.*Item0: '\([^']*\)'.*/\1/p")
    [ -n "$v" ] && { AUDIO_AUTOMUTE="$v"; break; }
  done
fi
if command -v rustdesk >/dev/null 2>&1 || [ -x /usr/bin/rustdesk ]; then
  RUSTDESK=installed
  systemctl is-active rustdesk >/dev/null 2>&1 && RUSTDESK=active
fi
kv "AUDIO_DEFAULT_SINK" "$AUDIO_DEFAULT_SINK"; jline "AUDIO_DEFAULT_SINK" "$AUDIO_DEFAULT_SINK"
kv "AUDIO_SINKS" "$AUDIO_SINKS"; jline "AUDIO_SINKS" "$AUDIO_SINKS"
kv "AUDIO_AUTOMUTE" "$AUDIO_AUTOMUTE"; jline "AUDIO_AUTOMUTE" "$AUDIO_AUTOMUTE"
kv "RUSTDESK" "$RUSTDESK"; jline "RUSTDESK" "$RUSTDESK"

# MONITOR_INFO — только РЕАЛЬНО подключённые коннекторы (status=connected)
MONITOR_INFO=UNKNOWN
if [ -d /sys/class/drm ]; then
  CONNECTED=$(for s in /sys/class/drm/card[0-9]*-*/status; do
                [ -r "$s" ] || continue
                [ "$(cat "$s" 2>/dev/null)" = connected ] || continue
                basename "$(dirname "$s")"
              done | head -4 | tr '\n' ',' | sed 's/,$//' || true)
  [ -n "$CONNECTED" ] && MONITOR_INFO="$CONNECTED"
fi
kv "MONITOR_INFO" "$MONITOR_INFO"; jline "MONITOR_INFO" "$MONITOR_INFO"

# MONITOR_MODEL — лесенка источников (NVIDIA-проприетарный в sysfs EDID НЕ отдаёт!):
#   1) sysfs EDID (Intel/AMD/nouveau) — корректный разбор дескриптора 0xFC
#   2) ddcutil detect (DDC/CI; ставится набором 02-warm-colors)
#   3) ~/.config/monitors.xml (GNOME)
edid_vendor(){ # bytes 8-9 -> PNP-код из 3 букв (по 5 бит на букву)
  local v l1 l2 l3
  v=$(od -An -tx1 -j8 -N2 "$1" 2>/dev/null | tr -d ' \n'); [ -n "$v" ] || return 1
  v=$((16#$v)); l1=$(((v>>10)&0x1f)); l2=$(((v>>5)&0x1f)); l3=$((v&0x1f))
  { [ "$l1" -ge 1 ] && [ "$l1" -le 26 ]; } || return 1
  printf "\\$(printf '%03o' $((64+l1)))\\$(printf '%03o' $((64+l2)))\\$(printf '%03o' $((64+l3)))"
}
edid_text(){ # $1=file $2=tag (0xfc=name, 0xff=serial) -> текст до терминатора 0x0a
  local off hx t
  [ "$(od -An -tx1 -N8 "$1" 2>/dev/null | tr -d ' \n')" = "00ffffffffffff00" ] || return 1
  for off in 54 72 90 108; do
    [ "$(od -An -tx1 -j $((off+3)) -N1 "$1" 2>/dev/null | tr -d ' \n')" = "$2" ] || continue
    hx=$(od -An -tx1 -j $((off+5)) -N13 "$1" | tr -d ' \n')
    hx=${hx%%0a*}
    t=$(printf '%b' "$(printf '%s' "$hx" | sed 's/../\\x&/g')" | sed 's/ *$//')
    printf '%s' "$t"; return 0
  done
  return 1
}
detect_monitor_model(){
  local e ven model
  for e in /sys/class/drm/*/edid; do
    [ -s "$e" ] || continue
    model=$(edid_text "$e" fc); [ -n "$model" ] || continue
    ven=$(edid_vendor "$e")
    printf '%s' "${ven:+$ven }$model"; return 0
  done
  if command -v ddcutil >/dev/null 2>&1; then
    local d
    d=$(timeout 15 ddcutil detect 2>/dev/null || true)
    model=$(printf '%s\n' "$d" | awk -F': *' '/Model:/{print $2; exit}' | sed 's/ *$//')
    ven=$(printf '%s\n' "$d" | awk -F': *' '/Mfg id:/{print $2; exit}' | awk '{print $1}')
    [ -n "$model" ] && { printf '%s' "${ven:+$ven }$model"; return 0; }
  fi
  if [ -r "$HOME/.config/monitors.xml" ]; then
    ven=$(grep -m1 '<vendor>' "$HOME/.config/monitors.xml" | sed -E 's/.*<vendor>([^<]*)<.*/\1/')
    model=$(grep -m1 '<product>' "$HOME/.config/monitors.xml" | sed -E 's/.*<product>([^<]*)<.*/\1/')
    [ -n "$model" ] && { printf '%s' "${ven:+$ven }$model"; return 0; }
  fi
  printf 'UNKNOWN'
}
MM=$(detect_monitor_model)
kv "MONITOR_MODEL" "$MM"; jline "MONITOR_MODEL" "$MM"

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
  *Realtek*) C_S=OK;    C_R="AUDIO_CODEC=$AUDIO_CODEC (11 применим)" ;;
  UNKNOWN)   C_S=ADAPT; C_R="AUDIO_CODEC=UNKNOWN: 11 — только после ручной проверки /proc/asound" ;;
  *)         C_S=ADAPT; C_R="AUDIO_CODEC=$AUDIO_CODEC: 11 описан для Realtek, пути hda-verb могут отличаться" ;;
esac
[ "$AUDIO_AUTOMUTE" = Enabled ] && C_R="$C_R; Auto-Mute=Enabled → 11 БОЛЕЗНЬ №5"
[ "$AUDIO_AUTOMUTE" = Disabled ] && C_R="$C_R; Auto-Mute=off"
verdict C-железо-периферия "$C_S" "$C_R"

# D. Софт и инструменты
[ "$NET" = yes ] && verdict D-софт-инструменты OK "NETWORK_ONLINE=$NET" \
                  || verdict D-софт-инструменты SKIP "NETWORK_ONLINE=$NET: 17 требует сети (npm-установка)"

# E. Сеть и удалённый доступ
E_EXTRA="RustDesk=$RUSTDESK, AUDIO_SINKS=$AUDIO_SINKS"
if [ "$NET" != yes ]; then
  verdict E-сеть-удалёнка SKIP "NETWORK_ONLINE=$NET; $E_EXTRA"
elif [ "$SESSION_TYPE" != wayland ]; then
  verdict E-сеть-удалёнка ADAPT "SESSION_TYPE=$SESSION_TYPE: 14 (хоткеи Wayland) — X11/other → другие механизмы; $E_EXTRA"
else
  verdict E-сеть-удалёнка OK "SESSION_TYPE=$SESSION_TYPE (09 — только при наличии своего VPS; 19 — только с согласием владельца); $E_EXTRA"
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
