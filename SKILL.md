---
name: fedora-windows-look
description: "Комплект для безопасного переезда на новый ПК + настройка Fedora/GNOME под Windows-лук и скорость. Использовать, когда нужно: ускорить Fedora/GNOME (медленная загрузка, какие службы отключить, кастомное ядро), тёплые цвета дисплея как на Windows, вид «как на винде» (тёмная тема, Segoe UI, курсоры, звуки, панель), терминалы как Windows Terminal, zram/своп/подкачка, форматирование и монтирование дисков, RustDesk для игр (чёрный экран, FPS), WireGuard VPN + торренты, OBS Studio запись, мёртвый задний аудиоразъём (hda-verb), AC Odyssey под Wine, хоткеи на Wayland (OBS/глобальные), видеоплееры VLC/Celluloid, RU/EN раскладки, opencode2, sudo без пароля. Всегда сначала preflight (scripts/preflight.sh), референсы — только примеры."
---

# Fedora → Windows Look & Performance — комплект «переезд на новый ПК»

Пакет проверенных живьём инструкций (Fedora 44, GNOME 50, NVIDIA):
ускорение, тёплые цвета, Windows-лук, терминалы, zram/своп, диски,
RustDesk/VPN/OBS/игры, хоткеи Wayland, раскладки, AI-инструменты.
Каждый шаг обратим и снабжён откатом.

## Законы (читай перед любым действием)

1. **Сначала preflight, потом действия.** `bash scripts/preflight.sh` — read-only карта
   железа/ОС. Нет свежего отчёта (< 1 дня) → запусти. Ничего не меняй до этого.
2. **Референсы — ТОЛЬКО примеры.** Команды проверены на реальных системах (Fedora 44,
   GNOME 50, NVIDIA/AMD). На новом ПК сверь preflight-гейт шага (шапка `<!-- meta -->`
   в референсе) и пересчитай числа из фактов: zram = `RAM_MB/2`, пин кодека — из своего
   `/proc/asound`, монитор — из своего EDID. Гейт → OK / ADAPT / SKIP (таблица в
   `references/00-preflight.md`).
3. **От лёгкого к тяжёлому.** Внутри категории и между категориями порядок любой
   (разнобой допускается), но L3 не трогать, пока на этой машине не стабилизированы
   L1–L2 (проверка: прогресс-файл). Постепенность — закон, «всё сразу» — запрещено.
4. **L3 = стоп-гейт.** dry-run → показать команды → backup-план → ЯВНОЕ «да» владельца →
   apply → verify → откат записать. Никогда не применяй L3 без явного подтверждения.
5. **Verify фактами, не глазами.** Команды проверки из референса. Не прошло → СТОП:
   диагностика + откат, не «чинить дальше».
6. **Шаг сделан = записан** в локальный журнал переноса (владелец хранит его вне git —
   в репозитории его нет; в коммиты он не попадает).
7. **Согласие владельца.** Sudo-команды — только с согласия. Деструктивные (диски,
   sudoers, VPN-сервер) — только после явного подтверждения и backup.

## Быстрый старт (новый ПК)

```bash
git clone https://github.com/<ваш-ник>/fedora-windows-look.git ~/fedora-windows-look
cd ~/fedora-windows-look
bash scripts/preflight.sh          # 1. карта железа/ОС + вердикты по категориям
# 2. выбери категорию (таблица ниже) — протокол шага из любого референса:
#    0 preflight-гейт → 1 план (dry-run) → 2 подтверждение → 3 apply → 4 verify → 5 откат+прогресс
bash scripts/audit.sh              # спец-аудит ускорения (read-only, категория B)
bash scripts/apply-zram.sh --dry-run   # zram: посмотреть план (cat. B)
bash scripts/apply-windows-look.sh --dry-run  # лук «как на винде» (cat. A)
```

## Категории (дробление: бери любой кусок, не всё сразу)

| # | Категория | Риск | Референсы | Главные гейты (из preflight) |
|---|---|---|---|---|
| A | Внешний вид | L1→L2 | 02, 03, 04 (+01 шаг 3) | DE=GNOME, SHELL_VER=45+, GPU/монитор для DDC |
| B | Производительность | L1→L3 | 01, 05, 08 | VIRT=none; ядро: CPU_X86_64_V3=yes, SECURE_BOOT=off; RAM_MB |
| C | Железо и периферия | L2→L3 | 06, 11, 15 | AUDIO_CODEC=realtek (11); диски — только с подтверждением |
| D | Софт и инструменты | L1→L2 | 16, 17 | NETWORK_ONLINE=yes (17); DE=GNOME (16 GDM) |
| E | Сеть и удалённый доступ | L2→L3 | 09, 14, 19 | NETWORK_ONLINE + свой VPS (09); SESSION_TYPE=wayland (14) |
| F | Игры и контент | L1→L3 | 07, 10, 12, 13 | GPU_VENDOR=nvidia (07, 10 NVENC); SESSION_TYPE=wayland (13) |
| G | Аудит и статус | L0 (только чтение) | 00-preflight, audit.sh | — |

Полная таблица гейтов (OK/ADAPT/SKIP по каждому ключу): `references/00-preflight.md`.
Числа в примерах референсов — НЕ переносить слепо (zram, swapfile, пин кодека, FPS, монитор).

## Протокол шага (применяется к ЛЮБОМУ референсу)

```
0. Preflight-гейт:  bash scripts/preflight.sh → сверь ключи с шапкой <!-- meta --> референса.
                    Гейт ADAPT/SKIP → покажи владельцу, ЧТО меняешь и ПОЧЕМУ; без решения не идти.
1. План:           точные команды; числа ИЗ ФАКТОВ; где есть --dry-run — вызвать; показать владельцу.
2. Подтверждение:  L1 → «поехали» достаточно; L2 → показать sudo-команды и откат;
                    L3 → явное «да» + backup-план (timestamped) до apply.
3. Apply:          по одной команде, с логом; L3 — после backup.
4. Verify:         команды проверки из референса → ФАКТЫ. Провал → СТОП: диагностика + откат.
5. Откат+прогресс: записать в локальный журнал переноса владельца: дата, хост, шаг,
   риск, verify, откат-команда (журнал вне git — в репозитории его нет).
```

## Когда использовать (запрос → категория → референс)

| Запрос пользователя | Куда |
|---|---|
| «тормозит», «медленная загрузка», «какие службы отключить», «стоит ли кастомное ядро» | B · `references/01-speedup.md` |
| «холодные цвета», «блекло», «настроить гамму», «тёплый как на винде» | A · `references/02-warm-colors.md` |
| «сделай как на винде»: тёмная тема, Segoe UI, курсоры, звуки, панель | A · `references/03-windows-look.md` |
| «терминал как Windows Terminal», konsole тёмная, Cascadia Mono | A · `references/04-terminals.md` |
| «настрой zram/своп», «сжатый своп» | B · `references/05-zram.md` + `scripts/apply-zram.sh` |
| «отформатируй диск», «не пишет на диск», разметка, fstab | C · `references/06-disks.md` (L3!) |
| «напарник не видит игру», «чёрный экран в RustDesk», «мало FPS» | F · `references/07-rustdesk-games.md` |
| «линукс умирает от нехватки ОЗУ», «файл подкачки», «чтобы не падал» | B · `references/08-swapfile-backup.md` |
| «настрой VPN», «wireguard», «торренты медленно», «сидбокс» | E · `references/09-vpn-torrents.md` |
| «поставь OBS», «настрой запись видео», «файлы записи жирные» | F · `references/10-obs-studio.md` |
| «задний зелёный молчит», «наушники в Line Out не играют» | C · `references/11-rear-audio-jack.md` |
| «игра не запускается на вине», «виснет на загрузке», «loader_section deadlock» | F · `references/12-ac-odyssey-wine.md` |
| «хоткеи OBS не работают в игре», «запись не стартует из игры» | F · `references/13-obs-wayland-hotkeys.md` |
| «назначить глобальные клавиши на софт», «хоткеи в фоне не работают» | E · `references/14-global-hotkeys-wayland.md` |
| «какой видеоплеер поставить», «Celluloid не видит файлы» | C · `references/15-video-players-vlc-celluloid.md` |
| «добавь русскую раскладку», «переключение как в Windows», «Alt+Shift» | D · `references/16-keyboard-layouts.md` |
| «поставь opencode», «opencode2 не работает», «AI-агент для кода» | D · `references/17-opencode2.md` |
| «sudo без пароля», «sudo спрашивает пароль в скрипте» | E · `references/19-sudo-nopasswd.md` (L3, только с согласия!) |

**Когда НЕ использовать:** серверы (там свои правила — не трогать
NetworkManager-wait-online); настройка Firefox (отдельный скилл).

## Структура

```
fedora-windows-look/
├── SKILL.md                    # этот файл: законы, категории, протокол
├── references/
│   ├── 00-preflight.md         # как читать preflight-отчёт + таблица гейтов (НЕ ПРОПУСКАТЬ)
│   └── 01..17,19-*.md          # проверенные инструкции; шапка <!-- meta --> = категория/риск/гейт/откат
├── scripts/
│   ├── preflight.sh            # read-only карта железа/ОС + вердикты (шаг 0 ЛЮБОГО сценария)
│   ├── audit.sh                # спец-аудит ускорения (read-only)
│   ├── apply-zram.sh           # идемпотентный, --dry-run
│   └── apply-windows-look.sh   # перенос лука на другую Fedora: gsettings+ассеты+расширения, --dry-run
└── README.md                   # обзор и быстрый старт
```

## Безопасность

- `preflight.sh`, `audit.sh` — только чтение; `apply-*.sh` — идемпотентные, `--dry-run`.
- Каждая команда с sudo — с согласия владельца; L3 (диски, sudoers, ядро, VPN-сервер) —
  явное «да» + backup до применения.
- Шрифты Microsoft (Segoe UI, Cascadia) — проприетарные: установка локальная, по выбору
  владельца (альтернатива — взять из существующего Windows-раздела).
- Личные артефакты владельца (журнал переноса, спеки, пути) в репозитории не публикуются
  и в коммиты не попадают — репозиторий остаётся универсальным «адаптивом для всех».

## References (первоисточники)

- SKILL-канон: platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- Скрипты-эталоны: github.com/Abdelrahman-El-Maghraby/linux-maintain · github.com/hamzaatservice/server-security-scan
- Идемпотентность: commandinline.com/shell-script-idempotency-safe-rerun-patterns
- Дотфайлы: chezmoi.io · dotfiles-репо 0xkuze/dotfiles · rdavidjr/ansible-setup
- Остальное (ускорение/цвета/терминалы/zram…) — в «References» каждого референса 01–19.
