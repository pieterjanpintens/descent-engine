#!/bin/sh
# macOS / Linux: imports the official assets from your own copy of the game (see FRIENDS_GUIDE.md).
#   ./import_all.sh ["<game folder>" ["<Godot 4.7.2 program or Godot.app>"]]
# Uses its own Python environment (.venv next to this file), so nothing is installed system-wide.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HERE/.venv"

if [ ! -x "$VENV/bin/python" ]; then
    PYTHON="${PYTHON:-$(command -v python3 || true)}"
    if [ -z "$PYTHON" ]; then
        echo "Python 3 is needed. Install it (macOS: 'brew install python' or python.org) and run this again."
        exit 1
    fi
    echo "Setting up a Python environment in $VENV ..."
    "$PYTHON" -m venv "$VENV"
fi
if ! "$VENV/bin/python" -c "import UnityPy" 2>/dev/null; then
    echo "Installing UnityPy (reads the game files) ..."
    "$VENV/bin/python" -m pip install --quiet --upgrade pip
    "$VENV/bin/python" -m pip install --quiet UnityPy
fi
exec "$VENV/bin/python" "$HERE/import_all.py" "$@"
