#!/bin/bash

# Launcher for the bridge GUI, run from the autostart .desktop entry.
# setup.sh copies this to /opt/pl_start.sh and rewrites the placeholder on
# the APP_HOME line below with the install directory, via a global sed.
#
# NOTE: that substitution is a plain substring replace, so no identifier or
# comment in this file may repeat the placeholder token - hence APP_HOME
# rather than the obvious name, which would otherwise be mangled too.
#
# Source checkouts run main.py directly. Compiled dists (peplink-agent)
# ship no .py at all: they carry main.pyc plus the package bytecode under
# a per-interpreter directory (py39/py311/py313), because a .pyc built for
# one Python minor will not load under another. Pick the directory matching
# the interpreter we are about to run and put it FIRST on PYTHONPATH, with
# the install dir after it so settings.py, font/ and assets/ still resolve.

APP_HOME="DIR"

cd "$APP_HOME" || exit 1

PYVER="$(python3 -c 'import sys; print("py%d%d" % sys.version_info[:2])' 2>/dev/null)"

if [ -f "$APP_HOME/main.py" ]; then
    # Source checkout.
    RUN_TARGET="main.py"
    RUN_PYPATH="$APP_HOME"
elif [ -f "$APP_HOME/$PYVER/main.pyc" ]; then
    # Compiled dist with bytecode for this interpreter.
    RUN_TARGET="$APP_HOME/$PYVER/main.pyc"
    RUN_PYPATH="$APP_HOME/$PYVER:$APP_HOME"
else
    echo "ERROR: no runnable agent found in $APP_HOME" >&2
    echo "       expected main.py (source) or $PYVER/main.pyc (compiled dist)." >&2
    echo "       available bytecode dirs: $(ls -d "$APP_HOME"/py3* 2>/dev/null | tr '\n' ' ')" >&2
    echo "       this interpreter is $(python3 --version 2>&1) -> $PYVER" >&2
    exit 1
fi

echo "Starting main GUI application ($RUN_TARGET)..."
screen -mS pl -d
screen -S pl -X stuff "export DISPLAY=:0.0\\r"
screen -S pl -X stuff "export PYTHONPATH=$RUN_PYPATH\\r"
screen -S pl -X stuff "cd $APP_HOME\\r"
screen -S pl -X stuff "python3 $RUN_TARGET\\r"
