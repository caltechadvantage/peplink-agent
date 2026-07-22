#!/usr/bin/env bash
#
# Update the DTS Router Monitor (Peplink5) on a deployed Raspberry Pi.
#
# Safe to re-run on a working unit. Pulls the latest agent code,
# refreshes Python deps + compiled UI, and re-runs the remote-access
# install so units that pre-date the wayvnc/ttyd switch (i.e. anything
# still on Raspberry Pi Connect) get those tunnels added without a
# full ./setup.sh.
#
# Usage:    bash ./update.sh
# Logs:     ~/.dts-update.log (kept on disk for support)
# Reboot:   the systemd-managed remote-access tunnels restart in place,
#           but the on-screen agent runs from the desktop autostart -
#           reboot once at the end of an update window to pick up new
#           Python code on the touchscreen UI.

set -u
set -o pipefail

cur_dir="$( cd "$(dirname "$0")" && pwd -P )"
log_file="${HOME}/.dts-update.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"  | tee -a "$log_file"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"   | tee -a "$log_file"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$log_file"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"  | tee -a "$log_file"; }
step()  { echo -e "\n${CYAN}>>> $1${NC}\n" | tee -a "$log_file"; }

info "DTS Router Monitor update started $(date '+%Y-%m-%d %H:%M:%S')"
info "Working directory: $cur_dir"

if [ -f "$cur_dir/.env" ]; then
    info "Loading $cur_dir/.env"
    # shellcheck disable=SC1091
    set -a; . "$cur_dir/.env"; set +a
fi

# --- Step 1: download latest code --------------------------------------------
#
# Fetched as a tarball from the compiled dist repo, not `git pull`. The
# source repo is private, so a deployed unit has no credentials to clone it
# with; the dist repo is public and needs none. This also means a unit needs
# no git at all, and there is no working tree to diverge or force-reset.
#
# Pass a branch, tag, or commit as $1 to pin a specific build (default main).
step "Step 1: Downloading latest agent code"
DIST_REPO="${DTS_DIST_REPO:-caltechadvantage/peplink-agent}"
target="${1:-main}"
ver_before="$(cat "$cur_dir/VERSION" 2>/dev/null || echo unknown)"
info "Before: $ver_before"

tmp_tgz="$(mktemp -t peplink-agent.XXXXXX.tar.gz)"
tmp_dir="$(mktemp -d -t peplink-agent.XXXXXX)"
cleanup_dl() { rm -rf "$tmp_tgz" "$tmp_dir"; }
trap cleanup_dl EXIT

dl_url="https://codeload.github.com/${DIST_REPO}/tar.gz/${target}"
info "Fetching ${dl_url}"
if command -v curl >/dev/null 2>&1; then
    dl_ok=0; curl -fsSL --max-time 300 -o "$tmp_tgz" "$dl_url" >>"$log_file" 2>&1 && dl_ok=1
elif command -v wget >/dev/null 2>&1; then
    dl_ok=0; wget -q -T 300 -O "$tmp_tgz" "$dl_url" >>"$log_file" 2>&1 && dl_ok=1
else
    err "neither curl nor wget is available; cannot download the agent."
    exit 2
fi
if [ "${dl_ok:-0}" -ne 1 ]; then
    err "download failed ($dl_url). Check $log_file. Aborting update."
    exit 2
fi

if ! tar xzf "$tmp_tgz" -C "$tmp_dir" >>"$log_file" 2>&1; then
    err "could not extract the downloaded archive. Aborting update."
    exit 2
fi
# codeload unpacks to a single <repo>-<ref> directory; glob it rather than
# assuming the name, since a tag ref drops the leading "v".
src_dir="$(echo "$tmp_dir"/*/)"
if [ ! -d "$src_dir" ]; then
    err "unexpected archive layout under $tmp_dir. Aborting update."
    exit 2
fi
if ! cp -r "$src_dir". "$cur_dir/" >>"$log_file" 2>&1; then
    err "failed to copy the new agent into $cur_dir. Aborting update."
    exit 2
fi

ver_after="$(cat "$cur_dir/VERSION" 2>/dev/null || echo unknown)"
if [ "$ver_before" = "$ver_after" ]; then
    info "Already at the latest version ($ver_after) - refreshing system parts anyway."
else
    ok  "Updated code: $ver_before -> $ver_after"
fi

# --- Step 2: Python deps ------------------------------------------------------
step "Step 2: Refreshing Python dependencies"
if sudo pip3 install --break-system-packages -r "$cur_dir/requirements.txt" >>"$log_file" 2>&1; then
    ok "requirements.txt is satisfied"
else
    err "pip install failed. Check $log_file."
    exit 3
fi

# --- Step 3: compiled UI ------------------------------------------------------
# Only meaningful on a source checkout. A compiled dist ships the UI already
# built (as bytecode) and carries no .ui designer sources or compile_ui.py to
# rebuild from, so running this there would just log a spurious error.
step "Step 3: Recompiling UI files"
if [ -f "$cur_dir/ui/compile_ui.py" ]; then
    if python3 "$cur_dir/ui/compile_ui.py" >>"$log_file" 2>&1; then
        ok "UI compiled"
    else
        warn "compile_ui.py reported an error (see $log_file). Continuing."
    fi
else
    info "Compiled dist - UI ships prebuilt, nothing to recompile."
fi

# --- Step 4: remote-access install (ttyd + wayvnc + noVNC + ngrok) -----------
step "Step 4: Refreshing remote-access components"
if [ -z "${DTS_NGROK_AUTHTOKEN:-}" ]; then
    warn "DTS_NGROK_AUTHTOKEN is not set in .env - skipping remote-access refresh."
    warn "Remote-access tunnels (ttyd / wayvnc / noVNC) won't be installed/updated."
    warn "If you're moving this unit off Raspberry Pi Connect, add the authtoken and re-run."
else
    if [ ! -f "$cur_dir/scripts/setup_ngrok.sh" ]; then
        err "scripts/setup_ngrok.sh not found. Cannot refresh remote-access stack."
        err "Pull a newer version of the agent and re-run ./update.sh."
        exit 4
    fi
    if sudo DTS_NON_INTERACTIVE=1 \
            DTS_NGROK_AUTHTOKEN="${DTS_NGROK_AUTHTOKEN}" \
            DTS_NGROK_PREFIX="${DTS_NGROK_PREFIX:-}" \
            DTS_SSH_TCP_ADDR="${DTS_SSH_TCP_ADDR:-}" \
            DTS_NGROK_DOMAIN="${DTS_NGROK_DOMAIN:-}" \
            DTS_ENABLE_SCREEN="${DTS_ENABLE_SCREEN:-}" \
            DTS_VNC_PASSWORD="${DTS_VNC_PASSWORD:-}" \
            bash "$cur_dir/scripts/setup_ngrok.sh" >>"$log_file" 2>&1; then
        ok "Remote-access stack is current"
    else
        warn "setup_ngrok.sh reported an error (see $log_file). Continuing."
    fi
fi

# --- Step 5: restart anything that runs under systemd ------------------------
step "Step 5: Restarting systemd-managed components"
if systemctl list-unit-files 2>/dev/null | grep -q '^ttyd\.service'; then
    if sudo systemctl restart ttyd 2>>"$log_file"; then
        ok "ttyd restarted"
    else
        warn "ttyd restart failed; check journalctl -u ttyd"
    fi
else
    info "ttyd service not installed (expected on units without .env auth token)"
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^splashscreen\.service'; then
    sudo systemctl restart splashscreen 2>>"$log_file" || warn "splashscreen restart failed"
fi

# --- Done --------------------------------------------------------------------
step "Update complete"
info "Code: $ver_before -> $ver_after"
info "Log file: $log_file"
ok   "REBOOT THE PI to fully reload the touchscreen agent:  sudo reboot"
exit 0
