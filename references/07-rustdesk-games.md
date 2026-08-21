# 07 · RustDesk for games on Wayland + NVIDIA

Workflow: fix black screen (direct scanout + Wine virtual desktop) → boost FPS
(60–120, hardware codec) → verify with the remote partner.

## Why it matters

- On Wayland, RustDesk captures the screen via the PipeWire portal. A
  fullscreen window on NVIDIA gets **direct scanout** — rendered straight to
  the display, bypassing the compositor — so the portal sees a black frame.
  SELinux and VPN are NOT involved.
- RustDesk caps FPS at **30 by default** (`custom-fps = 30`) and encodes with
  slow software VP8/VP9. Hardware H.264/H.265 (NVENC on NVIDIA 2019+/Turing+)
  removes the CPU bottleneck and allows up to 120 FPS.
- There is NO Ctrl+Enter fullscreen toggle in RustDesk (Windows or Linux) —
  only the toolbar button (mouse to top edge). In games, windowed toggle is
  usually Alt+Enter, not Ctrl+Enter.
- **GNOME-only caveat**: the `MUTTER_DEBUG_PAINT` fix below targets **mutter —
  GNOME's compositor**. On KDE Plasma, Sway, Hyprland etc. this env var does
  nothing; those compositors need their own capture path (KDE: xdg-desktop
  portal + wlr-screencopy alternatives). This whole skill assumes GNOME.
- **Fedora = SELinux Enforcing by default.** SELinux does NOT cause the black
  screen, but it CAN block RustDesk in other ways (`avc: denied` → connection
  fails, clipboard/permissions break). On this machine SELinux was disabled
  during setup — see the SELinux section below for the honest trade-off.

## Safety rules

- Edit `~/.config/rustdesk/RustDesk.toml` ONLY while the service is stopped
  (`sudo systemctl stop rustdesk`) — otherwise it overwrites the file on exit.
- Always back up the config first: `cp RustDesk.toml{,.bak}`.
- The `MUTTER_DEBUG_PAINT=disable-direct-scanout` env var applies after the
  user logs out and back in (read at GNOME session start). Removing the file
  reverts it.
- Registry writes via `wine reg add` take effect only after the game restarts.
- Rollback: delete the `[options]` section / restore `.bak`; remove the
  `99-game-capture.conf` file; delete the Wine Desktop registry keys.
- SELinux changes are SYSTEM-WIDE security decisions — always show the user
  the trade-off and the exact revert command before touching `/etc/selinux/config`.

## SELinux on Fedora (honest section)

Fedora ships with **SELinux Enforcing** — this is a security layer, not a bug.
RustDesk on a fresh Fedora often hits `avc: denied` blocks (connection refused,
weird permission failures). Two ways to handle it:

1. **Keep SELinux, fix the policy (recommended for security):**
   ```bash
   getenforce                          # check current mode
   sudo ausearch -m avc -ts recent | grep -i rustdesk   # see the denials
   # Option A — temporary permissive (survives until reboot):
   sudo setenforce 0
   # Option B — permanent local policy module (proper fix):
   sudo dnf install setroubleshoot setools-console
   sudo sealert -a /var/log/audit/audit.log | grep -A5 rustdesk   # suggested fix
   # (audit2allow -M rustdesk && semodule -i rustdesk.pp — build local module)
   ```
2. **Disable SELinux (what was done on this machine):**
   ```bash
   sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
   # or permissive (logs denials but does not block):
   sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
   # Apply now without reboot:
   sudo setenforce 0        # 0 = permissive, 1 = enforcing
   ```
   **Honest warning**: disabling SELinux removes a real defense layer (it
   contains many exploits and misconfigurations). For a gaming/desktop box it
   rarely matters day-to-day, but if this machine ever holds sensitive data or
   is exposed to the internet, prefer permissive (or a policy module) over
   disabled. **Revert**: edit `/etc/selinux/config` back to `SELINUX=enforcing`
   and run `sudo setenforce 1` (persists only after reboot).

## Part 1 — Partner sees a black screen (game not visible)

1. **Disable direct scanout in mutter** (main fix, keeps Wayland;
   **GNOME-only** — mutter is GNOME's compositor, see caveat above):

   ```bash
   cat > ~/.config/environment.d/99-game-capture.conf <<'EOF'
   MUTTER_DEBUG_PAINT=disable-direct-scanout
   EOF
   # Log out and back in (or reboot). Delete the file to revert.
   ```

2. **Wine games — virtual desktop** (window instead of fullscreen):

   ```bash
   # Size = monitor size (check: xrandr | grep connected)
   wine reg add "HKCU\\Software\\Wine\\Explorer\\Desktop\\Default" /ve /t REG_SZ /d "1920x1080" /f
   wine reg add "HKCU\\Software\\Wine\\Drivers" /v Graphics /t REG_SZ /d "x11" /f
   # Takes effect after restarting the game.
   ```

3. **Also**: in-game resolution = monitor size; add `-windowed` to the game's
   `commandline.txt`.

**Quick test without logout**: set the Wine virtual desktop smaller than the
screen (e.g. 1600×900) — the window no longer covers the monitor, so direct
scanout can't trigger. If the partner then sees the game, the diagnosis is
confirmed.

**Still black?** Check: GNOME "Show screen" permission granted at connect;
NVIDIA driver newer than 555 (`nvidia-smi`); fallback = log into the
"GNOME on Xorg" session (cog icon at login).

## Part 2 — Boost FPS (30 → 120)

GUI path: **Settings → Display → Default image quality → Custom → FPS up to
120**; **Default codec → H.264** (or H.265); disable **"Auto adjust quality"**
(it drops FPS on any network jitter).

Config way (verified):

```bash
sudo systemctl stop rustdesk
cp ~/.config/rustdesk/RustDesk.toml{,.bak}

cat >> ~/.config/rustdesk/RustDesk.toml <<'EOF'

[options]
image-quality = 'custom'
custom-fps = 120
codec-preference = 'h264'
EOF

grep -A5 '^\[options\]' ~/.config/rustdesk/RustDesk.toml   # verify
sudo systemctl start rustdesk
```

Real FPS depends on: direct P2P vs relayed connection (icon shows the type),
the partner's monitor (60 Hz = max 60 visible) and decoding power, and the
host's NVENC (1080p@120 is easy on 2019+ NVIDIA). Verify with the quality
monitor icon in the session corner.

Other tools: AnyDesk (Performance → H.264 + 60 FPS), TeamViewer (Advanced →
60 FPS), Steam Remote Play (120 FPS), **Sunshine + Moonlight** — best for
games (120–144 FPS, NVENC, minimal latency).
