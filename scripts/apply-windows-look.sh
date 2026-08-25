#!/usr/bin/env bash
# apply-windows-look.sh — make another Fedora/GNOME box look EXACTLY like the main PC.
# Canon: references/03-windows-look.md (verified on the main machine, Fedora 44, GNOME 50).
# Idempotent: safe to run again. Use --dry-run to preview only.
# Usage: bash apply-windows-look.sh [--dry-run] [--assets /path/to/windows-look-assets.tar.gz | --assets /tmp/...]
set -u

DRY=0; ASSETS=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --assets) ASSETS="${2:-}" ;;
  esac
done

log(){ echo "[look] $*"; }
doit(){ if [ "$DRY" = 1 ]; then log "DRY: $*"; else eval "$*"; fi; }

# 0. Facts
SHELL_VER=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
log "GNOME shell: ${SHELL_VER:-?} (needs 45+)"
log "OS: $(grep -E '^(NAME|VERSION_ID)=' /etc/os-release 2>/dev/null | tr '\n' ' ')"

# 0b. RPM prerequisites (batch install, one sudo call)
REQUIRED_PKGS="git curl tar gzip unzip adw-gtk3-theme cascadia-code-fonts xcursorgen"
MISSING=""
for p in $REQUIRED_PKGS; do
  if ! rpm -q "$p" >/dev/null 2>&1; then MISSING="$MISSING $p"; fi
done
if [ -n "$MISSING" ]; then
  log "missing RPMs:$MISSING — installing (one sudo dnf call)..."
  if [ "$DRY" = 1 ]; then
    log "DRY: sudo dnf install -y$MISSING"
  else
    if sudo dnf install -y $MISSING 2>&1 | grep -qiE "no package available|nothing provides"; then
      log "WARN: some of$MISSING not found in current repos — check dnf history for the exact ones"
    fi
  fi
else
  log "RPM prerequisites — all present ✅"
fi
log "NOTE: dash-to-panel/arcmenu/blur-my-shell/ding do NOT exist as RPMs —"
log "      they are installed from extensions.gnome.org (phase 3 below)."

# 1. gsettings — the whole "look" (no sudo, safe)
G(){ gsettings set "$1" "$2" 2>/dev/null; }
if [ "$DRY" = 1 ]; then
  log "DRY: 30+ gsettings (theme/fonts/cursor/icon/sound/panel) — skipped"
else
  G org.gnome.desktop.interface color-scheme 'prefer-dark'
  G org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
  G org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
  G org.gnome.desktop.interface accent-color 'blue'
  G org.gnome.desktop.interface clock-format '24h'
  G org.gnome.desktop.interface clock-show-date true
  G org.gnome.desktop.interface text-scaling-factor 1.1
  G org.gnome.desktop.interface cursor-size 24
  G org.gnome.desktop.interface font-name 'Segoe UI 11'
  G org.gnome.desktop.interface document-font-name 'Segoe UI 12'
  G org.gnome.desktop.interface monospace-font-name 'Cascadia Mono 11'
  G org.gnome.desktop.interface icon-theme 'Fluent-dark'
  G org.gnome.desktop.interface cursor-theme 'win11-aero'
  G org.gnome.desktop.sound theme-name 'win11'
  G org.gnome.desktop.sound event-sounds true
  # Windows-style taskbar (bottom) + start menu + blur + desktop icons
  G org.gnome.shell.extensions.dash-to-panel panel-position 'BOTTOM'
  G org.gnome.shell.extensions.arcmenu override-menu-theme true
  G org.gnome.shell.extensions.arcmenu menu-background-color 'rgba(48,48,49,0.98)'
  G org.gnome.shell.extensions.arcmenu windows-show-frequent-apps true
  G org.gnome.shell.extensions.arcmenu windows-show-pinned-apps true
  G org.gnome.shell.extensions.blur-my-shell.panel blur true
  G org.gnome.shell.extensions.blur-my-shell.panel static-blur true
  G org.gnome.shell.extensions.blur-my-shell.panel corner-radius 16
  G org.gnome.shell.extensions.ding icon-size 'standard'
  G org.gnome.shell.extensions.ding start-corner 'top-left'
  G org.gnome.shell.extensions.ding show-home true
  G org.gnome.shell.extensions.ding show-trash true
  G org.gnome.shell.extensions.ding arrangeorder 'NAME'
  G org.gnome.shell.extensions.ding keep-arranged false
  # black wallpaper
  G org.gnome.desktop.background picture-uri-dark ''
  G org.gnome.desktop.background picture-uri ''
  G org.gnome.desktop.background color-shading-type 'solid'
  G org.gnome.desktop.background primary-color '#000000'
  G org.gnome.desktop.background secondary-color '#000000'
  log "gsettings applied (if a key said 'schema not found' — extension not installed yet, see phase 3)"
fi

# 2. Assets (theme/icons/cursors/sounds/fonts) from the tarball — if provided
if [ -n "$ASSETS" ] && [ -f "$ASSETS" ]; then
  log "unpacking assets from $ASSETS"
  if [ "$DRY" = 1 ]; then log "DRY: tar xzf"; else
    tar xzf "$ASSETS" -C "$HOME"
    fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null
    log "assets unpacked + font cache rebuilt"
  fi
else
  log "assets tarball not given — check fonts/icons/cursors/sounds first:"
  log "  fc-list | grep -i segoe   (Segoe UI — else references/03 §3)"
  log "  ls ~/.local/share/icons/Fluent-dark ~/.local/share/icons/win11-aero ~/.local/share/sounds/win11"
fi

# 3. Extensions (system-wide; needs sudo + network; zip from extensions.gnome.org)
declare -A EXT=( [dash-to-panel@jderose9.github.com]=dash-to-panel
                 [arcmenu@arcmenu.com]=arcmenu
                 [blur-my-shell@aunetx]=blur-my-shell
                 [ding@rastersoft.com]=ding )
for uuid in "${!EXT[@]}"; do
  if [ -d "/usr/share/gnome-shell/extensions/$uuid" ]; then
    log "extension $uuid — already installed"
    continue
  fi
  log "extension $uuid — MISSING, installing (needs sudo + net)..."
  if [ "$DRY" = 1 ]; then log "DRY: would download+install $uuid"; continue; fi
  zip="/tmp/${uuid}.shell-extension.zip"
  pk=$(curl -s "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${SHELL_VER}" \
        | grep -o '"pk":[0-9]*' | head -1 | cut -d: -f2)
  if [ -z "$pk" ]; then log "no pk for $uuid on shell $SHELL_VER — install manually (references/03 §4)"; continue; fi
  curl -sL -o "$zip" "https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${pk}" || { log "download failed: $uuid"; continue; }
  sudo mkdir -p "/usr/share/gnome-shell/extensions/$uuid"
  sudo unzip -qo "$zip" -d "/usr/share/gnome-shell/extensions/$uuid" 2>/dev/null
  sudo restorecon -R "/usr/share/gnome-shell/extensions/$uuid" 2>/dev/null
  sudo chmod -R a+rX "/usr/share/gnome-shell/extensions/$uuid"
  sudo glib-compile-schemas "/usr/share/gnome-shell/extensions/$uuid/schemas" 2>/dev/null
  gsettings set "$uuid.schemas" dummy 2>/dev/null  # warm schema cache path (harmless)
  rm -f "$zip"
  log "installed $uuid — relaunch gsettings of its keys after login"
done

log "done. EXTENSION KEYS apply after LOG OUT/IN (shell scans dirs only at startup)."
log "Then check: gnome-extensions info <uuid>  (should be ACTIVE)"
