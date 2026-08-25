# Fedora → Windows Look & Performance

Проверенные инструкции: ускорить Fedora (GNOME), сделать тёплые цвета дисплея
и полный вид «как на Windows» (тёмная тема, шрифты, курсоры, звуки, панель),
терминалы как Windows Terminal, zram-своп, форматирование дисков.

Совместимость: Fedora Workstation, GNOME + Wayland (проверено GNOME 45–50,
Fedora 44); раздел zram — любой systemd-Linux (Fedora/Arch/CachyOS/Ubuntu).

## Что внутри

| Раздел | Файл | О чём |
|---|---|---|
| Обзор + маршрут | `SKILL.md` | когда какой раздел, главное правило, быстрый старт |
| Ускорение | `references/01-speedup.md` | аудит → службы → загрузка → GNOME → ядро CachyOS + правила питания владельца (профиль performance, экран/сон/затемнение — OFF) |
| Тёплые цвета | `references/02-warm-colors.md` | Night Light, VCGT-гамма, DDC монитора + макс Гц автоматом (monitors.xml, проверено 144 Гц) |
| Windows-лук | `references/03-windows-look.md` | тёмная тема, Segoe UI, курсоры, звуки, расширения + установка Telegram (репозиторий Fedora) |
| Терминалы | `references/04-terminals.md` | Alacritty, WezTerm, Konsole + Cascadia Mono |
| zram | `references/05-zram.md` | сжатый своп: RAM/2, zstd, swappiness 150 |
| Диски | `references/06-disks.md` | форматирование, монтирование, fstab, NTFS-fix |
| RustDesk + игры | `references/07-rustdesk-games.md` | удалёнка, гейминг-тюнинг |
| Своп-файл | `references/08-swapfile-backup.md` | дисковый своп за zram, защита от OOM + правило размера по ОЗУ (8G→32G, 16G→16G) |
| VPN + торренты | `references/09-vpn-torrents.md` | свой WireGuard с нуля, клиент Fedora, MTU/BBR, проброс портов, сидбокс |
| Аудио: задний разъём | `references/11-rear-audio-jack.md` | «мёртвый» задний зелёный: пин кодека выключен, hda-verb + автозапуск |
| AC Odyssey + Wine | `references/12-ac-odyssey-wine.md` | игра виснет на загрузке: loader_section deadlock → WINEDEBUG=+loaddll, DXVK рядом с exe, без dxvk.conf |
| OBS хоткеи (Wayland) | `references/13-obs-wayland-hotkeys.md` | нативные хоткеи OBS не работают в фоне → плагин Wayland Hotkeys + клавиши в dconf системы |
| Глобальные клавиши | `references/14-global-hotkeys-wayland.md` | назначить клавиши на любой софт: портал / WebSocket-мост / evdev |
| Видеоплееры | `references/15-video-players-vlc-celluloid.md` | VLC (универсал) + Celluloid (блогер): установка + фикс flatpak-песочницы «не видит файлы» |
| Раскладки | `references/16-keyboard-layouts.md` | русский + английский: установка RU/EN, переключение как в Windows (Alt+Shift), консоль + экран входа |
| OpenCode 2 | `references/17-opencode2.md` | AI-кодинг-агент (beta): установка `opencode2` без sudo, первый запуск, план/билд, грабли беты |
| Camoufox MCP | `references/18-camoufox-mcp.md` | браузер-ресёрч для агента: установка в opencode2, фикс «Unknown tool» (новая сессия), codemode=false |
| Sudo без пароля | `references/19-sudo-nopasswd.md` | passwordless sudo: ПРАВИЛО «только с согласия владельца», настройка через sudoers.d, проверка visudo, откат, узкая альтернатива |
| Скрипты | `scripts/` | `audit.sh` (read-only аудит), `apply-zram.sh` (идемпотентный, `--dry-run`), `apply-windows-look.sh` (перенос вида «как на ПК» на другую Fedora: gsettings + ассеты + расширения) |

## Быстрый старт

```bash
bash scripts/audit.sh                 # аудит, ничего не меняет
bash scripts/apply-zram.sh --dry-run  # zram: посмотреть план
bash scripts/apply-zram.sh            # zram: применить (sudo)
bash scripts/apply-windows-look.sh --dry-run   # лук «как на ПК»: посмотреть план
bash scripts/apply-windows-look.sh --assets windows-look-assets.tar.gz  # применить (расширения — sudo)
bash scripts/apply-windows-look.sh --vpn ~/vpn/сервер.conf  # сходу поднять WireGuard (путь свой, см. 09-vpn-torrents.md)
```

Дальше — по `SKILL.md`: цвета → лук → терминалы, каждая секция с откатами.

## Замечания

- Каждая правка обратима; деструктивные шаги — только с подтверждением владельца.
- Шрифты Microsoft — проприетарные, устанавливаются локально по выбору владельца.
- Проверено на реальных системах (Fedora 44, GNOME 50.3, NVIDIA); свежесть
  ссылок и версий пакетов — проверять перед применением.
