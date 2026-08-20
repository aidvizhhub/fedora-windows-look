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
| Ускорение | `references/01-speedup.md` | аудит → службы → загрузка → GNOME → ядро CachyOS |
| Тёплые цвета | `references/02-warm-colors.md` | Night Light, VCGT-гамма, DDC монитора |
| Windows-лук | `references/03-windows-look.md` | тёмная тема, Segoe UI, курсоры, звуки, расширения |
| Терминалы | `references/04-terminals.md` | Alacritty, WezTerm, Konsole + Cascadia Mono |
| zram | `references/05-zram.md` | сжатый своп: RAM/2, zstd, swappiness 150 |
| Диски | `references/06-disks.md` | форматирование, монтирование, fstab, NTFS-fix |
| Скрипты | `scripts/` | `audit.sh` (read-only аудит), `apply-zram.sh` (идемпотентный, `--dry-run`) |

## Быстрый старт

```bash
bash scripts/audit.sh                 # аудит, ничего не меняет
bash scripts/apply-zram.sh --dry-run  # zram: посмотреть план
bash scripts/apply-zram.sh            # zram: применить (sudo)
```

Дальше — по `SKILL.md`: цвета → лук → терминалы, каждая секция с откатами.

## Замечания

- Каждая правка обратима; деструктивные шаги — только с подтверждением владельца.
- Шрифты Microsoft — проприетарные, устанавливаются локально по выбору владельца.
- Проверено на реальных системах (Fedora 44, GNOME 50.3, NVIDIA); свежесть
  ссылок и версий пакетов — проверять перед применением.
