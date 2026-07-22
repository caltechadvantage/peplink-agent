#!/bin/bash
#
# Mirror the physical touchscreen over VNC and bridge it to noVNC on
# 127.0.0.1:6080 — which the ngrok 'screen' tunnel points at.
#
# Runs from the desktop autostart so it inherits the session env
# (DISPLAY/XAUTHORITY on X11, WAYLAND_DISPLAY/XDG_RUNTIME_DIR on Wayland).
# Enable via .env:  DTS_ENABLE_SCREEN=1  (optional DTS_VNC_PASSWORD on X11).
#
# Pi OS Bookworm defaults to a Wayland compositor (labwc/wayfire); x11vnc
# cannot capture Wayland, so we use wayvnc there and fall back to x11vnc on a
# real X11 session. Either way the local touchscreen keeps working while the
# browser shows a live, controllable mirror.

cur_dir="$( cd "$(dirname "$0")/.." ; pwd -P )"
[ -f "${cur_dir}/.env" ] && { set -a; . "${cur_dir}/.env"; set +a; }

# Opt-in only.
[ "${DTS_ENABLE_SCREEN:-0}" = "1" ] || exit 0

LOG="$HOME/.pl/screen_share.log"
mkdir -p "$HOME/.pl"

if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    # --- Wayland session: use wayvnc (captures XWayland clients too) ---
    if ! pgrep -x wayvnc >/dev/null 2>&1; then
        echo "$(date) starting wayvnc (Wayland)" >>"$LOG"
        wayvnc 127.0.0.1 5900 >>"$LOG" 2>&1 &
    fi
    if [ -n "${DTS_VNC_PASSWORD:-}" ]; then
        echo "NOTE: DTS_VNC_PASSWORD is not applied under wayvnc — protect the" >>"$LOG"
        echo "      screen endpoint with ngrok edge auth instead." >>"$LOG"
    fi
else
    # --- X11 session: use x11vnc (supports an -rfbauth password) ---
    export DISPLAY="${DISPLAY:-:0}"
    if [ -n "${DTS_VNC_PASSWORD:-}" ]; then
        x11vnc -storepasswd "$DTS_VNC_PASSWORD" "$HOME/.pl/vncpasswd" >/dev/null 2>&1
        AUTH=(-rfbauth "$HOME/.pl/vncpasswd")
    else
        AUTH=(-nopw)
    fi
    if ! pgrep -x x11vnc >/dev/null 2>&1; then
        echo "$(date) starting x11vnc (X11)" >>"$LOG"
        x11vnc -display :0 -auth guess -forever -shared -noxdamage -repeat \
            -rfbport 5900 -localhost "${AUTH[@]}" -bg -o "$LOG"
    fi
fi

# Bridge noVNC (browser, 6080) -> VNC (5900); both localhost, ngrok adds TLS.
if ! pgrep -f "websockify.*6080" >/dev/null 2>&1; then
    websockify --web /usr/share/novnc 127.0.0.1:6080 127.0.0.1:5900 >>"$LOG" 2>&1 &
fi
