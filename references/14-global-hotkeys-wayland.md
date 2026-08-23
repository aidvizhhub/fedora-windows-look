# 14 · Global hotkeys on Wayland: bind ANY action in ANY app (universal)

Verified live: Fedora, GNOME/Wayland. Pattern: an app that needs global
hotkeys (OBS, Discord PTT, game commands) can't hear keys without focus —
Wayland blocks it. The universal fix has three tiers; pick by effort.

## Why it matters

- Wayland apps only receive keyboard input when focused (anti-keylogging
  security). "Global" hotkeys inside a game/background app simply don't fire.
- The industrial solution is the **Global Shortcuts portal**
  (`org.freedesktop.portal.GlobalShortcuts`): the desktop environment (DE)
  captures the keys and delivers them to the app.
- If an app does not support the portal, the fallback is a **bridge**:
  DE hotkey → command → app (via CLI/WebSocket) — works everywhere.

## 🟢 Tier 1 — App supports the portal (the clean way)

Works for: OBS with the Wayland Hotkeys plugin, some modern apps.

1. Check the app's flatpak add-ons / plugin list for a "Wayland Hotkeys"
   or "Global Shortcuts" plugin; install it.
2. The plugin registers the app's actions into the DE, e.g. GNOME dconf:
   `/org/gnome/settings-daemon/global-shortcuts/<app-id>/shortcuts`
3. Keys live in the DE (System Settings or dconf), NOT in the app.
4. Result: the action fires from ANY window (game included) — global.

Format details (GNOME dconf, `a(sa{sv})` list per app):
```
('action_id', {'description': <'A description'>, 'shortcuts': <['<Control><Shift>r']>})
```
- dict key **`shortcuts`** (array of GTK accelerators in a variant);
- accelerator: `<Control><Shift>r` (GNOME may normalize order — same combo);
- never use legacy `binding` key; never double-wrap the variant.

## 🟡 Tier 2 — App speaks WebSocket/CLI (the bridge way)

Works for: anything with a local API (OBS WebSocket, mpv, MPD, Jellyfin, ...).

1. Expose the app API locally (e.g. OBS WebSocket server, port, password).
2. Install a tiny CLI that talks to it (e.g. `obs-cli`):
   `obs-cli recording.toggle` (same repo pattern: websocket clients exist
   for most apps).
3. In the DE: Settings → Keyboard → Customize Shortcuts → Custom Shortcuts
   → add a shortcut that runs the command:
   ```dconf
   /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/customN/
   name='Record Toggle'
   command='obs-cli recording.toggle'
   binding='<Control><Shift>r'
   ```
   plus register the path in
   `org.gnome.settings-daemon.plugins.media-keys custom-keybindings`.
4. Result: DE fires the command globally → app reacts. Works even if the
   app never implements the portal.

## 🔴 Tier 3 — Raw input daemon (the last resort)

Works for: proprietary/broken apps with no API.

- An evdev-based daemon reads keys directly from the input device and
  sends commands (e.g. `obs-hotkey` Rust daemon / `wayland-hotkey`).
- Pros: works on Wayland + X11. Cons: needs root or input-group access,
  keys are captured globally (conflict risk), more moving parts.
- Use only when Tier 1 and Tier 2 are impossible.

## Decision table

| Case | Pick |
|---|---|
| App has a Wayland Hotkeys plugin | 🟢 Tier 1 |
| App has WebSocket / CLI | 🟡 Tier 2 |
| Nothing works, app is closed-source | 🔴 Tier 3 |
| Just need a few global commands | 🟡 Tier 2 (custom shortcuts) |

## Universal rules

- **Combos only** — never single keys (accidental presses).
- **Check conflicts** — a game may bind the same combo; test from the game.
- **Verify by fact**: run the action from a NON-focused window (terminal
  is enough) and check the app's log / output file — not the screen.
- **One instance** — kill the old process before restarting (single
  instance canon: verify with pgrep, then start new).
- **Edit full config at once** — DE settings have no "update one element"
  API; read-modify-write the whole list, keep existing entries.

## Verified

2026-08-23: Tier 1 (OBS Wayland Hotkeys plugin, GNOME dconf) — recording
start/stop fired from a terminal while focus was NOT on OBS. ✅
