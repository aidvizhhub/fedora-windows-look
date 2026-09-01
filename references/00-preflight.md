# 00 · Preflight: как читать отчёт и что с ним делать

Это мост «отчёт → действие». Все числа и пути ниже — ПРИМЕРЫ.
Реальные значения всегда бери из `bash scripts/preflight.sh` на этой машине.

## Как запускать

```bash
bash scripts/preflight.sh          # полный отчёт (read-only, без sudo)
bash scripts/preflight.sh --json   # машиночитаемо (для агентов/скриптов)
bash scripts/preflight.sh --deep   # + sudo-факты (только чтение; не по умолчанию)
```

Отчёт состоит из двух частей:
1. `KEY=value` — факты железа/ОС (что есть на этой машине).
2. `VERDICT <категория>: OK | ADAPT: <что менять> | SKIP: <почему>` — применимость
   категории целиком. Детали шага смотри в самом референсе.

## Ключи (и что они значат)

| Ключ | Источник | Примеры | Зачем |
|---|---|---|---|
| `DISTRO`, `VERSION` | /etc/os-release | fedora 44 / arch 0 / ubuntu 24.04 | пакеты: dnf/pacman/apt |
| `DE` | $XDG_CURRENT_DESKTOP | GNOME / KDE / Cinnamon | gsettings vs kwriteconfig |
| `SESSION_TYPE` | $XDG_SESSION_TYPE | wayland / x11 | хоткеи, RustDesk, OBS |
| `GPU_VENDOR`, `GPU_DRIVER` | lspci/lspci -k/nvidia-smi | nvidia / amd / intel | DDC, NVENC/VAAPI, direct scanout |
| `RAM_MB` | /proc/meminfo | 16384 | zram=RAM/2, правило swapfile |
| `CPU_X86_64_V3` | ld-linux --help | yes/no | гейт CachyOS ядра |
| `SECURE_BOOT` | mokutil --sb-state | on/off/unknown | гейт кастомного ядра |
| `VIRT` | systemd-detect-virt | none / kvm / oracle | маски служб (qemu-guest-agent и др.) |
| `ROOT_FS` | findmnt / | btrfs / ext4 / xfs | swapfile-особенности, fstab |
| `SWAP_STATUS` | swapon + zramctl | zram / disk / both / none | что уже сделано |
| `SHELL_VER` | gnome-shell --version | 50 | совместимость расширений EGO |
| `AUDIO_CODEC` | /proc/asound codec# | Realtek HDA (модель — из preflight) | фикс заднего разъёма |
| `MONITOR_INFO` | udevadm / drm / xrandr | 144Гц монитор на DP-1 | DDC/CI, частота, гамма |
| `NETWORK_ONLINE` | nmcli/ping | yes/no | VPN, npm, скачивания |

## Правило «референсы — только примеры»

1. Запусти preflight (если отчёта нет или он старше 1 дня).
2. Найди гейт шага в таблице ниже (или в шапке `<!-- meta -->` референса).
3. Сверь факт → вывод:
   - **OK** — команды из референса применимы, числа пересчитай из фактов;
   - **ADAPT** — применимо с изменением: покажи владельцу, ЧТО меняешь и ПОЧЕМУ;
   - **SKIP** — не применимо: назови причину и предложи альтернативу.
4. Никогда не переноси цифры из примеров, если они зависят от машины
   (zram-размер, swapfile, пин кодека, монитор, FPS).

## Категория → гейты → куда идти

| Категория | Уровень | Главные гейты | Если не проходит | Референс |
|---|---|---|---|---|
| A. Внешний вид | L1→L2 | DE=GNOME (03, 16); GPU/монитор (02 DDC) | другой DE → ADAPT (в 03 есть Cinnamon) | 02, 03, 04 (+01 шаг 3) |
| B. Производительность | L1→L3 | VIRT=none (маски); CPU_X86_64_V3+SECURE_BOOT (ядро); RAM_MB (zram) | VIRT=kvm → не маскировать qemu-агент; ядро → SKIP, дать шаги 1-3 | 01, 05, 08 |
| C. Железо и периферия | L2→L3 | AUDIO_CODEC=realtek (11); диски/ROOT_FS (06) | не realtek → ADAPT (пути другие); диски → L3, только с согласием | 06, 11, 15 |
| D. Софт и инструменты | L1→L2 | NETWORK_ONLINE=yes (17); DE=GNOME (16 GDM) | оффлайн → SKIP до сети | 16, 17 |
| E. Сеть и удалённый доступ | L2→L3 | NETWORK_ONLINE + свой VPS (09); SESSION_TYPE=wayland (14); согласие (19) | нет VPS → SKIP 09; X11 → ADAPT 14 | 09, 14, 19 |
| F. Игры и контент | L1→L3 | GPU_VENDOR=nvidia (07, 10 NVENC); SESSION_TYPE=wayland (13; 07) | amd/intel → ADAPT (VAAPI); X11 → ADAPT 13 | 07, 10, 12, 13 |
| G. Аудит и статус | L0 | — | — | preflight.sh, audit.sh |

## Чек-лист шага (протокол)

```
[ ] 0. Preflight прочитан, гейт шага сверен (OK/ADAPT/SKIP назван владельцу)
[ ] 1. План показан (dry-run/команды; числа — из фактов, не из примеров)
[ ] 2. Подтверждение получено (L3 → явное «да» + backup-план)
[ ] 3. Применено (по одной команде, с логом)
[ ] 4. Verify-команды из референса — факты, не «смотрится ок»; падение → СТОП + откат
[ ] 5. Откат записан в локальный журнал переноса владельца (вне git — в репозиторий не попадает)
```
