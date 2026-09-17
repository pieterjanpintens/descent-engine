"""Extracts each monster's real "plastic pool" miniature mesh + texture from
YOUR OWN legally-purchased copy of the official "Descent: Legends of the
Dark" companion app, and converts them into the portable Godot resources
MonsterDisplay.gd loads at runtime from user://monster_assets/<name>/.

Same rule as the other tools in this folder: nothing here ships,
redistributes, or commits any copyrighted game content - it only reads
Unity AssetBundle files that already exist on your own machine and writes
the result to Godot's user:// data folder, where only YOU will ever see it.

Unlike import_official_assets.py/dump_all_assets.py, this tool ALSO needs a
real Godot 4.7.2 executable (not just Python) - see claude.md's "Mesh
conversion: Godot's own native importer, not a hand-rolled parser" section
for why: a hand-rolled runtime OBJ parser was tried first and consistently
produced wrong orientation/shading, while Godot's OWN native res:// OBJ
importer gets it right on the first try. This tool leans on that importer
directly (by shelling out to it, headless, twice) rather than re-deriving
its behavior by hand in Python.

Requires: pip install UnityPy

Usage:
    python import_monster_meshes.py <path to game's bundles folder> <path to Godot executable>

What it does, in order:
    1. Reads the monster list straight from MonsterDisplay.gd's own
       REAL_MONSTERS array - never hand-duplicated here, same "read the
       source of truth" convention import_official_assets.py already uses
       for OfficialAssetMap.gd's MAP dict - so this never drifts out of
       sync with which monsters the Player actually shows, and picks up
       new entries automatically once REAL_MONSTERS grows.
    2. For each monster, finds its "<folder> plastic pool.prefab" Mesh +
       diffuse Texture2D by CONTAINER PATH - mesh/texture internal names
       are NOT consistent across monsters (e.g. Zealot's own mesh is
       literally named "default"), but every plastic-pool asset's
       container path follows
       assets/d3/enemies/<folder>/prefabs/"<folder> plastic pool.prefab"
       (confirmed against Centurion/Zealot/Doomcaller/Fae, the 4 already
       wired into MonsterDisplay.gd).
    3. Exports each mesh as .obj into a TEMPORARY staging folder inside the
       actual Godot project (models/original/monster_staging/<folder>/ -
       already gitignored via the existing /models/original/ entry, same
       "local reference only, never committed" rule as every other
       official asset), and each texture straight to its final
       user://monster_assets/<folder>/diffuse.png (textures need no Godot
       import step - loaded via Image.load_from_file() at runtime, same
       as OfficialAssetOverrides already does for floor/underlay textures).
    4. Shells out to the given Godot executable, headless, twice: first
       `--import` to run every staged .obj through Godot's own native
       importer, then the checked-in one-off GDScript
       (convert_staged_meshes.gd, in this same folder) that loads each
       natively-imported mesh and re-saves it as
       user://monster_assets/<folder>/mesh.tres.
    5. Deletes the staging folder - nothing from step 3's .obj files is
       left behind in the actual project tree.

Re-run any time MonsterDisplay.REAL_MONSTERS gains a new monster, or a
mesh/texture needs re-extracting.
"""
import sys
import os
import re
import shutil
import subprocess
import UnityPy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
MONSTER_DISPLAY_GD = os.path.join(PROJECT_DIR, "scripts", "MonsterDisplay.gd")
CONVERT_SCRIPT_RES_PATH = "res://tools/asset_import/convert_staged_meshes.gd"
STAGING_DIR = os.path.join(PROJECT_DIR, "models", "original", "monster_staging")
USER_DATA_DIR = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\monster_assets")


def read_monster_folders_from_gd():
    """Parses MonsterDisplay.gd's REAL_MONSTERS array for each entry's
    "folder" value - never hand-duplicated, always matches what the Player
    actually looks for under user://monster_assets/."""
    with open(MONSTER_DISPLAY_GD, "r", encoding="utf-8") as f:
        text = f.read()
    match = re.search(r"const REAL_MONSTERS := \[(.*?)\n\]", text, re.DOTALL)
    if not match:
        raise RuntimeError(f"Couldn't find REAL_MONSTERS array in {MONSTER_DISPLAY_GD}")
    return re.findall(r'"folder"\s*:\s*"([^"]+)"', match.group(1))


def find_plastic_pool_mesh_and_texture(env, folder):
    """Finds the Mesh + diffuse Texture2D for one monster's "plastic pool"
    miniature, by CONTAINER PATH rather than internal object name (see
    module docstring for why). Returns (mesh_data, texture_data), either
    of which may be None if not found."""
    needle = f"/enemies/{folder}/".lower()
    mesh_candidates = []
    texture_candidates = []
    for obj in env.objects:
        type_name = obj.type.name
        if type_name not in ("Mesh", "Texture2D", "Sprite"):
            continue
        container = (getattr(obj, "container", "") or "").lower()
        if needle not in container or "plastic pool" not in container:
            continue
        try:
            data = obj.read()
        except Exception:
            continue
        if type_name == "Mesh":
            mesh_candidates.append(data)
        else:
            texture_candidates.append(data)

    mesh = None
    if mesh_candidates:
        mesh = mesh_candidates[0]
        if len(mesh_candidates) > 1:
            names = [getattr(m, "m_Name", "?") for m in mesh_candidates]
            print(f"  '{folder}': {len(mesh_candidates)} candidate meshes found {names}, using the first")

    texture = None
    if texture_candidates:
        # Prefer a "LightBake" (not "NoLightBake") variant - the shared,
        # per-monster diffuse, confirmed against all 4 already-verified
        # monsters - falls back to the first match otherwise.
        light_bake = [
            t for t in texture_candidates
            if "lightbake" in getattr(t, "m_Name", "").lower()
            and "nolightbake" not in getattr(t, "m_Name", "").lower()
        ]
        texture = light_bake[0] if light_bake else texture_candidates[0]
        if len(texture_candidates) > 1 and not light_bake:
            names = [getattr(t, "m_Name", "?") for t in texture_candidates]
            print(f"  '{folder}': {len(texture_candidates)} candidate textures found {names}, using the first")

    return mesh, texture


def run_godot(godot_exe, args, description):
    print(f"\nRunning Godot ({description})...")
    result = subprocess.run(
        [godot_exe, "--headless", "--path", PROJECT_DIR] + args,
        capture_output=True, text=True,
    )
    print(result.stdout)
    if result.stderr:
        print(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"Godot exited with code {result.returncode} during {description}")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    bundles_dir = sys.argv[1]
    godot_exe = sys.argv[2]

    folders = read_monster_folders_from_gd()
    print(f"Looking for {len(folders)} monster(s): {folders}")

    print("Loading bundles folder (this can take a while)...")
    env = UnityPy.load(bundles_dir)

    if os.path.isdir(STAGING_DIR):
        shutil.rmtree(STAGING_DIR)
    os.makedirs(STAGING_DIR, exist_ok=True)

    staged = []
    for folder in folders:
        mesh, texture = find_plastic_pool_mesh_and_texture(env, folder)
        if mesh is None:
            print(f"  '{folder}': NO mesh found - skipping")
            continue

        monster_staging_dir = os.path.join(STAGING_DIR, folder)
        os.makedirs(monster_staging_dir, exist_ok=True)
        obj_path = os.path.join(monster_staging_dir, "mesh.obj")
        with open(obj_path, "w", encoding="utf-8") as f:
            f.write(mesh.export())
        staged.append(folder)
        print(f"  '{folder}': staged mesh -> {obj_path}")

        user_dir = os.path.join(USER_DATA_DIR, folder)
        os.makedirs(user_dir, exist_ok=True)
        if texture is not None:
            texture.image.save(os.path.join(user_dir, "diffuse.png"))
            print(f"  '{folder}': saved texture -> {user_dir}\\diffuse.png")
        else:
            print(f"  '{folder}': NO texture found - figure will render untextured")

    if not staged:
        print("\nNothing staged - nothing to convert. Aborting.")
        shutil.rmtree(STAGING_DIR, ignore_errors=True)
        sys.exit(1)

    try:
        run_godot(godot_exe, ["--import"], "importing staged .obj files")
        run_godot(godot_exe, ["-s", CONVERT_SCRIPT_RES_PATH], "converting to .tres under user://")
    finally:
        shutil.rmtree(STAGING_DIR, ignore_errors=True)
        print(f"\nCleaned up staging folder {STAGING_DIR}")

    print(f"\nDone. {len(staged)}/{len(folders)} monster mesh(es) converted to")
    print(f"{USER_DATA_DIR}\\<folder>\\mesh.tres - Godot will pick these up next run.")


if __name__ == "__main__":
    main()
