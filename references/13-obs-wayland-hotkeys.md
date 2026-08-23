# 13 · OBS hotkeys on Wayland: combos + how to defeat the shortcut wall

Verified live: Fedora, GNOME (Wayland, modern GNOME Shell with the
Global Shortcuts portal), OBS Studio 32.x via Flathub + official
Wayland Hotkeys plugin. Result: global recording/streaming hotkeys that
fire from ANY window (game included) — no focus on OBS needed.

## Why it matters

- On Wayland, OBS native hotkeys only work while OBS has focus. In a game
  (focus on the game) they simply do not fire. This is not an OBS bug — it
  is Wayland security (no keylogging without focus).
- The industry answer is the **Global Shortcuts portal**: the desktop
  environment (GNOME/KDE) owns the keys and forwards them to the app.
- Once set up, you control recording/streaming from the middle of any game.

## The key combos (industry canon)

Rule: NEVER single keys (M, F1 — accidental presses in games/chat).
Always `Ctrl+Shift+<letter>` combos. Letters = mnemonics.

| Action | Combo | Mnemonic |
|---|---|---|
| ▶️ Start Streaming | Ctrl+Shift+S | **S**tream |
| ⏹️ Stop Streaming | Ctrl+Shift+X | **X** = stop |
| 🔴 Start Recording | Ctrl+Shift+R | **R**ecord |
| ⏹️ Stop Recording | Ctrl+Shift+E | **E**nd |
| ⏸️ Pause Recording | Ctrl+Shift+P | **P**ause |
| ▶️ Unpause Recording | Ctrl+Shift+U | **U**npause |
| 💾 Save Replay Buffer | Ctrl+Shift+B | **B**uffer |

## How to defeat Wayland (step by step)

### 1. Install the official Flatpak plugin

```bash
flatpak install -y flathub com.obsproject.Studio.Plugin.WaylandHotkeys
```

This plugin integrates OBS hotkeys with the Wayland Global Shortcuts Portal.
Works on GNOME 49+ / KDE Plasma 6+ (portal support).

### 2. Understand where the keys live now

On Wayland the keys live in the DESKTOP, not in OBS:
- dconf path per app:
  `/org/gnome/settings-daemon/global-shortcuts/com.obsproject.Studio/shortcuts`
- The list of actions is registered by the plugin (OBS start registers them).
- Shortcut bindings live INSIDE that list, per action.

### 3. Correct dconf format (the trap)

The entry is `a(sa{sv})`: list of `(action_id, {'description': ..., 'shortcuts': <[...]>})`.

CORRECT:
```dconf
('OBSBasic.StartRecording', {'description': <'Начать запись'>, 'shortcuts': <['<Control><Shift>r']>})
```

- Key name inside the dict: **`shortcuts`** (NOT `binding` — legacy/wrong).
- Value: variant of array of accelerator strings: `<['<Control><Shift>r']>`.
- Accelerator format: GTK style, `<Control><Shift>r`. GNOME may normalize
  the order to `<Shift><Control>r` — same combo, fine.

WRONG (breaks it):
- `'binding': ...` — old key, ignored.
- `<<'<Control><Shift>r'>>` — double variant, OBS will not read it.
- Writing a bad format can WIPE the whole `shortcuts` list (becomes
  `@a(sa{sv}) []`) — the plugin re-registers it on OBS restart.

### 4. Assign via dconf (edit full list, keep descriptions!)

Read, modify, write the WHOLE list in one shot (python/regex — dconf has
no "update element" API). Preserve `description` values.

### 5. Restart OBS so it picks up new bindings

`flatpak kill com.obsproject.Studio` (kills whole sandbox — canon:
single instance, family kill), then `flatpak run com.obsproject.Studio`.

### 6. Verify by FACT, not by looking at the screen

- `dconf read .../shortcuts | grep StopRecording` — binding present
- Press the combo from a NON-OBS window (terminal is enough — that proves
  global reach), then check the OBS log:
  `grep -E "Recording (Start|Stop)" <latest log>`
  or watch the output file appear/close. A closed mkv file = Stop fired.

## Pitfalls (all hit live)

1. **Native OBS hotkeys (basic.ini [Hotkeys]) are useless on Wayland** —
   they only fire with OBS focused. Keep them in sync or ignore them.
2. **Toggle vs separate Start/Stop**: the plugin registers both
   (`_toggle_recording`, `OBSBasic.StartRecording`, ...). If you assign BOTH
   to the same combo, the actions fight. Pick either toggle-only or
   separate start/stop.
3. **`ReplayBuffer.Save` appears only after Replay Buffer is enabled**
   in OBS settings. Until then use `_toggle_replay_buffer` for the Save key.
4. **stdout log lags** — OBS writes its own log file under
   `~/.var/app/com.obsproject.Studio/config/obs-studio/logs/`, buffer it;
   judge by files, not by stdout tail.
5. **flatpak run does not start a second instance** — if OBS is already
   running, `flatpak run` just activates it. Kill first, then run.

## Verified

2026-08-23: Ctrl+Shift+R started recording from a terminal (focus NOT on
OBS) — mkv created; Ctrl+Shift+E stopped it — mkv closed. Global hotkeys
work from any window. ✅
