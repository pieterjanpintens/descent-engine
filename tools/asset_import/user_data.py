"""Where the app keeps its per-user files (Godot's `user://`), on Windows, macOS and Linux.

Every import tool in this folder writes there, so the app finds the results without any copying:
    Windows  %APPDATA%\\Godot\\app_userdata\\Descent-Engine
    macOS    ~/Library/Application Support/Godot/app_userdata/Descent-Engine
    Linux    $XDG_DATA_HOME (or ~/.local/share)/godot/app_userdata/Descent-Engine
"""

import os
import sys

APP_NAME = "Descent-Engine"


def user_data_dir(*parts: str) -> str:
    """The app's user folder, or a path below it: user_data_dir("weapon_data")."""
    if os.name == "nt":
        base = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "Godot")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "godot")
    return os.path.join(base, "app_userdata", APP_NAME, *parts)
