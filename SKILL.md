---
name: fedora-windows-look
description: "Make Fedora look and feel like Windows and run faster. Use when the user asks to speed up Fedora/GNOME (slow boot, which services to disable, custom kernel), set warm display colors like Windows (cold/washed-out screen, gamma, night light), apply a Windows 11 look (dark theme, Segoe UI, cursors, sounds, taskbar), set up terminals like Windows Terminal (Alacritty/WezTerm/Konsole, Cascadia Mono), tune zram swap, format/mount disks, fix RustDesk for games (black screen on Wayland/NVIDIA, boost FPS to 120), set up WireGuard VPN + torrents/seedbox, install/configure OBS Studio for local recording (Flatpak, NVENC HEVC, CQP, 120/144 fps, MKV), fix a dead rear audio jack (Realtek HDA pin disabled, hda-verb), or fix a Windows game that hangs on the loading screen under Wine (loader_section deadlock, WINEDEBUG=+loaddll, DXVK next to exe), or make global hotkeys work on Wayland (OBS recording/streaming from any window, GNOME Global Shortcuts portal, dconf bindings, WebSocket bridge), or pick/install a video player (VLC universal + Celluloid for creators, Flatpak sandbox fix for 'can't open local files'). Covers: audit -> speedup -> warm colors -> windows-look -> terminals -> zram -> disks -> rustdesk -> vpn -> obs -> audio-jack -> ac-odyssey-wine -> obs-wayland-hotkeys -> global-hotkeys-wayland -> video-players."
---

# Fedora → Windows Look & Performance

Пакет инструкций, проверенных живьём на Fedora (GNOME + Wayland): ускорение
системы, тёплые цвета дисплея как на Windows, полный Windows-лук (тёмная тема,
шрифты, курсоры, звуки, панель), терминалы как Windows Terminal, zram-своп,
форматирование дисков, RustDesk для игр (чёрный экран + FPS). Каждый шаг
обратим, каждая правка — с командой отката.

## Когда использовать

| Запрос пользователя | Раздел |
|---|---|
| «тормозит», «медленная загрузка», «какие службы отключить», «стоит ли кастомное ядро» | `references/01-speedup.md` |
| «холодные цвета», «блекло», «настрой гамму», «сделай тёплый как на винде» | `references/02-warm-colors.md` |
| «сделай как на винде»: тёмная тема, шрифты Segoe UI, курсоры, звуки, панель, пуск | `references/03-windows-look.md` |
| «поставь терминал как Windows Terminal», konsole тёмная тема, Cascadia Mono | `references/04-terminals.md` |
| «настрой zram/своп», «сжатый своп» | `references/05-zram.md` |
| «отформатируй диск», «не пишет на диск», разметка, fstab | `references/06-disks.md` |
| «напарник не видит игру по удалёнке», «чёрный экран в RustDesk», «мало FPS при демонстрации экрана» | `references/07-rustdesk-games.md` |
| «линукс умирает от нехватки ОЗУ», «файл подкачки», «сделай больше свопа», «чтобы не падал» | `references/08-swapfile-backup.md` |
| «настрой VPN», «wireguard», «торренты медленно», «сидбокс» | `references/09-vpn-torrents.md` |
| «поставь OBS», «настрой запись видео», «запись тормозит», «файлы записи жирные» | `references/10-obs-studio.md` |
| «задний зелёный молчит», «наушники в Line Out не играют», «звук только из переднего разъёма» | `references/11-rear-audio-jack.md` |
| «игра не запускается на вине», «виснет на загрузке», «loader_section deadlock», «AC Odyssey не стартует» | `references/12-ac-odyssey-wine.md` |
| «хоткеи OBS не работают в игре», «глобальные клавиши на Wayland», «запись не стартует из игры» | `references/13-obs-wayland-hotkeys.md` |
| «назначить глобальные клавиши на софт», «хоткеи в фоне не работают», «Wayland перехват клавиш» | `references/14-global-hotkeys-wayland.md` |
| «какой видеоплеер поставить», «видео не открывается во flatpak-плеере», «Celluloid не видит файлы» | `references/15-video-players-vlc-celluloid.md` |
| «добавь русскую раскладку», «переключение языка как в Windows», «Alt+Shift не работает», «раскладка не на экране входа» | `references/16-keyboard-layouts.md` |
| «поставь opencode», «opencode2 не работает», «AI-агент для кода», «как подключить API» | `references/17-opencode2.md` |
| «camoufox Unknown tool», «MCP отвалился», «браузер для агента», «ресёрч через кауфми», «camoufox Connection closed» | `references/18-camoufox-mcp.md` |
| «sudo без пароля», «sudo спрашивает пароль в скрипте», «NOPASSWD», «вернуть пароль sudo» | `references/19-sudo-nopasswd.md` (только с согласия владельца!) |

**Когда НЕ использовать:** серверы (там свои правила — не трогать
NetworkManager-wait-online); настройка Firefox (отдельный скилл);
ускорение через zram/диски — по ссылкам выше.

## Главное правило

**Сначала аудит (read-only), потом правки, потом перезагрузка — владельцем.**
Ничего не менять до того, как собраны факты. Каждую правку показывать
владельцу с ценой и командой отката. Необратимые операции (форматирование
дисков) — только после явного подтверждения.

## Быстрый старт

```bash
# 1. Аудит системы (ничего не меняет)
bash scripts/audit.sh

# 2. Ускорение — references/01-speedup.md (шаги 1-3, ядро — опционально)

# 3. Тёплые цвета — references/02-warm-colors.md
#    главный фикс «холодного» экрана: пресет монитора 7500K → 6500K (DDC)

# 4. Windows-лук — references/03-windows-look.md

# 5. Терминалы — references/04-terminals.md

# 6. zram — scripts/apply-zram.sh [--dry-run]   (см. references/05-zram.md)
bash scripts/apply-zram.sh --dry-run   # посмотреть, что будет
bash scripts/apply-zram.sh             # применить (sudo, размер = RAM/2)
```

## Важность каждого раздела (коротко)

1. **Ускорение** — загрузка 45с → ~13с и −300–500МБ RAM бесплатно: boot-время
   это ожидания (мёртвые UUID, wait-online, plymouth), а RAM едят краш-репортеры
   и модем-мониторы. Кастомное ядро — последний шаг, эффект единицы-десятки %.
2. **Тёплые цвета** — мониторы по умолчанию 7500K (холодно/дёшево); 6500K пресет
   + VCGT-гамма + gamma 0.95 = «как на винде». Это первое впечатление от системы.
3. **Windows-лук** — тёмная тема + Segoe UI + курсоры + звуки + панель Dash to
   Panel + ArcMenu = привычный вид, мелкие настройки, огромная субъективная разница.
4. **Терминалы** — Windows Terminal Dark на Alacritty/WezTerm/Konsole + Cascadia
   Mono; тёмно-серый #0C0C0C вместо чистого чёрного (халация, астигматизм).
5. **zram** — сжатый своп в RAM в 10+ раз быстрее диска: swappiness 150 +
   page-cluster 0 + zstd = свободная RAM под кэш.
6. **Диски** — большинство «не пишет» лечится без переформатирования
   (ntfsfix dirty flag); fstab с nofail не вешает загрузку при отсутствии диска.
7. **RustDesk для игр** — на Wayland+NVIDIA полноэкранная игра уходит в
   direct scanout мимо композитора (чёрный экран у напарника); лечится
   `MUTTER_DEBUG_PAINT=disable-direct-scanout` + виртуальный стол Wine.
   Лимит FPS по умолчанию 30 — поднимается до 120 аппаратным H.264 (NVENC).
8. **Файл подкачки (страховка от OOM)** — zram без дна: когда RAM+zram
   кончаются, Linux умирает (OOM-kill/фриз). Файл 16G на диске с приоритетом
   ниже zram = система тормозит, но не падает; на LUKS-root подкачка
   автоматически зашифрована.
9. **VPN + торренты** — свой WireGuard-VPS = без логов и подписки; MTU-чёрная
   дыра — главный тихий убийца скорости; сидбокс на сервере = скорость без
   покупки дорогого канала у провайдера.
10. **OBS Studio** — запись ≠ стрим: для записи CQP вместо CBR (файлы в 2 раза
    легче, качество выше); NVENC — отдельный чип, CPU не грузит; настройки
    энкодера — в `recordEncoder.json`, а не в `basic.ini`; 120/144 FPS —
    только Integer/Fraction режимы.
11. **Задний звуковой разъём** — «мёртвый» задний зелёный при живом переднем
    это НЕ поломка железа: пин кодека выключен (`Pin-ctls: 0x00`), лечится
    `hda-verb` + юнит автозапуска; путаница портов «Наушники» (перед) vs
    «Линейный выход» (зад) и чёрная дыра «Цифрового выхода» (S/PDIF).
12. **AC Odyssey (EMPRESS) + Wine** — «тихая смерть» на загрузке (окно 1x1,
    GPU ~5%, loader_section таймауты) это гонка загрузчика Wine, а не железо:
    лечится `WINEDEBUG=+loaddll` (trace замедляет гонку) + DXVK DLL рядом с
    exe; dxvk.conf (`enableGraphicsPipelineLibrary=False`) НАОБОРОТ убивает
    запуск. Шейдеры кэшируются — второй запуск быстрее.
13. **OBS хоткеи на Wayland** — нативные хоткеи OBS работают только в
    фокусе (безопасность Wayland). Победа: плагин Wayland Hotkeys
    (Global Shortcuts portal) + клавиши в dconf системы, не в OBS;
    формат: `shortcuts` (не binding), `<Control><Shift>r`.
14. **Глобальные клавиши на любой софт** — три уровня: 🟢 приложение
    поддерживает портал (плагин), 🟡 мост через WebSocket/CLI +
    кастомный шорткат DE, 🔴 evdev-демон. Комбо вместо одиночных клавиш.
15. **Видеоплееры** — VLC (универсал, host-доступ из коробки) +
    Celluloid (mpv-движок, для блогера: HEVC, скриншоты, скорость).
    «Формат не поддерживается» во flatpak-плеере = ПЕСОЧНИЦА
    (xdg-pictures), не кодеки: лечится `flatpak override --filesystem=home`.

## Структура

```
fedora-windows-look/
├── SKILL.md                  # этот файл
├── references/
│   ├── 01-speedup.md         # аудит → службы → загрузка → GNOME → ядро
│   ├── 02-warm-colors.md     # тёплые цвета: Night Light, VCGT, DDC
│   ├── 03-windows-look.md    # тёмная тема, шрифты, иконки, курсоры, звуки, расширения
│   ├── 04-terminals.md       # Alacritty, WezTerm, Konsole + Cascadia Mono
│   ├── 05-zram.md            # zram-своп (универсально)
│   ├── 06-disks.md           # форматирование/монтирование дисков
│   ├── 07-rustdesk-games.md  # RustDesk: чёрный экран (Wayland/NVIDIA) + FPS до 120
│   ├── 08-swapfile-backup.md # файл подкачки на диске: страховка от OOM за zram
│   ├── 09-vpn-torrents.md    # WireGuard VPN + быстрые торренты (сидбокс)
│   ├── 10-obs-studio.md      # OBS: установка (Flatpak) + запись NVENC/CQP/144fps
│   ├── 11-rear-audio-jack.md # «мёртвый» задний зелёный: пин кодека выключен (hda-verb)
│   ├── 12-ac-odyssey-wine.md # AC Odyssey (EMPRESS) + Wine: loader_section deadlock → WINEDEBUG=+loaddll, DXVK рядом с exe, без dxvk.conf
│   ├── 13-obs-wayland-hotkeys.md # OBS хоткеи на Wayland: комбо + плагин Global Shortcuts portal + dconf
│   ├── 14-global-hotkeys-wayland.md # глобальные клавиши на любой софт: портал / WebSocket-мост / evdev
│   └── 15-video-players-vlc-celluloid.md # видеоплееры: VLC + Celluloid, фикс sandbox «не видит файлы»
├── scripts/
│   ├── audit.sh              # read-only аудит системы (один запуск — вся картина)
│   └── apply-zram.sh         # установщик zram (RAM/2, zstd, swappiness 150)
└── README.md
```

## Безопасность

- Скрипты `audit.sh` — read-only; `apply-zram.sh` — идемпотентный, есть `--dry-run`.
- Каждая команда с `sudo` — только с согласия владельца; деструктивные
  операции (диски) — с явным подтверждением.
- Шрифты Microsoft (Segoe UI, Cascadia) — проприетарные: установка локальная,
  по выбору владельца (альтернатива — взять из существующего Windows-раздела).

## References (первоисточники)

- Ускорение: github.com/winterofhell/fedora-optimizations ·
  copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos ·
  discussion.fedoraproject.org · phoronix.com/review/cachyos-x86-64-v3-v4
- Цвета: github.com/zb3/gnome-gamma-tool · wiki.archlinux.org (Wayland gamma)
- Терминалы: github.com/wez/wezterm · github.com/mbadolato/iTerm2-Color-Schemes
- zram: docs.kernel.org/admin-guide/blockdev/zram.html ·
  wiki.archlinux.org/title/Zram · github.com/systemd/zram-generator
