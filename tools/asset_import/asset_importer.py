"""The import tools as ONE program, run by the app's own "Import game assets" button (and packaged with PyInstaller
by build_importer.py, so players need no Python).

    asset_importer --bundles <game bundles folder> --out <the app's user folder> --manifest <json> --staging <folder>

Runs every import step in this one process. The app says what it wants (the manifest: official asset names, monster
folders, hero names - see user_data.manifest_list) and where its user folder is; the monster and hero meshes are only
STAGED as .obj files in --staging, the app converts them itself (no Godot editor needed).

Lines starting with "##" are for the app: "##STEP <n>/<total> <label>" when a step starts,
"##RESULT <label>|ok" or "##RESULT <label>|failed" when it ends, "##DONE" at the very end.
"""

import argparse
import os
import sys
import traceback

PROTOCOL = 1

STEPS = [
    ("Textures, portraits, icons", "import_official_assets"),
    ("Monster figures", "import_monster_meshes"),
    ("Hero models", "import_hero_meshes"),
    ("Weapon data", "import_weapon_data"),
    ("Item data", "import_item_data"),
    ("Monster data", "import_monster_data"),
    ("Original props", "import_original_props"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Imports the official game assets for the Descent Engine app.")
    parser.add_argument("--bundles")
    parser.add_argument("--out")
    parser.add_argument("--manifest")
    parser.add_argument("--staging")
    parser.add_argument("--protocol", action="store_true", help="print the protocol number and stop")
    options = parser.parse_args()
    if options.protocol:
        print(PROTOCOL)
        return 0
    if not (options.bundles and options.out and options.manifest and options.staging):
        parser.print_usage()
        return 2
    # One stream for everything: the app only reads the standard output, and an unread error stream would block
    # this program once it is full.
    sys.stdout.flush()
    os.dup2(sys.stdout.fileno(), sys.stderr.fileno())
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(line_buffering=True, errors="replace")

    # The tools read these when they are imported (their output folders are module constants).
    os.environ["DESCENT_USER_DIR"] = options.out
    os.environ["DESCENT_IMPORT_MANIFEST"] = options.manifest
    os.environ["DESCENT_STAGING_DIR"] = options.staging
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

    failed = 0
    for number, (label, module_name) in enumerate(STEPS, start=1):
        print("##STEP %d/%d %s" % (number, len(STEPS), label))
        ok = True
        saved_argv = sys.argv
        sys.argv = [module_name, options.bundles]
        try:
            module = __import__(module_name)
            result = module.main()
            ok = result in (None, 0)
        except SystemExit as stop:
            ok = stop.code in (None, 0)
        except Exception:
            traceback.print_exc()
            ok = False
        finally:
            sys.argv = saved_argv
        print("##RESULT %s|%s" % (label, "ok" if ok else "failed"))
        failed += 0 if ok else 1
    print("##DONE")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
