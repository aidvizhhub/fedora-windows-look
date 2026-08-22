# 10 · OBS Studio: install + optimized local recording (Flatpak, NVENC, CQP, high-FPS)

Verified live: Fedora 44, OBS Studio 32.2.2 via Flatpak/Flathub, NVIDIA GPU with
Turing-or-newer NVENC, 1080p display with refresh above 120 Hz. Result: local
recording at 1920x1080 @ 144 fps, HEVC (NVENC) CQP 20, MKV container, AAC 192
kbps — near-zero CPU load, small files, no dropped frames. No personal data
below — only generic paths and placeholders.

## Why it matters

- **Recording is not streaming.** Streaming needs CBR (constant bitrate) to
  match the network ceiling; recording to disk should use **CQP** (constant
  quality) — the encoder spends bits only where the picture actually changes.
  CBR on a static screen wastes ~90 MB/min on nothing, then still looks blocky
  in fast motion. CQP typically halves file size and improves quality.
- **NVENC lives on its own silicon** — the CPU and the game rendering pipeline
  are barely affected (a few % of GPU at most). No x264, no CPU meltdown.
- **HEVC (H.265) is ~40–50% smaller than H.264 at the same quality** — the
  right codec for local recordings (AV1 needs RTX 40-series+, not available on
  older cards).
- Recording at the monitor's refresh rate (120/144 fps) keeps motion buttery;
  a 60 fps capture of a 144 Hz game skips frames.

## The setup (what was applied)

### 1. Install — Flatpak over distro RPM

Official OBS KB (obsproject.com/kb/linux-installation) recommends **Flathub**
for non-Ubuntu distros. The distro RPM lags behind upstream (e.g. 32.1.x vs
32.2.x) and can drag in GPG-key prompts from third-party repos.

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.obsproject.Studio
# give the sandbox access to GPU render nodes (needed for NVENC + capture):
flatpak override --user --device=all com.obsproject.Studio
flatpak run com.obsproject.Studio
```

Check the version and the available encoders in the startup log
(`flatpak run com.obsproject.Studio` > log, or
`~/.var/app/com.obsproject.Studio/config/obs-studio/logs/*.txt`):

```
[obs-nvenc] NVENC version: 13.0 (compiled) / 13.1 (driver), AV1 supported: false
- obs_nvenc_h264_tex (NVIDIA NVENC H.264)
- obs_nvenc_hevc_tex (NVIDIA NVENC HEVC)
```

`AV1 supported: false` on older GPUs is expected — use HEVC.

### 2. Recording settings — THE trap: encoders read `recordEncoder.json`, not `basic.ini`

Writing `RecRateControl=CQP`, `RecCQ=20` etc. into `[AdvOut]` of the profile
`basic.ini` **does nothing** for NVENC in OBS 30+ — the keys don't exist in the
source (verified in obsproject/obs-studio; `AdvancedOutput.cpp` loads encoder
settings from `GetDataFromJsonFile("recordEncoder.json")`). OBS silently keeps
the defaults (CBR 10 Mbps) while happily storing your dead keys back to disk.

The real file: `<PROFILE_DIR>/recordEncoder.json` where `<PROFILE_DIR>` is
`~/.var/app/com.obsproject.Studio/config/obs-studio/basic/profiles/<PROFILE_NAME>/`
(Flatpak) or `~/.config/obs-studio/basic/profiles/<PROFILE_NAME>/` (native).

`recordEncoder.json` — optimal quality/size for HEVC:

```json
{
	"rate_control": "CQP",
	"cqp": 20,
	"keyint_sec": 2,
	"preset": "p5",
	"tune": "hq",
	"multipass": "qres",
	"profile": "main",
	"lookahead": true,
	"adaptive_quantization": true,
	"bf": 2
}
```

Valid keys (from `plugins/obs-nvenc/nvenc-properties.c`): `rate_control`
(CBR|CQP|VBR|CQVBR), `cqp` (1–51), `keyint_sec` (0–10), `preset` (p1–p7),
`tune` (uhq|hq|ll|ull), `multipass` (disabled|qres|fullres), `profile`,
`lookahead`, `adaptive_quantization`, `bf`, `bframe_ref_mode`, `opts`.

CQP scale (industry consensus across 20+ sources): 15–18 visually lossless /
large; **19–23 excellent quality, sensible size — start at 20**; 24–26 soft;
27+ artifacts.

The container/audio keys in `basic.ini` still matter (same profile, `[AdvOut]`):

```ini
RecFormat2=mkv            ; MKV survives crashes; remux to MP4 in OBS (1 click)
RecEncoder=obs_nvenc_hevc_tex
RecTracks=1
Track1Bitrate=192         ; AAC 192 kbps is plenty
RecAudioEncoder=ffmpeg_aac
```

### 3. Resolution & FPS — `120/144` are NOT "Common FPS" values

`[Video]` in the same `basic.ini`:

```ini
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
ScaleType=bicubic
FPSType=2
FPSCommon=60
FPSInt=120
FPSNum=144
FPSDen=1
```

- Check the real monitor mode first: `xrandr | grep -E " connected|current"`
  (or `*` marker = active mode). Match canvas to it — default canvas is only
  1280x720@30.
- **FPSType 0 (Common) accepts ONLY** `10, 20, 24 NTSC, 25 PAL, 29.97, 48,
  50 PAL, 59.94, 60` — anything else silently becomes **30/1** (see
  `OBSBasic.cpp` `GetFPSCommon()`, `else { num = 30; }`). No 120, no 144.
- **FPSType 1 (Integer)**: `FPSInt=120` → 120/1. The right way for 120 fps.
- **FPSType 2 (Fraction)**: `FPSNum=144, FPSDen=1` → 144/1. Full match for a
  144 Hz display.
- The GPU's NVENC handles 1080p HEVC up to ~240 fps (NVIDIA NVENC app note),
  so 120/144 are safe — but verify the disk keeps up: 144 fps HEVC ≈ ~5 MB/s,
  any SSD is fine.

### 4. Verification

Start OBS, hit Record, then read the log:

```
[obs-nvenc: 'advanced_video_recording'] settings:
	codec:        HEVC
	rate_control: CQP        <- was cbr/10000 before the JSON file
	cqp:          20
	keyint:       60         <- 2 s at 30 fps / 120 at 60 fps, etc.
	preset:       p5
	tuning:       hq
	multipass:    qres
	profile:      main
	lookahead:    true (8 frames)
	aq:           true
[FFmpeg aac encoder: 'Track1'] bitrate: 192
video settings reset: fps: 144/1
```

Spot-check file sizes: a CQP 20 static-screen clip measured ~440 KB / 18 s vs
~173 MB for the same minutes at CBR 10 Mbps.

## Pitfalls (all hit live)

1. **`Rec*` encoder keys in `basic.ini` are ghosts for NVENC** — OBS saves them
   unchanged but never uses them. Edit `recordEncoder.json` (or the GUI).
2. **OBS overwrites `basic.ini` on exit** — edit profiles only while OBS is
   closed, then restart. Running instances fight over the file like two npm
   processes in one folder.
3. **`pkill -f "com.obsproject.Studio"` only kills the Flatpak wrapper** —
   `bwrap`/the real `obs` process survives, next launch prints
   "OBS is already running!" and you get multiple instances. Kill with
   `pkill -f "[o]bs"` (never combined with other commands in one line — the
   pattern also matches any log file name in your own command line and kills
   your own shell; rule: separate call, `[x]` guard, verify with `pgrep`).
4. **First launch errors** about `.sentinel` / `scenes.json` rename are a
   config-dir race — harmless, the folder is created by OBS itself.
5. **`video settings reset` showing 30/1** after writing `FPSCommon=120` is
   exactly the Common-FPS whitelist above — use Integer/Fraction modes.
6. **Flatpak sandbox + NVENC**: without `flatpak override --user --device=all`
   the GPU render nodes are not accessible.
7. **Wayland**: screen capture works out of the box via PipeWire (portal
   dialog asks what to share; per-session permission).

## Bonus: launching a GUI app from a CLI session

Flatpak/GUI apps started from SSH/terminal need the display env from the live
desktop process (systemd inherits almost nothing):

```bash
GPS=$(pgrep -f 'gnome-s[h]ell' | head -1)
export $(tr '\0' '\n' < /proc/$GPS/environ | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR)=' | tr '\n' ' ')
nohup flatpak run com.obsproject.Studio > /tmp/obs.log 2>&1 &
```
