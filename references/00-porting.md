# 00 · Портирование: что универсально, а где швы

Репа **проверена живьём на одной связке**: **Fedora Workstation + GNOME + Wayland**
(+ NVIDIA). Это «золотой путь» — рецепт, который повторяется влёт, потому что
каждая строка кем-то щупана. На другой системе репа **не обещает 100%** — она
честно показывает, ГДЕ менять. Карта швов — ниже.

Правило то же, что и везде: гейты бери из `bash scripts/preflight.sh`
(`DISTRO`, `DE`, `SESSION_TYPE`, `GPU_VENDOR`), а не с потолка.

## Слой 1 — общий Linux (не трогаешь вообще)

Работает на любом дистро и любом рабочем столе — там только `systemctl`,
`pactl`/`amixer`, `lsblk`, `zramctl`, `wg`, стандартные тулы:

| Референс | О чём |
|---|---|
| `05-zram.md` + `scripts/apply-zram.sh` | сжатый своп (сам кросс-дистро: dnf/apt/pacman) |
| `06-disks.md` | диски, монтирование, fstab |
| `08-swapfile-backup.md` | своп-файл, защита от OOM |
| `09-vpn-torrents.md` | WireGuard, MTU/BBR, сидбокс |
| `11-rear-audio-jack.md` | мёртвый аудио-разъём / Auto-Mute (ALSA/HDA) |
| `12-ac-odyssey-wine.md` | Wine/Proton |
| `15-video-players-vlc-celluloid.md` | VLC/Celluloid |
| `17-opencode2.md` | AI-агент без sudo |
| `20-rustdesk-audio.md` | звук в RustDesk (PipeWire/PulseAudio) |
| `scripts/preflight.sh`, `audit.sh`, `diag-audio.sh` | портативные: всё через `command -v`, отсутствие тула → `UNKNOWN` |

Эти куски переносятся **как есть**. Если что-то не так — проблема в фактах
машины, а не в референсе.

## Слой 2 — 4 точки адаптации (правь тут, остальное оставь)

| # | Точка | Fedora+GNOME | Другое |
|---|---|---|---|
| 1 | **Пакеты** | `dnf install -y X` | `apt install -y X` / `pacman -S X` / `zypper in X` |
| 2 | **Настройки красоты** | `gsettings set SCHEMA KEY VAL` + расширения GNOME | KDE: `kwriteconfig6 ...`/плазмоиды; Sway/Hyprland: свой конфиг |
| 3 | **Сессия** | Wayland (порталы, mutter, direct-scanout) | X11: другой путь захвата/хоткеев |
| 4 | **GPU** | NVIDIA: NVENC, direct scanout, DDC | AMD/Intel: VAAPI, свой путь |

Где эти точки живут:

- **Пакеты (1):** `01`, `03`, `04`, `10`, `11`, `19`, `apply-windows-look.sh`, `apply-zram.sh`.
- **Красота/DE (2):** `01` (часть), `02`, `03`, `16`, `apply-windows-look.sh`.
- **Wayland→X11 (3):** `07`, `13`, `14`.
- **NVIDIA→AMD/Intel (4):** `02`, `07`, `10`.

## Слой 3 — GNOME-хард: не адаптация, а переписать

На KDE Plasma / Sway / Hyprland эти референсы **не заведутся** (тут `gsettings`,
расширения GNOME Shell, `mutter`). Нужна своя DE-ветка, а не правка строки:

- `02-warm-colors.md` (Night Light/VCGT через GNOME, mutter)
- `03-windows-look.md` (весь лук — тема/панель/расширения)
- `16-keyboard-layouts.md` (раскладки через gsettings)
- `scripts/apply-windows-look.sh` (целиком gsettings + GNOME-расширения)

## Как портировать (алгоритм)

```
1. bash scripts/preflight.sh   → DISTRO / DE / SESSION_TYPE / GPU_VENDOR
2. Разложи референс по слоям: 1 (общий) / 2 (точка адаптации) / 3 (переписать)
3. Слой 1 — как есть.
4. Слой 2 — поменяй ровно свою точку:
     dnf→apt/pacman · gsettings→тул DE · Wayland→X11 · NVENC→VAAPI
5. Слой 3 — НЕ трогай, если DE не GNOME: он просто не твой.
6. Числа (zram, swapfile, FPS, пин кодека, монитор) — всегда пересчитывай из
   preflight, чужой пример слепо не тащи.
```

## Чего репа НЕ обещает

- **100% на не-GNOME.** Обещает только на Fedora+GNOME+Wayland.
- **Что чужие числа подойдут.** Свои RAM/кодек/монитор/GPU → свои числа.
- **Что гейт ADAPT/SKIP — это «сломалось».** Это «по-другому, думай».

## Примеры замен

```bash
# пакеты
sudo dnf install -y htop      →  sudo apt install -y htop      →  sudo pacman -S htop

# красота (DE)
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
# KDE (аналог):
kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark

# сессия — универсально, не меняется
systemctl --user restart wireplumber
```

## References

- `references/00-preflight.md` — как читать гейты (DE/SESSION_TYPE/GPU_VENDOR).
- `SKILL.md` — категории A–G и протокол шага.
- Правило владельца: референсы — только примеры; живой прогон > переписанный текст.
