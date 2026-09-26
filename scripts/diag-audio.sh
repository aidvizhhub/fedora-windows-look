#!/usr/bin/env bash
# diag-audio.sh — read-only диагностика звука на Linux-десктопе.
# CHANGES NOTHING. Без sudo (root-конфиг RustDesk читается только если и так доступен).
# Закрывает грабли: references/11 (мёртвый разъём / Auto-Mute) и references/20 (RustDesk-звук).
# Usage: bash scripts/diag-audio.sh [--help]
set -uo pipefail
export LC_ALL=C   # стабильный разбор подписей pactl (Source:, Server Name и т.п.)

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
  cat <<'EOF'
usage: bash scripts/diag-audio.sh [--help]

Read-only прибор по звуку:
  • кодек + состояние Auto-Mute (ref 11: перед+зад не играют одновременно)
  • выходы (sinks) / дефолтный / мониторы-источники
  • RustDesk: стоит/активен, какой audio-input прописан, куда он РЕАЛЬНО залип
    (последняя строка 'pa monitor:' из лога + активные захваты)

Ничего не меняет, sudo не требует.
EOF
  exit 0
}

sec(){ printf '\n===== %s =====\n' "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }
RD_LOGDIR="$HOME/.local/share/logs/RustDesk"

sec "СИСТЕМА"
printf 'session: %s\n' "${XDG_SESSION_TYPE:-UNKNOWN}"
printf 'audio server: %s\n' "$(have pactl && pactl info 2>/dev/null | awk -F': ' '/Server Name/{print $2; exit}' || echo unknown)"

# ---------- 1. Кодек + Auto-Mute (ref 11) --------------------------------
sec "КОДЕК / AUTO-MUTE (ref 11)"
if [ -r /proc/asound/cards ]; then
  CODEC=$(for f in /proc/asound/card*/codec#*; do
            [ -r "$f" ] || continue
            grep -m1 'Codec:' "$f" 2>/dev/null | sed 's/Codec:[[:space:]]*//'; break
          done)
  printf 'codec: %s\n' "${CODEC:-UNKNOWN}"
fi
if have amixer; then
  FOUND=0
  for n in $(sed -n 's/^ *\([0-9]\+\) \[.*/\1/p' /proc/asound/cards 2>/dev/null); do
    v=$(amixer -c "$n" get 'Auto-Mute Mode' 2>/dev/null | sed -n "s/.*Item0: '\([^']*\)'.*/\1/p")
    [ -n "$v" ] || continue
    FOUND=1
    printf 'card%s Auto-Mute Mode = %s\n' "$n" "$v"
  done
  [ "$FOUND" = 0 ] && echo "Auto-Mute Mode: контрол не найден (не Realtek HDA или другой драйвер)"
else
  echo "amixer недоступен (нет ALSA-утилит)"
fi

# ---------- 2. Выходы / источники ----------------------------------------
sec "ВЫХОДЫ (sinks) и МОНИТОРЫ-ИСТОЧНИКИ"
if have pactl; then
  printf 'default sink: %s\n' "$(pactl get-default-sink 2>/dev/null || echo UNKNOWN)"
  echo "--- sinks ---"
  pactl list short sinks 2>/dev/null | awk '{printf "  #%s  %s  [%s]\n",$1,$2,$5}'
  echo "--- sources (мониторы = loopback-вход, их слушает RustDesk) ---"
  pactl list short sources 2>/dev/null | awk '{printf "  #%s  %s  [%s]\n",$1,$2,$5}'
  N_SINK=$(pactl list short sinks 2>/dev/null | wc -l | tr -d ' ')
  N_MON=$(pactl list short sources 2>/dev/null | grep -c '\.monitor' || true)
  printf 'итог: выходов=%s, мониторов=%s\n' "$N_SINK" "$N_MON"
else
  echo "pactl недоступен"
fi

# ---------- 3. RustDesk (ref 20) -----------------------------------------
sec "RUSTDESK (ref 20)"
AI_USER=""
if have rustdesk || [ -x /usr/bin/rustdesk ]; then
  st=$(systemctl is-active rustdesk 2>/dev/null || echo unknown)
  printf 'установлен: да; служба: %s\n' "$st"
  for f in "$HOME/.config/rustdesk/RustDesk2.toml" /root/.config/rustdesk/RustDesk2.toml; do
    ai=""
    if [ -r "$f" ]; then
      ai=$(grep -E "^audio-input" "$f" 2>/dev/null | sed "s/^audio-input *= *//")
    elif sudo -n test -r "$f" 2>/dev/null; then
      ai=$(sudo -n grep -E "^audio-input" "$f" 2>/dev/null | sed "s/^audio-input *= *//")
    else
      printf 'audio-input [%s] = (нет доступа — читать через sudo)\n' "$f"; continue
    fi
    [ "$f" = "$HOME/.config/rustdesk/RustDesk2.toml" ] && AI_USER="$ai"
    printf 'audio-input [%s] = %s\n' "$f" "${ai:-<пусто → баг первого монитора>}"
  done
  log="$RD_LOGDIR/cm/rustdesk_rCURRENT.log"
  if [ -r "$log" ]; then
    last=$(grep -h 'pa monitor' "$log" 2>/dev/null | tail -1 | sed 's/.*pa monitor: //')
    printf 'последний выбор источника: %s\n' "${last:-<нет записей>}"
  else
    echo "лог RustDesk не найден ($log)"
  fi
  if have pactl; then
    echo "--- активные захваты СЕЙЧАС (идёт ли сессия) ---"
    pactl list source-outputs 2>/dev/null | awk '
      /^Source output #/ {id=$0}
      /Source:/ {s=$2}
      /application.name =/ {gsub(/"/,"");print "  "$0" (source #"s")"}' | head
  fi
else
  echo "RustDesk не установлен"
fi

# ---------- 4. Вердикт-подсказки -----------------------------------------
sec "ПОДСКАЗКИ"
AM=$(for n in $(sed -n 's/^ *\([0-9]\+\) \[.*/\1/p' /proc/asound/cards 2>/dev/null); do
       amixer -c "$n" get 'Auto-Mute Mode' 2>/dev/null | sed -n "s/.*Item0: '\([^']*\)'.*/\1/p"
     done | head -1)
[ "$AM" = Enabled ] && echo "• Auto-Mute=Enabled → перед+зад не играют одновременно: ref 11, БОЛЕЗНЬ №5"
[ "$AM" = Disabled ] && echo "• Auto-Mute=Disabled → ок (оба разъёма играют разом)"
if have pactl; then
  dc=$(pactl get-default-sink 2>/dev/null)
  mon=$(pactl list short sources 2>/dev/null | grep '\.monitor')
  pm=$(echo "$mon" | awk '{print $2}' | head -1)
  if [ -n "$dc" ] && [ -n "$pm" ] && [ "${dc}.monitor" != "$pm" ]; then
    if [ -n "${AI_USER:-}" ]; then
      echo "• мониторов >1, но audio-input в RustDesk задан явно → ок (баг первого монитора обойдён)"
    else
      echo "• мониторов >1, а audio-input в RustDesk ПУСТ → риск ref 20:"
      echo "  залипнет на первом мониторе '$pm' (возможно, тишина); дефолт = '$dc'."
      echo "  Лечение: audio-input = 'Monitor of <нужный выход>' (см. ref 20)."
    fi
  fi
fi
echo
echo "Больше контекста: references/11-rear-audio-jack.md, references/20-rustdesk-audio.md"
