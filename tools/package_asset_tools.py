"""Builds Descent-Engine-asset-tools.zip: everything a friend needs to import the real game art/data from their own install
(see tools/asset_import/FRIENDS_GUIDE.md), without the 140 MB of the full project.

The import scripts expect to live inside the project: they read a few of its scripts as text (OfficialAssetMap.gd,
MonsterDisplay.gd, HeroCatalog.gd), and the two Godot steps run headless against the project folder. So the zip holds a MINIMAL
project - a project.godot with the same name as the app (the files must land in the app's user folder, which is named after
it), the three scripts the tools parse (in folders with a .gdignore so Godot does not try to compile them), and tools/asset_import.

Usage: python tools/package_asset_tools.py [output.zip]     (run from anywhere; the release workflow runs it)
"""

import os
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TOP = "Descent-Engine-asset-tools"
DEFAULT_OUTPUT = os.path.join(ROOT, TOP + ".zip")

# The scripts the import tools read as text.
PARSED_SCRIPTS = ["autoload/OfficialAssetMap.gd", "scripts/MonsterDisplay.gd", "scripts/HeroCatalog.gd"]
# Dev-only tools of tools/asset_import that friends do not need.
SKIP_TOOLS = {"generate_shield_icons.py"}

PROJECT_GODOT = """config_version=5

[application]

config/name="Descent-Engine"
config/features=PackedStringArray("4.7")
"""

START_HERE = """Descent Engine - asset tools
============================

These tools copy the art and data out of YOUR OWN install of "Descent: Legends of the Dark" so the app can use it.
Nothing is downloaded and nothing leaves your computer.

1. Install Python 3 (tick "Add python.exe to PATH") and, for the 3D figures, Godot 4.7.2 (the Standard build, unzipped anywhere).
2. Double-click  tools\\asset_import\\import_all.bat
3. Read tools\\asset_import\\FRIENDS_GUIDE.md if something goes wrong.

Keep this folder as it is: the tools need the small project around them (project.godot, autoload, scripts).
"""


def main() -> None:
    output = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    entries: list[tuple[str, str | bytes]] = []  # (path inside the zip, source file path or the content itself)

    entries.append(("project.godot", PROJECT_GODOT))
    entries.append(("START-HERE.txt", START_HERE))
    for relative in PARSED_SCRIPTS:
        entries.append((relative, os.path.join(ROOT, relative)))
    for folder in {os.path.dirname(relative) for relative in PARSED_SCRIPTS}:
        entries.append((folder + "/.gdignore", ""))  # Godot skips a folder holding this file: the scripts stay plain text

    tools_dir = os.path.join(ROOT, "tools", "asset_import")
    for name in sorted(os.listdir(tools_dir)):
        path = os.path.join(tools_dir, name)
        if os.path.isfile(path) and name not in SKIP_TOOLS and not name.endswith(".pyc"):
            entries.append(("tools/asset_import/" + name, path))

    if os.path.exists(output):
        os.remove(output)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for inner, source in sorted(entries):
            target = TOP + "/" + inner
            if isinstance(source, str) and os.path.isfile(source):
                archive.write(source, target)
            else:
                archive.writestr(target, source)  # generated content
    print("Wrote %s (%d files)" % (output, len(entries)))


if __name__ == "__main__":
    main()
