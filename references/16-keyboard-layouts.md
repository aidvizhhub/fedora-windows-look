# 16 · Keyboard layouts: Russian (RU) + English (US), Windows-style switch

Verified live: Fedora (GNOME, Wayland, GNOME 45–50) + `localectl`. Result:
two input sources (English + Russian), switch by **Alt+Shift** like on
Windows (GNOME default is Super+Space), same languages in console and on
the login screen.

## The goal

- Two layouts: **English** (coding, URLs) + **Russian** (typing).
- Switch with **Alt+Shift** — muscle memory from Windows.
- Layout indicator in the top bar.
- Same layouts in TTY console and on the login screen (GDM).

## User session (GUI, GNOME) — 3 commands

```bash
# 1. Languages (order matters: first = default on boot)
gsettings set org.gnome.desktop.input-sources sources "[('xkb','us'), ('xkb','ru')]"

# 2. Switch keys: Alt+Shift like Windows (keep Super+Space as backup)
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Alt>Shift_L', '<Super>space']"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Alt>Shift_R', '<Shift><Super>space']"
```

- Verify:
  `gsettings get org.gnome.desktop.input-sources sources`
  → `[('xkb', 'us'), ('xkb', 'ru')]` ✅
- GUI way (same thing): Settings → Keyboard → **Input Sources** → «+» →
  English (US) / Русский; switch keys: Settings → Keyboard → View and
  Shortcuts → Typing → «Switch to next input source».
- Indicator «EN/RU» in the top bar appears automatically when there are
  2+ sources; if hidden:
  `gsettings set org.gnome.desktop.input-sources show-all-sources true`

## Console (TTY) — system-wide

```bash
localectl set-x11-keymap us,ru   # X11/Wayland layout (system-wide)
localectl set-keymap ru          # console (tty1-6) keymap
```

- Verify: `localectl status` → `VC Keymap: ru, X11 Layout: us,ru` ✅
- No account needed — applies to the whole machine.

## Login screen (GDM) — for all users

GNOME reads GDM settings from dconf system-db `gdm`:

```bash
sudo mkdir -p /etc/dconf/db/gdm.d
sudo tee /etc/dconf/db/gdm.d/01-input-sources > /dev/null <<'EOF'
[org/gnome/desktop/input-sources]
sources=[('xkb','us'), ('xkb','ru')]
EOF
sudo dconf update
```

- Requires the profile `/etc/dconf/profile/gdm` containing
  `system-db:gdm` — present in stock Fedora; if absent on your host,
  create it with lines: `user-db:user` + `system-db:gdm`.
- Revert: `sudo rm /etc/dconf/db/gdm.d/01-input-sources && sudo dconf update`.

## Pitfalls

1. **Setting `switch-input-source` to ONLY Alt+Shift removes Super+Space** —
   keep `'<Super>space'` in the list (as above) unless you truly want only
   Alt+Shift.
2. **Order = default layout.** First entry is the one active on boot/login;
   put `'us'` first if you want English by default.
3. **`<Alt>Shift_L` vs `<Alt><Shift>l`** — the valid GSettings format is
   `'<Alt>Shift_L'` (modifier + key name). After setting, check with
   `gsettings get ...` — a bad value returns empty/null.
4. **GDM dconf does not affect user session** — the two are separate:
   GDM file covers only the login screen, user `gsettings` covers the
   session. Configure both for a consistent look (or skip GDM if the
   login screen language does not matter).
5. **Wayland + per-app layout** — `per-window` switching is off by default
   (`org.gnome.desktop.input-sources per-window false`); one global layout
   matches Windows behavior. Don't enable it unless you want per-app.

## Verified

2026-08-25: live host shows `sources=[('xkb','us'), ('xkb','ru')]`,
switch = `['<Super>space', 'XF86Keyboard']` (stock defaults), `localectl`
reports `VC Keymap: ru`, `X11 Layout: us,ru`, `LANG=ru_UA.UTF-8`;
`/etc/dconf/db/gdm.d` exists (the gdm dconf profile file was absent on
this host — check before the GDM step). ✅
