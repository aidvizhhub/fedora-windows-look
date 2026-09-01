# 04 · Terminals like Windows Terminal (Alacritty, WezTerm, Konsole)

<!-- meta
категория: A-внешний-вид
риск: L1 (пакеты/конфиги, без системных прав)
preflight-гейт: DE любой; пакеты: dnf (Fedora) / pacman / apt — репозитории свои
откат: в файле: удаление пакетов / восстановление конфигов
-->

Windows Terminal look: dark background, Cascadia Mono, WT color schemes —
on three different terminals: Alacritty, WezTerm (GNOME world) and Konsole (KDE).

## Why it matters

- Windows Terminal's "Campbell" dark scheme (`#0C0C0C` bg) is easy on the eyes;
  pure black causes halation (letters bleed), worse for astigmatism.
- Cascadia Mono is the exact Windows Terminal font — familiarity for the user.

## Alacritty + WezTerm (GNOME / any desktop)

Install:
```bash
sudo dnf install -y alacritty        # 0.17.0, in Fedora repos
# wezterm NOT in Fedora repos — official RPM from GitHub releases:
curl -sL -o /tmp/wezterm.rpm https://github.com/wez/wezterm/releases/download/20240203-110809-5046fc22/wezterm-20240203_110809_5046fc22-1.fedora39.x86_64.rpm
sudo dnf install -y /tmp/wezterm.rpm   # fedora39 build works on 44; ~121 MiB
```
GOTCHAS:
- WezTerm: the original author stepped back in early 2024 (last release tag
  `20240203-110809-5046fc22`). The repo is NOT archived — actively developed by
  community maintainers in the SAME repo, but no new tagged releases are cut,
  so the releases page only has up to `fedora39` RPMs. The `20240203` RPM is
  therefore the newest installable release. There is no wezterm COPR either (404).
- Fedora's `cascadia-code-fonts` ships ONLY "Cascadia Code" (with ligatures) —
  the Mono family (Windows Terminal default) must be installed from the official
  release:
```bash
curl -sL -o /tmp/cascadia.zip https://github.com/microsoft/cascadia-code/releases/download/v2404.23/CascadiaCode-2404.23.zip
unzip -o -q /tmp/cascadia.zip -d /tmp/cascadia
mkdir -p ~/.local/share/fonts/cascadia-mono
cp /tmp/cascadia/ttf/CascadiaMono.ttf /tmp/cascadia/ttf/CascadiaMonoItalic.ttf /tmp/cascadia/ttf/CascadiaMonoPL.ttf /tmp/cascadia/ttf/CascadiaMonoPLItalic.ttf ~/.local/share/fonts/cascadia-mono/
fc-cache -f ~/.local/share/fonts/cascadia-mono
```
  (zip ≈ 150 MB; the 9-byte "Not Found" response = wrong URL.)

Configs (Windows Terminal Dark look: bg `#0c0c0c`, fg `#cccccc`, WT palette):
- Alacritty: `~/.config/alacritty/alacritty.toml` (0.17 = TOML format; font
  `Cascadia Mono` normal/bold/italic, size 12, WT Dark palette).
- WezTerm: `~/.config/wezterm/wezterm.lua` — `color_scheme = "Windows Terminal Dark"`,
  `font = wezterm.font("Cascadia Mono")`, font_size 12.
- GOTCHA: wezterm has NO `background = "<color>"` config key (that's a Vec for
  gradients) — it errors with "Cannot convert String to Vec"; the bg color comes
  from the color_scheme.
- Font verify: `wezterm ls-fonts`; alacritty config validates on launch
  (`timeout 3 alacritty`, exit 0).
- Alacritty hotkeys: `Ctrl+Shift+-`/`=` zoom, `Ctrl+Shift+C/V` copy/paste, `F11` fullscreen.

## Konsole (KDE) — Windows Terminal dark theme

Verified on Fedora (Konsole 26.x).

Key facts:
- Konsole color schemes live in `~/.local/share/konsole/*.colorscheme` (user) or
  `/usr/share/konsole/*.colorscheme` (system). On minimal Fedora installs the
  package ships NO schemes at all — you must create them.
- Scheme format: INI with `[Background]`, `[Foreground]`, `[Color0..Color7]`
  (+ `Intense`/`Faint` variants), `[General]` (`Description`, `Opacity`).
  Colors as `R,G,B` decimal.
- Windows canon:
  - Windows Terminal default "Campbell": background `#0C0C0C` (12,12,12),
    foreground `#CCCCCC`.
  - "One Half Dark" (a WT preset): background `#282C34` (40,44,52).
  - Font: **Cascadia Mono**.
  - Do NOT use pure black `0,0,0` — white-on-pure-black causes halation; dark
    gray is the WCAG recommendation. If the user insists, use `12,12,12`.
- Profiles live in `~/.local/share/konsole/` (root) or
  `~/.local/share/konsole/Profiles/`:
```ini
[Appearance]
AntiAlias=true
BoldIntense=false
ColorScheme=One Half Dark
DrawBoldTextAsBold=true
Font=Cascadia Mono,12,-1,5,50,0,0,0,0,0
LineSpacing=1.0

[General]
Name=Windows
Parent=FALLBACK/
Description=
```
- Default profile is set in `~/.config/konsolerc`:
  - `[Desktop Entry] DefaultProfile=<profile file name>`
  - `[UiSettings] ColorScheme=<scheme name>` (legacy fallback)
- Ready-made scheme sources (verified working):
  - `https://github.com/mbadolato/iTerm2-Color-Schemes` — `konsole/` folder has
    One Half Dark, Dracula, Nord, Gruvbox, Solarized, Catppuccin etc.
    `git clone --depth 1 https://github.com/mbadolato/iTerm2-Color-Schemes /tmp/iterm-schemes`
  - `https://raw.githubusercontent.com/dracula/konsole/master/Dracula.colorscheme`
  - `https://raw.githubusercontent.com/catppuccin/konsole/main/themes/catppuccin-mocha.colorscheme`

Steps:
1. Check what exists: `ls ~/.local/share/konsole/ ~/.local/share/konsole/Profiles/ 2>/dev/null; cat ~/.config/konsolerc`.
2. Get schemes (see above) or write the `.colorscheme` by hand.
3. Adjust background to `12,12,12` (sed the `[Background]`/`[BackgroundIntense]`
   Color lines; also `[BackgroundFaint]` if present).
4. Create/update the profile file (format above). Font `Cascadia Mono` —
   check: `fc-list | grep -i cascadia`; if missing: `sudo dnf install cascadia-code-fonts`.
5. Set `DefaultProfile` and `ColorScheme` in `~/.config/konsolerc`.
6. Remove other user profiles so only the chosen one remains:
   `rm ~/.local/share/konsole/Profiles/*.profile` (built-in fallback cannot be removed).
7. Restart Konsole — the running instance caches the default profile at startup;
   new tabs in the old instance do NOT pick it up:
   - SAFETY FIRST: check Konsole has no active sessions and that your own shell
     is NOT inside it: `ps --ppid $(pgrep -x konsole) -o pid,comm` (must be empty).
     If your shell's ancestry leads to konsole — do NOT kill it; ask the user
     to close Konsole manually.
   - `pkill -x konsole; sleep 2; pgrep -x konsole || (setsid nohup konsole >/dev/null 2>&1 & sleep 3; pgrep -x konsole)`

## GUI reference (manual switching)

- Konsole menu bar hidden: `Ctrl+Shift+M`.
- Path: Settings → Edit current profile… (NOT "Configure Konsole") → Appearance
  tab → Color scheme.

## Eye-health talking points (when asked "isn't dark mode better for eyes?")

- Dark mode is NOT proven by science to reduce eye strain; it helps subjectively at night.
- Pure black + white text causes halation/bloom, worse for astigmatism and poor
  vision. Dark gray (`#0C0C0C`–`#121212`) is the recommended compromise.
- Windows Terminal itself does not use pure black — Campbell is `#0C0C0C`,
  One Half Dark is `#282C34`.
