# 02 · Warm display colors like Windows (GNOME + Wayland)

Goal: replicate the pleasant, warm Windows-like display look on Fedora
Workstation (GNOME + Wayland). Windows drivers apply gamma/color corrections;
Linux does not, so the panel often looks cold and flat.

Environment: Fedora, GNOME + Wayland, NVIDIA GPU (proprietary driver — DDC/CI
over i2c works; with nouveau it does NOT respond), external monitor on DP-1.
Tested on GNOME 45–50. Color work is driver-agnostic (colord VCGT + Mutter).
Mutter's Wayland does not expose wlr-gamma-control, so gammastep/wl-gammactl
will NOT work. Night Light is one gamma path, plus colord ICC profiles via VCGT.

**The single biggest "cold/flat" fix is usually the MONITOR's own color preset**
— many ship at 7500 K (bluish); set it to 6500 K via DDC (§4).

## Why it matters

- The eye perceives 7500 K screens as "cheap cold" and 5200–6500 K as
  "comfortable warm" — this is the whole Windows-vs-Linux first impression.
- VCGT gamma survives reboots and stacks with Night Light, no extra services.
- Fixing the monitor's hardware preset fixes the base; software layers tune on top.

## 1. Night Light (warmth) — built-in, no packages

```bash
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic false
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 4200
```

- `temperature`: 6500 = neutral, lower = warmer. 4000–4200 = comfortable warm.
- GUI alternative: Settings → Displays → Night Light → always on + slider.
- GOTCHA: gsd-color may silently set `night-light-enabled` back to `false`
  when other keys change. Always re-verify and set it LAST.
- Prefer the VCGT temperature from §2 instead — same warmth, no Night Light
  flakiness, survives reboots.

## 2. gnome-gamma-tool (gamma / temperature / contrast / brightness) — persistent via VCGT

Works on GNOME Wayland by cloning the active ICC profile and adding a VCGT gamma
table; survives reboot and stacks with Night Light. Does NOT change saturation
or hue (VCGT limitation).

```bash
git clone --depth 1 https://github.com/zb3/gnome-gamma-tool ~/gnome-gamma-tool
cd ~/gnome-gamma-tool
./gnome-gamma-tool.py -g 0.95 -t 5200   # warm 5200K via VCGT, night light OFF
```

- `-g 0.95` — gamma (0.9 = brighter/softer midtones but washed out; 0.95 is the
  sweet spot; 1.0 = neutral). Per channel: `-g 0.95:0.95:0.95`.
- `-t 5200` — color temperature (warm, "Windows feel", works WITHOUT Night Light).
  Tuning range seen in practice: 4800–5300; 5200 is a good landing point.
- `-c 1.05` — contrast (1 = default; `-1` inverts).
- `-b 0.7` — brightness (decrease only, max output; 1 = neutral). `-bm 0.05` — minimum black level.
- `-a` — apply to all monitors; `-d N` — display index (same order as Settings → Color).

Prerequisite check (Fedora):
```bash
python3 -c "import gi; gi.require_version('Colord','1.0'); from gi.repository import Colord"
```
(Debian/Ubuntu needs `gir1.2-colord-1.0`, openSUSE `typelib-1_0-Colord-1_0`.)

## 3. Verify the profile is active

```bash
colormgr get-devices
```
The active profile should show `gnome-gamma-tool-<uuid>.icc` under `Profile 1`
(original EDID profile under `Profile 2`).

## 4. Monitor OSD + DDC/CI (brightness/color) — needs proprietary NVIDIA driver

STATUS: with the proprietary NVIDIA driver DDC/CI works; with nouveau it is dead
(no monitor responds on any i2c bus). Find the display's bus:
`ddcutil detect` → note the `I2C bus: /dev/i2c-N` next to `Display 1`.
GOTCHA: `ddcutil` always prints "Device /dev/i2c-0 ... EACCES" — that bus is the
GPU adapter with no display; IGNORE it, the display bus works fine.

Findings + fixes (the REAL cause of the cold/flat look):
- **Color preset was 7500 K** (cold!) → set to **6500 K**: `ddcutil setvcp 14 0x05`.
  Available presets (VCP 0x14): 01=sRGB, 05=6500K, 06=7500K, 08=9300K, 0b=User 1.
- **Contrast was 50/100** (flat, washed out) → set to **75**: `ddcutil setvcp 12 75`.
- **Brightness was 99/100** (max — harsh white) → set to **80**: `ddcutil setvcp 10 80`.
- After the 6500K preset, per-channel video gain (VCP 16/18/1A) auto-adjusted to
  R > B (warmer at hardware level).
- Save into monitor EEPROM: `ddcutil setvcp 0C 1` (also via OSD menu save).
- GOTCHA: switching the color preset (0x14) RESETS contrast back to 50 and the
  gains — always re-apply in this order: preset → contrast → brightness → save.
  After saving, values persist across power cycles.
- Other commands: `ddcutil getvcp 14` (check preset), `ddcutil capabilities`
  (list features). Works on Wayland. Permissions: Fedora ships 60-ddcutil-i2c.rules
  with uaccess tag (works for the logged-in user without sudo).
- Manual OSD options (monitor buttons): RGB range = **full** (not limited), picture
  mode "Warm"/"sRGB", saturation/vivid control — the only way to get
  "Digital Vibrance" punch (VCGT cannot change saturation).

## 5. Verify after relogin / next session

```bash
echo "== Night Light (expect false or user-chosen)"; gsettings get org.gnome.settings-daemon.plugins.color night-light-enabled; \
gsettings get org.gnome.settings-daemon.plugins.color night-light-temperature; \
gsettings get org.gnome.settings-daemon.plugins.color night-light-schedule-automatic
echo "== Gamma profile (expect gnome-gamma-tool-*.icc under Profile 1)"; \
colormgr get-devices | grep -E 'Profile 1|Profile 2'
echo "== Monitor via DDC (expect 6500 K / 75 / 80)"; ddcutil getvcp 14 2>/dev/null | grep -iE 'current'; \
ddcutil getvcp 12 2>/dev/null | grep -iE 'current'; ddcutil getvcp 10 2>/dev/null | grep -iE 'current'
```

Expected: DDC lines show `6500 K (sl=0x05)` / contrast `75` / brightness `80`.
`ddcutil` prints an EACCES warning about /dev/i2c-0 — harmless noise, the
display is on another bus.

## 6. Max refresh rate — GNOME applies it automatically at login

Verified live: monitor ART G24F144 (144 Hz) on DP-1, GNOME Wayland,
1920x1080 @ 143.993. `xrandr` shows the live mode with `*+`:
`1920x1080    143.88*+` — the max rate IS active, not just "set" somewhere.

- **Where it lives:** `~/.config/monitors.xml` (version="2" on GNOME 45+)
  — the `<rate>143.993</rate>` per connector. At every login / monitor
  (re)connect, mutter applies it automatically. **That IS the "auto max
  Hz":** nothing else to install or run.
- **Check now:** `xrandr | grep '\*'` (current rate, `*+` = primary)
  or `cat ~/.config/monitors.xml | grep -i rate`.
- **Set manually (one-time):** Settings → Displays → Refresh Rate →
  144 → Apply; monitors.xml is rewritten with the new `<rate>`.
- **If the monitor moves to another connector** (DP-1 → HDMI-A-1), GNOME
  does not know that connector's spec → may fall back to 60 Hz. Fix: pick
  the rate once in Settings → xml is rewritten for the new connector.
- **Scripted safety net (the "other port" case), optional:** install
  `pip install --user gnome-monitor-config`, autostart entry calling
  `gnome-monitor-config set -p 1920x1080@144` (talks to mutter via D-Bus,
  works on Wayland; exact syntax per the tool's docs — this host does NOT
  need it, the xml already carries 144).
- 144 Hz frame pacing on DP is native here; VRR (Freesync) is a monitor
  OSD setting, not a GNOME one — unrelated to this section.

## Rollback

- Night Light: `gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled false`
- Gamma: re-run the tool with neutral values (`-g 1.0`) or remove the profile via
  `colormgr delete-profile <profile-id>` (list ids with `colormgr get-profiles`).
- The tool itself can be deleted after applying; the profile persists.
- Windows-look rollbacks (theme, cursors, sounds, extensions) — `03-windows-look.md` §Rollback.

## Notes

- GPU matters: with NVIDIA proprietary driver, `nvidia-settings` color controls
  are X11-only and do nothing under GNOME Wayland. The proprietary driver is also
  required for DDC/CI to work (nouveau: no i2c response).
- The single biggest "cold/flat" fix is the monitor's own color preset
  (7500 K → 6500 K). Combined stack: 6500K preset × VCGT 5000K × gamma 0.95 ×
  DDC brightness 80 × contrast 75.
- Everything here is user-scope (gsettings, `~/.local/share/icc/`), no sudo
  needed except for package installs and system-extension installs.
