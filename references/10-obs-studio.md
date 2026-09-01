# 10 · OBS Studio: install + optimized local recording (Flatpak, NVENC, CQP, high-FPS)

<!-- meta
категория: F-игры-контент
риск: L2 (flatpak + конфиги пульта; обратимо)
preflight-гейт: GPU_VENDOR=nvidia (NVENC) → ADAPT для amd/intel (VAAPI); SESSION_TYPE=wayland (захват)
откат: в файле: flatpak uninstall / восстановить конфиги
-->

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

## Profiles: what to use when, and how to create one

A profile in OBS bundles output + video settings (canvas, FPS, encoder,
quality, container) into one folder. Switch between them with one click
(Profiles menu) — no re-configuring each time. Three profiles cover the
common cases:

| Profile | Encoder | FPS | Use it for |
|---|---|---|---|
| Default / gameplay | HEVC (NVENC), CQP 20 | monitor refresh (120/144) | games, fast motion: smallest files, buttery motion. Costs the most in post (HEVC decode is heavy) |
| Review / screencast | H.264 (NVENC), CQP 20 | 60 | universal option: smooth enough, and H.264 decodes ~2-3x cheaper in any editor, so both recording and post-processing are comfortable |
| Talk / course / fast turnaround | H.264 (NVENC), CQP 20 | 30 | static screens (interfaces, slides, podcasts): visually almost identical to 60, but half the frames — fastest to process, smallest output |

Rule of thumb: **HEVC saves disk, H.264 saves time in post.** Static
content barely shows 30 vs 60 fps; fast motion does — hence gameplay at
monitor rate, reviews at 60, talks at 30.

### How to add a profile

**UI way (safe):** OBS → Profiles → Add → name it → Settings → Output:
encoder (NVENC H.264/H.265), Rate control CQP, 20, preset p5; Settings →
Video: FPS + canvas. OBS writes everything itself, no file editing.

**File way (automation; OBS must be closed** — it rewrites `basic.ini` on
exit, see Pitfalls §2):

```bash
SRC=<config>/basic/profiles/Default
DST=<config>/basic/profiles/Review-h264
cp -r "$SRC" "$DST"
```

Then touch two files inside `$DST`:

1. `basic.ini` — `[General] Name=` must match the **folder name** (otherwise
   OBS de-duplicates and hides the profile after restart); `[AdvOut]
   RecEncoder=obs_nvenc` (H.264; HEVC = `obs_nvenc_hevc_tex`); `[Video]` FPS
   block: `FPSType=0` (Common) + `FPSCommon=60` for 60/1 (30 for 30/1 —
   both are Common-whitelist values, §3).
2. `recordEncoder.json` — the **actual NVENC settings** (basic.ini `Rec*`
   keys are ghosts for NVENC, §2). Copying it from the source profile gives
   the same CQP/preset/tune; the same JSON keys are valid for both H.264
   and HEVC.

Restart OBS (fully: `pkill -f "[o]bs"`, §3), then verify in the fresh log:
`codec: H.264` (or HEVC), `rate_control: CQP`, `cqp: 20`, and
`video settings reset: fps: 60/1`.

Verified workflow: source profile (HEVC, 144 fps) duplicated into a
review profile (H.264 + `recordEncoder.json` copied) — switched by the
Profiles menu, recordings land with the right codec and presets.

## 60 FPS for delivery: bake once, deliver lighter (verified 25 Aug 2026)

### Why 60, not 144
Web platforms (YouTube, Telegram, most players) cap at **60 fps** anyway — 120/144
(§3) matter only for local playback on a matching-Hz monitor. For distribution,
baking at 60 fps is the 80/20 lever: **2.4× fewer frames** → render drops from
~11 min to ~5 min per 30-min clip, and the file gets ~2× lighter.

### The bake (branding + 60 fps in one pass)
```
VIDEO=src.mkv OUT=out.mkv bash ~/bake/scripts/bake.sh
```
- Script has `-r 60` / `fps=60` in the final pass (one-char switch back to 144).
- Does in ONE pass: 5-s logo intro (fade), semi-transparent watermark (bottom-right),
  running text on TOP (pendulum, bordered), ASS subtitles (44 px, styled, +5 s shift),
  loudnorm audio, perfect timestamps (concat-filter, not copy-join).
- Verified: 30:08 clip → 351 MB @ 60/1 (vs 711 MB @ 144/1); frames/audio/watermark
  checked frame-by-frame. The 144 version stays untouched for local viewing.

### 60 for OBS recording too
If the clip is meant for the web directly and no post-bake is planned — record at
**60 fps natively**: `basic.ini` `[Video] FPSType=0 + FPSCommon=60` (on the
Common-whitelist, §3), then no post-processing at all. 144 remains the local-review
profile (§ "Profiles").

## MP4 for delivery (Telegram/web): MKV master → MP4 road (verified 25 Aug 2026)

### Why two files
- **MKV = master** (storage/edits): HEVC copy fits lossless, container is crash-safe.
- **MP4 = road** (publishing): Telegram/players read it as media, not a file.
- Rule: never try to *copy* HEVC into MP4 (broken trailer, known trap) — instead
  **re-encode video to H.264** once for delivery.

### The delivery bake (H.264 for web, ~7.5x speed)
```
ffmpeg -i master.mkv -map 0:v -map 0:a -map 0:s \
  -c:v h264_nvenc -preset p4 -cq 21 -c:a copy -c:s mov_text \
  -metadata:s:s:0 language=rus -movflags +faststart out.mp4
```
- NVENC H.264 on the same clip ran **7.5x realtime** (30-min clip → ~4 min), vs ~2.8x for HEVC branding pass.
- Verified: 30:02 clip → 379 MB H.264 60/1 + AAC + mov_text subs; `moov` moved to
  the start (faststart) so playback starts instantly. Frames/watermark/line checked.
- File size chain: 711 MB (144/1 HEVC master) → 351 MB (60/1 HEVC web) → 379 MB (60/1 H.264 Telegram).

### OBS: record straight to MP4 — use **Hybrid MP4** (not plain MP4)
- Plain MP4 writes its index at the end: crash/power loss = unreadable file
  (14-crash lab: 0 of 14 recovered).
- **Hybrid MP4** (OBS 30.2+, official kb/hybrid-mp4): writes fragmented
  (crash-safe like MKV), then soft-remuxes into a regular MP4 at stop.
  Output is a genuine `.mp4` — media-ready everywhere. Hybrid: 13/14 recovered.
- Applied to profile `Редактор-h264` (backup first): `RecFormat2=hybrid_mp4`
  in BOTH `[AdvOut]` (was `mkv` — that's why OBS was giving MKV) and
  `[SimpleOutput]`. Backup: `basic.ini.bak-20260825`.
- GUI check after start: Settings → Output → Recording → Format: **Hybrid MP4**.
