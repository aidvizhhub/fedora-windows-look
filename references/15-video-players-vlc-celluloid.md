# 15 · Video players: VLC + Celluloid install & the sandbox "no access" fix

<!-- meta
категория: C-железо-периферия
риск: L1 (flatpak для пользователя; без sudo)
preflight-гейт: flatpak (Flathub) доступен; NETWORK_ONLINE=yes
откат: в файле: flatpak uninstall / flatpak override --unset
-->

Verified live: Fedora (GNOME, Wayland), Flathub. Result: two players —
VLC (universal) and Celluloid (creator-friendly, mpv engine). Celluloid
could not open local MKV files out of the box — root cause was the
Flatpak sandbox (only `xdg-pictures`), NOT the player. Fix: one flatpak
override. No personal data below.

## Why these two (the "green + yellow" pairing)

- **VLC** — the universal one (🟢 green, MVP): plays almost anything
  (MKV/MP4/AVI/DVD/streams/YouTube URLs), hardware decoding, subtitles,
  no extra codec setup. Best for "just watch" and guests.
- **Celluloid** — the creator one (🟡 yellow, mpv engine): hardware
  decoding for HEVC/AV1, one-click frame screenshot, playback speed,
  two subtitle streams, clean GTK/GNOME look. Best for reviewing own
  recordings (HEVC MKV), taking stills, timeline scrubbing.
- They do NOT conflict: VLC for everything, Celluloid for creator work.

## Install (Flathub, 2 commands)

```bash
flatpak install -y flathub io.github.celluloid_player.Celluloid
flatpak install -y flathub org.videolan.VLC
```

## The trap: Celluloid "does not support MKV" — it's the sandbox

Symptom: Celluloid opens, but a local MKV shows as unplayable; mpv in
the sandbox logs:

```
Cannot open file '/home/<user>/video.mkv': No such file or directory
```

It is NOT a codec problem (libavcodec is bundled). It is the Flatpak
sandbox: the app only had permission for `xdg-pictures`:

```
flatpak info --show-permissions io.github.celluloid_player.Celluloid
# filesystems=xdg-run/pipewire-0:ro;xdg-pictures;xdg-run/gvfsd;xdg-run/gvfs;
```

→ files outside `~/Pictures` (Downloads, Documents, recordings folder)
simply do not exist for the sandbox.

### Fix (one command, persistent)

```bash
flatpak override --user --filesystem=home io.github.celluloid_player.Celluloid
```

- The override lives in
  `~/.local/share/flatpak/overrides/io.github.celluloid_player.Celluloid`
  (`filesystems=home;`) — OUTSIDE the sandbox, survives reboots and
  app updates.
- Verify:
  `flatpak info --show-permissions io.github.celluloid_player.Celluloid`
  → filesystems now contains `home`.

### Verification by fact

```bash
flatpak run --command=bash io.github.celluloid_player.Celluloid -c \
  'mpv --no-config --vo=null --ao=null --frames=5 "/home/<user>/video.mkv" 2>&1 | grep -E "Video|Audio"'
# expect: Video  --vid=1  (hevc ... fps)   Audio ... (aac ...)
```

Kill and relaunch the app afterwards — the override applies on every start.

## About VLC (no fix needed)

VLC flatpak ships `filesystems=host` — full filesystem access from the
sandbox, so it sees everything out of the box:

```
flatpak info --show-permissions org.videolan.VLC | grep filesystem
# filesystems=xdg-config/kdeglobals:ro;host;xdg-run/gvfs;
```

## Pitfalls

1. **"Does not support format X" in a Flatpak player == sandbox, not
   codecs** — check `flatpak info --show-permissions` FIRST.
2. **Kill before restart** (`flatpak kill <app-id>`, then run) — Flatpak
   reuses a running instance; the new permission only applies on a fresh
   launch. Single-instance canon.
3. **`--framework` tests**: test playback with `--vo=null --ao=null`
   (no window, no sound, fast) — verifies file access + decode without
   opening the GUI.
4. **Defaults matter**: VLC hardware decoding — set to Automatic in
   Preferences; Celluloid uses mpv's defaults (hwdec on by default in
   recent builds).

## Verified

2026-08-23: Celluloid override `filesystems=home` → fresh launch
reproduced HEVC 1920x1080 144 fps playback (`Video --vid=1 (hevc...)`);
override file present on disk after full restart. VLC reads /home files
via `host` without override. ✅
