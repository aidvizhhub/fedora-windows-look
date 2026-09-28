#!/usr/bin/env bash
# isolated-agent.sh — запуск opencode внутри контейнера podman.
#
# Что даёт: агент видит ТОЛЬКО указанную папку проекта; домашняя папка,
# память, .env и ключи хоста — не видны; у контейнера своя сеть (не видно
# 127.0.0.1 и LAN хоста); ключи приходят файлом-env, а не лежат в конфиге.
#
# Нужен образ (см. references/26-*.md), напр. fedora-база + curl/git/ripgrep.
#
# Использование:
#   isolated-agent.sh                          # текущая папка
#   isolated-agent.sh ~/Projects/moy-proekt    # явно
#   isolated-agent.sh ~/Projects/moy-proekt run "privet" --model myrelay/model
#   isolated-agent.sh ~/Projects/moy-proekt -- bash -c 'ls -la'
#
# Настройки (переменные окружения):
#   AGENT_SANDBOX   каталог песочницы (конфиг + keys.env), по умолчанию ~/.agent-sandbox/agent
#   AGENT_IMAGE     образ podman, по умолчанию localhost/agent-sandbox:44
#   AGENT_BIN       бинарь opencode на хосте, монтируется в образ read-only
#                   (нужен, если образ не содержит opencode), по умолчанию ~/.opencode/bin/opencode
set -euo pipefail

SANDBOX="${AGENT_SANDBOX:-$HOME/.agent-sandbox/agent}"
IMAGE="${AGENT_IMAGE:-localhost/agent-sandbox:44}"
BIN="${AGENT_BIN:-$HOME/.opencode/bin/opencode}"
ENVFILE="$SANDBOX/keys.env"

# папка проекта: первый аргумент, если это существующий каталог, иначе текущая
if [ $# -gt 0 ] && [ -d "$1" ]; then PROJ="$1"; shift; else PROJ="$PWD"; fi
PROJ="$(readlink -f "$PROJ")"
[ -d "$PROJ" ] || { echo "нет такой папки: $PROJ" >&2; exit 2; }

# защита: не дать случайно примонтировать домашнюю папку или её родителя
if [ "$PROJ" = "$HOME" ] || [ "$PROJ" = "/" ] || [[ "$HOME" == "$PROJ"/* ]]; then
    echo "ОТКАЗ: '$PROJ' — домашняя папка или её родитель." >&2
    echo "Запускай из папки проекта: cd ~/Projects/имя && isolated-agent.sh" >&2
    exit 3
fi

[ -f "$ENVFILE" ] || { echo "нет файла ключей: $ENVFILE" >&2; exit 2; }

mkdir -p "$SANDBOX/home/.config/opencode" "$SANDBOX/home/.local/share"

CMD=(opencode); [ $# -gt 0 ] && CMD=(opencode "$@")
if [ "${1:-}" = "--" ]; then shift; CMD=("$@"); fi
TTY=(-i); [ -t 0 ] && TTY=(-it)

MOUNT_BIN=()
[ -x "$BIN" ] && MOUNT_BIN=(-v "$BIN:/usr/local/bin/opencode:ro")

exec podman run --rm "${TTY[@]}" \
    --userns=keep-id \
    --env-file "$ENVFILE" \
    -e HOME=/home/agent \
    "${MOUNT_BIN[@]}" \
    -v "$SANDBOX/home:/home/agent" \
    -v "$PROJ:/work" \
    -w /work \
    "$IMAGE" "${CMD[@]}"
