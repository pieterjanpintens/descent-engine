"""Extracts each hero's real "flat" rigged mesh + diffuse texture from YOUR
OWN legally-purchased copy of the official "Descent: Legends of the Dark"
companion app, for the combat view's hero side (see CombatMeshPreview.gd,
HeroCatalog.flat_mesh_paths()/flat_diffuse_texture()) - the same idea as
import_monster_meshes.py's monster "flat card", extended to heroes once
they were confirmed to have an equivalent asset.

Same rule as every other tool in this folder: nothing here ships,
redistributes, or commits any copyrighted game content - it only reads
Unity AssetBundle files that already exist on your own machine and writes
the result to Godot's user:// data folder.

Requires: pip install UnityPy, and a real Godot 4.7.2 executable (same
reason as import_monster_meshes.py - see that script's own doc and
claude.md's "Mesh conversion: Godot's own native importer, not a
hand-rolled parser" section for why).

Usage:
    python import_hero_meshes.py <path to game's bundles folder> <path to Godot executable>

**Corrected 2026-09-27, same day**: an earlier version of this doc claimed
heroes only had ONE mesh (actii only), because the first search only looked
for "flat" in the container path - acti's own mesh isn't named "flat" (e.g.
Chance's acti mesh file is "vaerix.fbx"-style, just "<hero>.fbx", not
"<hero> flat.fbx"), so it was missed. Confirmed directly (the user found
both while inspecting the raw dump in Blender) that BOTH acti and actii
have a real, usable mesh, each with its own dedicated texture - exactly
mirroring the crop images (Weapon 1 = acti, Weapon 2 = actii, see
HeroCatalog.slot_crop()). Both weapon slots now get their OWN mesh/texture,
same as the crops - there is no reuse needed after all.

One naming exception, found the same way: Chance's ACTI mesh is internally
named "Meiyer", not "Chance" (their pre-established name in the game's own
lore, apparently) - HERO_BODY_MESH_NAME_OVERRIDES below records this, the
only hero/act combination that doesn't match by the hero's own name.

Each hero's actii "<hero>.prefab" is a fully rigged SkinnedMeshRenderer
model (a bone armature, same shape Centurion's card turned out to have -
see import_monster_meshes.py's stage_centurion_flat() - though heroes need
no submesh-splitting, every material on a hero resolves to the SAME single
diffuse texture). It also carries a "Weapon" bone/socket with no geometry
attached - showing the actually-equipped weapon in-hand is out of scope
here; the mesh alone doesn't include one.

Picking the RIGHT SkinnedMeshRenderer needed real care - a hero's prefab
can contain MORE than one (Syrus's own prefab has 3 on EACH act: "Syrus" -
his own body - plus "Bird"/"Syrus-Bird" and "Bird.Flame", an unrelated
companion creature with its own mesh/texture). Resolved by matching the
MESH's own name against the hero's name case-insensitively (or the
HERO_BODY_MESH_NAME_OVERRIDES entry for Chance's acti side - see above);
falls back to the renderer with the most vertices if neither matches (a
safety net, not currently exercised - every hero/act combination checked
resolves by name).

Texture resolution also needed a second key: some materials (any "Cloth"
piece, and Syrus's own body) use `_Diffuse` instead of the more common
`_MainTex` - both are checked, `_MainTex` preferred when both are present.
"""
import sys
import os
import re
import shutil
import subprocess
import UnityPy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
HERO_CATALOG_GD = os.path.join(PROJECT_DIR, "scripts", "HeroCatalog.gd")
CONVERT_SCRIPT_RES_PATH = "res://tools/asset_import/convert_staged_hero_meshes.gd"
STAGING_DIR = os.path.join(PROJECT_DIR, "models", "original", "hero_staging")
USER_DATA_DIR = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\hero_assets")

PREFERRED_TEX_KEYS = ["_MainTex", "_Diffuse"]

# Hero/act combinations whose body mesh isn't named after the hero itself -
# recorded by hand, once, same "can't be derived, only hand-authored"
# precedent as import_official_assets.py's own HERO_PORTRAIT_CONTAINERS.
HERO_BODY_MESH_NAME_OVERRIDES = {
    ("chance", "acti"): "meiyer",
}


def read_hero_names_from_gd():
    """Parses HeroCatalog.gd's HERO_NAMES array - never hand-duplicated,
    same "read the source of truth" convention as every other import
    script here."""
    with open(HERO_CATALOG_GD, "r", encoding="utf-8") as f:
        text = f.read()
    match = re.search(r"const HERO_NAMES: Array\[String\] = \[(.*?)\]", text)
    if not match:
        raise RuntimeError(f"Couldn't find HERO_NAMES array in {HERO_CATALOG_GD}")
    return re.findall(r'"([^"]+)"', match.group(1))


def find_hero_body_mesh_and_texture(env, hero, act):
    """Finds the hero's OWN SkinnedMeshRenderer for the given act ("acti" or
    "actii") - not a companion creature's, see module docstring - Syrus in
    particular - + its diffuse texture, from
    "<hero>/<act>/prefabs/<hero>.prefab". Returns (mesh_data, texture_data),
    either of which may be None if not found."""
    folder = hero.lower()
    prefab_container = f"assets/d3/heroes/{folder}/{act}/prefabs/{folder}.prefab"
    renderers = []
    for obj in env.objects:
        if obj.type.name != "SkinnedMeshRenderer":
            continue
        if (getattr(obj, "container", "") or "") != prefab_container:
            continue
        try:
            renderers.append(obj.read())
        except Exception:
            continue
    if not renderers:
        return None, None

    def mesh_of(renderer):
        try:
            return renderer.m_Mesh.read()
        except Exception:
            return None

    # Prefer the renderer whose mesh is literally named after the hero (or
    # this hero/act's recorded override, e.g. Chance's acti body is
    # internally "Meiyer") - confirmed correct for all 6 heroes on both
    # acts; the vertex-count fallback below is an untested safety net.
    wanted_name = HERO_BODY_MESH_NAME_OVERRIDES.get((folder, act), hero.lower())
    named_match = None
    for renderer in renderers:
        mesh = mesh_of(renderer)
        if mesh is not None and mesh.m_Name.lower() == wanted_name:
            named_match = (renderer, mesh)
            break
    if named_match is None:
        scored = []
        for renderer in renderers:
            mesh = mesh_of(renderer)
            if mesh is None:
                continue
            try:
                vcount = mesh.export().count("\nv ")
            except Exception:
                vcount = 0
            scored.append((vcount, renderer, mesh))
        if not scored:
            return None, None
        scored.sort(key=lambda x: -x[0])
        print(f"  '{hero}' ({act}): no mesh literally named '{wanted_name}' among {len(renderers)} candidates - using the one with the most vertices")
        _, renderer, mesh = scored[0]
        named_match = (renderer, mesh)

    renderer, mesh = named_match
    texture = None
    for mat_ptr in renderer.m_Materials:
        try:
            mat = mat_ptr.read()
        except Exception:
            continue
        for key in PREFERRED_TEX_KEYS:
            for tex_key, tex_env in mat.m_SavedProperties.m_TexEnvs:
                if tex_key != key or tex_env.m_Texture.path_id == 0:
                    continue
                try:
                    texture = tex_env.m_Texture.read()
                except Exception:
                    continue
                break
            if texture is not None:
                break
        if texture is not None:
            break
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

    heroes = read_hero_names_from_gd()
    print(f"Looking for {len(heroes)} hero(es): {heroes}")

    print("Loading bundles folder (this can take a while)...")
    env = UnityPy.load(bundles_dir)

    if os.path.isdir(STAGING_DIR):
        shutil.rmtree(STAGING_DIR)
    os.makedirs(STAGING_DIR, exist_ok=True)

    staged = []
    for hero in heroes:
        folder = hero.lower()
        hero_staging_dir = os.path.join(STAGING_DIR, folder)
        user_dir = os.path.join(USER_DATA_DIR, folder)
        any_staged = False
        # index 0 = acti = Weapon 1, index 1 = actii = Weapon 2 - same
        # convention HeroCatalog.slot_crop()'s weapon_index already uses.
        for weapon_index, act in enumerate(["acti", "actii"]):
            mesh, texture = find_hero_body_mesh_and_texture(env, hero, act)
            if mesh is None:
                print(f"  '{hero}' ({act}, weapon {weapon_index + 1}): NO mesh found - this weapon slot keeps the crop mockup")
                continue
            os.makedirs(hero_staging_dir, exist_ok=True)
            obj_path = os.path.join(hero_staging_dir, f"weapon_{weapon_index}.obj")
            with open(obj_path, "w", encoding="utf-8") as f:
                f.write(mesh.export())
            any_staged = True
            print(f"  '{hero}' ({act}, weapon {weapon_index + 1}): staged mesh -> {obj_path}")

            os.makedirs(user_dir, exist_ok=True)
            if texture is not None:
                texture.image.save(os.path.join(user_dir, f"weapon_{weapon_index}_diffuse.png"))
                print(f"  '{hero}' ({act}): saved texture -> {user_dir}\\weapon_{weapon_index}_diffuse.png")
            else:
                print(f"  '{hero}' ({act}): NO texture found - mesh will render untextured")
        if any_staged:
            staged.append(hero)

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

    print(f"\nDone. {len(staged)}/{len(heroes)} hero(es) converted to")
    print(f"{USER_DATA_DIR}\\<hero>\\weapon_<0|1>.tres - Godot will pick these up next run.")


if __name__ == "__main__":
    main()
