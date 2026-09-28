# 26 · Незнакомый AI-API (серый релей) — запуск только в контейнере

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L2 (собирает образ podman, создаёт каталог песочницы и обёртку; обратимо)
preflight-гейт: NETWORK_ONLINE=yes + rootless podman работает (`podman info` → `rootless: true`)
откат: podman rmi <образ>; rm -rf ~/.agent-sandbox/<имя>; удалить обёртку и алиас
-->

Verified live: Fedora 44, GNOME 50, Wayland; rootless `podman 5.8`. Агент — opencode (v2),
API — сторонний «релей» (`base_url` чужого сервера, не Anthropic/OpenAI напрямую).
Реальные ключи, домены и пути в примерах не приводятся — только плейсхолдеры.

## Почему это нужно

**Сторонний AI-API (релей) — это посредник между тобой и моделью.** Ты отправляешь
свой промпт и файлы не вендору, а неизвестному серверу, который гонит запрос дальше.
Что это значит на практике:

- **Он видит всё, что агент положил в запрос** — прочитанные файлы, вывод команд,
  структуру проекта, твои промпты. Агент (opencode/Claude Code) читает файлы САМ.
- **Он может подменить ответ** (MITM): вписать бэкдор в «сгенерированный» код,
  добавить команду. В авто-режиме ты этого не заметишь.
- **Модель могут подменить** на более дешёвую, а токены — завысить (проверяется
  сторонними тестерами релеев). Наблюдаемый пример: у одного Claude-подобного релея
  на КАЖДЫЙ запрос прилетало ~6543 входных токена (чужой системный промпт) —
  базовый расход завышен.
- **Домен может быть свежим, оператор анонимным** → предоплаченный баланс может
  пропасть вместе с сервисом.

Вывод: если пользуешься непроверенным API — **не с хоста**. Запускай агента в
контейнере, который видит только папку проекта, и ключи передавай через окружение.

## Что изолирует контейнер

| Слой | Хост | Контейнер |
|---|---|---|
| Файлы | весь `~` | только `/work` (папка проекта) |
| Сеть | общая | своя netns: `127.0.0.1` и LAN недоступны, интернет через VPN |
| Ключи | не хранятся в конфиге хоста | читаются из env-файла |
| Состояние агента | твои сессии/логи | отдельный `HOME` песочницы |

## Шаг 1. Образ (Fedora-база + утилиты)

```dockerfile title="Containerfile"
FROM docker.io/library/fedora:44
RUN dnf -y install --setopt=install_weak_deps=False \
      curl ca-certificates git ripgrep which \
    && dnf clean all
```

```bash
podman build -t localhost/agent-sandbox:44 .
```

**Зачем Fedora-база:** бинарь opencode монтируется с хоста read-only; если хост —
Fedora, база должна совпадать по glibc, иначе бинарь не запустится.

## Шаг 2. Песочница и конфиг opencode (V2)

Создать `~/.agent-sandbox/<имя>/home/.config/opencode/opencode.jsonc`.
Секции V2 — `providers` (ключ = префикс провайдера в `provider/model`), пакет
`@opencode/ai/providers/openai-compatible`, эндпоинт в `settings.baseURL`, а имя
переменной с ключом — в `env` (сам ключ в файл НЕ пишется).

```jsonc title="opencode.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "myrelay": {
      "name": "My Relay",
      "env": ["MYRELAY_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "https://relay.example/v1" },
      "models": {
        "model-a": { "name": "Model A" }
      }
    }
  }
}
```

## Шаг 3. Ключи — в env-файл (не в конфиг)

```bash
mkdir -p ~/.agent-sandbox/myrelay/home
umask 077
printf 'MYRELAY_KEY=sk-xxx\n' > ~/.agent-sandbox/myrelay/keys.env
chmod 600 ~/.agent-sandbox/myrelay/keys.env
```

Контейнеру файл передаётся как `--env-file` — ключ попадает в окружение процесса,
а не в конфиг на диске контейнера.

## Шаг 4. Запуск

Готовый скрипт: `scripts/isolated-agent.sh`.

```bash
AGENT_SANDBOX=~/.agent-sandbox/myrelay scripts/isolated-agent.sh ~/Projects/foo
AGENT_SANDBOX=~/.agent-sandbox/myrelay scripts/isolated-agent.sh ~/Projects/foo run "привет" --model myrelay/model-a
AGENT_SANDBOX=~/.agent-sandbox/myrelay scripts/isolated-agent.sh ~/Projects/foo -- bash -c 'ls -la'
```

Скрипт: берёт папку проекта (аргумент или текущую), отказывается монтировать
домашнюю папку/её родителя, монтирует бинарь opencode ro, песочницу как `HOME`,
`--userns=keep-id` (файлы в `/work` сохраняют владельца), `--env-file` с ключами.

## Verify (только факты)

```bash
# 1) домашняя и секреты не видны
scripts/isolated-agent.sh ~/Projects/foo -- bash -c 'ls ~ ; cat /home/<user>/AGENTS.md'
# → ~ пустой, AGENTS.md: No such file

# 2) сеть изолирована
scripts/isolated-agent.sh ~/Projects/foo -- bash -c \
  'curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://127.0.0.1:8080'
# → 000 (недоступно). Интернет при этом работает и идёт через VPN:
scripts/isolated-agent.sh ~/Projects/foo -- bash -c 'curl -s https://am.i.mullvad.net/json'

# 3) обе группы отвечают
scripts/isolated-agent.sh ~/Projects/foo run "reply PONG" --model myrelay/model-a
```

## Грабли (проверено)

- **`source keys.env` без `set -a` не экспортирует переменные** → `podman -e VAR`
  их не пробросит. Либо `set -a; . keys.env; set +a`, либо `--env-file` (проще).
- **Пакет `anthropic-compatible` может не завестись** («Cannot find package
  '@opencode/ai'»). Если релей отдаёт Claude и в OpenAI-формате
  (`/v1/chat/completions`), используй `openai-compatible` для обеих групп — проверено.
- **Монтирование бинаря с хоста требует совпадения glibc** → база образа той же
  семьи, что и хост (Fedora↔Fedora).
- **`--userns=keep-id`** обязателен, иначе файлы в `/work` станут root-овыми.
- **`--new-session` в bwrap рвёт tty** — для интерактивного TUI проверяй; у podman
  TUI обычно ок, но тестируй в реальном терминале.
- **Проверь группы ключей:** GPT-ключ не имеет доступа к Claude-моделям
  (`Model not supported by any configured account in this group`).
- **Домен свежий / оператор анонимный** — изоляция не делает сервис честным:
  модель всё ещё могут подменить, токены завысить.

## Откат

```bash
podman rmi localhost/agent-sandbox:44
rm -rf ~/.agent-sandbox/<имя>
rm ~/.local/bin/<обёртка>        # и удалить алиас из ~/.bashrc, если добавлял
```

## References

- V2-конфиг провайдеров: https://opencode.ai/v2/docs/providers/
- Модели/лимиты: https://opencode.ai/v2/docs/models/
- Проверка релеев сторонними тестерами (подмена модели / биллинг): сообщества
  вида veridrop / llmtest (см. также соседний `24-mullvad-vpn-hardening.md` про VPN-слой)
- Соседние референсы: `17-opencode2.md` (установка), `25-webrtc-ip-leak-firefox.md`
