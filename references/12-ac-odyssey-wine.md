# 12 · Assassin's Creed Odyssey (EMPRESS) + Wine: loader_section deadlock — FIX

<!-- meta
категория: F-игры-контент
риск: L2 (переменные окружения Wine; обратимо)
preflight-гейт: GPU любой (DXVK); Wine + игра (EMPRESS) — личный выбор владельца; гейт F: проверить GPU_VENDOR
откат: в файле: снять WINEDEBUG/настройки
-->

Details how to get ACOdyssey (EMPRESS release, standalone, non-Steam) running
under stock Wine + DXVK when it hangs on the loading screen with
`loader_section` wait-timeouts. Verified live on Fedora (GNOME + Wayland,
proprietary NVIDIA driver, 6 GB VRAM GPU, 6-thread CPU). Hardware-agnostic:
the fix is about Wine/DXVK behavior, not the GPU.

## Why it matters

- The game dies "silently": window hides at 1x1, GPU barely used, process
  lives 10+ minutes then just exits — looks like a hardware/driver problem,
  but it is a Wine loader race.
- The "official-looking" internet fix (`dxvk.enableGraphicsPipelineLibrary = False`)
  actually makes it WORSE — it kills the launch.
- One correct launch line = playable game; wrong config = endless reboots.

## Symptom

- Game hangs on loading screen, window hidden (1x1), GPU ~5–7%,
  DXVK shader cache not growing.
- Log repeats every 60 s:
  `err:sync:RtlpWaitForCriticalSection ... "dlls/ntdll/loader.c: loader_section"
  wait timed out in thread X, blocked by Y, retrying (60 sec)`
- "Program not responding" dialog appears; clicking "Close" kills the process.

## Clues (how we found it)

- DXVK shader cache from the previous day (30 MB) = the game RAN before →
  something changed. The change was: reboot after a NVIDIA driver update.
  BUT the driver was NOT the culprit — the fix is in Wine/DXVK config.
- Same symptom reported by others (Whisky App issue #1108, WineHQ forums,
  unix.stackexchange 617117): ACOdyssey + Wine = loader deadlock.

## Working fix (verified multiple times)

1. **Put DXVK DLLs NEXT TO the game exe** (dxgi.dll + d3d11.dll into the game
   folder, same place as ACOdyssey.exe). Wine loads DLLs from the app folder
   FIRST — this is the industry canon (Nexus mod 299 for ACOdyssey).
   Installing DXVK only into `system32` is NOT enough for this game.
2. **Launch with `WINEDEBUG=+loaddll`** (NOT `-all`!): the DLL-load trace
   slows the loader down and breaks the race — the deadlock never forms.
   Opposite of the old "don't add WINEDEBUG" advice: for THIS crack,
   trace heals, `-all` kills.
3. **DO NOT create dxvk.conf in the game folder.** The internet-suggested
   `dxvk.enableGraphicsPipelineLibrary = False` (freeze fix) KILLS the launch —
   game dies from the same loader_section even with `+loaddll`.
   Tested: 2 launches with dxvk.conf = 2 deaths; without it = launches.
   One variable at a time — dxvk.conf is the culprit.

## Success indicators

- Window appears at full resolution (1920x1080, not 1x1)
- GPU 30%+ load, VRAM 3+ GB — game actually renders
- Process alive, game loads and starts

## Notes / gotchas

- If the user clicked "Close" in the "not responding" dialog — the process
  dies even though it could have started. Teach: WAIT, don't click.
- In-game stutters right after launch: shader compilation on first run
  (CPU 200%+, freezes) — NORMAL, passes. Do NOT "fix" via dxvk.conf (see #3).
- Shader cache persists between runs (~30 MB in AppData/Local/dxvk/) —
  second launch is faster.
- Use the same `WINEDEBUG=+loaddll` in every launcher script
  (menu shortcut, folder script, manual terminal line) — all three paths
  must point to the same working command.

## Verified

2026-08-23: ACOdyssey + wine-11.0-staging + DXVK 3.0.2, launch via script
with `WINEDEBUG=+loaddll`, DXVK DLLs beside the exe, no dxvk.conf. ✅
