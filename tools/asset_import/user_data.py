"""Where the app keeps its per-user files (Godot's `user://`), on Windows, macOS and Linux.

Every import tool in this folder writes there, so the app finds the results without any copying:
    Windows  %APPDATA%\\Godot\\app_userdata\\Descent-Engine
    macOS    ~/Library/Application Support/Godot/app_userdata/Descent-Engine
    Linux    $XDG_DATA_HOME (or ~/.local/share)/godot/app_userdata/Descent-Engine
"""

import json
import os
import sys

APP_NAME = "Descent-Engine"


def user_data_dir(*parts: str) -> str:
    """The app's user folder, or a path below it: user_data_dir("weapon_data").

    The app itself (its in-game "Import game assets" button) passes its real user folder in DESCENT_USER_DIR."""
    if os.environ.get("DESCENT_USER_DIR"):
        return os.path.join(os.environ["DESCENT_USER_DIR"], *parts)
    if os.name == "nt":
        base = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "Godot")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "godot")
    return os.path.join(base, "app_userdata", APP_NAME, *parts)


def manifest_list(key: str):
    """What the app wants imported, when it runs the tools itself: the list stored under `key` in the JSON file
    named by DESCENT_IMPORT_MANIFEST ("official_assets" = our name -> official name, "monster_folders", "hero_names").
    None when the tools run from the project folder - they then read the project's own scripts instead."""
    path = os.environ.get("DESCENT_IMPORT_MANIFEST")
    if not path:
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle).get(key)


def staging_dir(name: str) -> str:
    """Where the app wants the staged .obj files ("" = not run by the app: the tools stage inside the project and let
    a Godot editor binary convert them). The app converts the staged files itself, so no Godot program is needed."""
    base = os.environ.get("DESCENT_STAGING_DIR")
    return os.path.join(base, name) if base else ""


## The game's text columns -> our language codes (one localization_<code>.json per column; the game has no Dutch).
LANGUAGE_CODES = {"English": "en", "Spanish": "es", "French": "fr", "German": "de", "Italian": "it", "Portuguese": "pt", "Polish": "pl",
                  "Czech": "cs", "Russian": "ru", "Hungarian": "hu", "Korean": "ko", "Chinese (Simplified)": "zh", "Chinese (Traditional)": "zh-TW"}
