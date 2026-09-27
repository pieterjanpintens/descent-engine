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

**Confirmed directly from the game's own data, not assumed**: unlike the
crop images (one per act - Weapon 1 = acti, Weapon 2 = actii, see
HeroCatalog.slot_crop()), there is only ONE real mesh per hero, and it only
exists under actii - acti has no "flat" model at all, just the regular
non-flat one. Both weapon slots in the combat view therefore reuse this
same single mesh/texture; there is no per-weapon mesh to bind separately.

Each hero's actii "<hero>.prefab" is a fully rigged SkinnedMeshRenderer
model (a bone armature, same shape Centurion's card turned out to have -
see import_monster_meshes.py's stage_centurion_flat() - though heroes need
no submesh-splitting, every material on a hero resolves to the SAME single
diffuse texture). It also carries a "Weapon" bone/socket with no geometry
attached - showing the actually-equipped weapon in-hand is out of scope
here; the mesh alone doesn't include one.

Picking the RIGHT SkinnedMeshRenderer needed real care - a hero's prefab
can contain MORE than one (Syrus's own prefab has 3: "Syrus" - his own
body - plus "Bird" and "Bird.Flame", an unrelated companion creature with
its own mesh/texture). Resolved by matching the MESH's own name against the
hero's name case-insensitively; falls back to the renderer with the most
vertices if no name match is found (a safety net, not currently exercised -
all 6 heroes checked resolve by name).

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


def find_hero_body_mesh_and_texture(env, hero):
    """Finds the hero's OWN SkinnedMeshRenderer (not a companion creature's,
    see module docstring - Syrus in particular) + its diffuse texture, from
    "<hero>/actii/prefabs/<hero>.prefab". Returns (mesh_data, texture_data),
    either of which may be None if not found."""
    folder = hero.lower()
    prefab_container = f"assets/d3/heroes/{folder}/actii/prefabs/{folder}.prefab"
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

    # Prefer the renderer whose mesh is literally named after the hero -
    # confirmed correct for all 6 heroes; the vertex-count fallback below is
    # an untested safety net for a hero this wasn't checked against.
    named_match = None
    for renderer in renderers:
        mesh = mesh_of(renderer)
        if mesh is not None and mesh.m_Name.lower() == hero.lower():
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
        print(f"  '{hero}': no mesh literally named '{hero}' among {len(renderers)} candidates - using the one with the most vertices")
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
        mesh, texture = find_hero_body_mesh_and_texture(env, hero)
        if mesh is None:
            print(f"  '{hero}': NO flat mesh found - combat view keeps the crop mockup")
            continue

        hero_staging_dir = os.path.join(STAGING_DIR, folder)
        os.makedirs(hero_staging_dir, exist_ok=True)
        obj_path = os.path.join(hero_staging_dir, "flat_0.obj")
        with open(obj_path, "w", encoding="utf-8") as f:
            f.write(mesh.export())
        staged.append(hero)
        print(f"  '{hero}': staged flat mesh -> {obj_path}")

        user_dir = os.path.join(USER_DATA_DIR, folder)
        os.makedirs(user_dir, exist_ok=True)
        if texture is not None:
            texture.image.save(os.path.join(user_dir, "flat_diffuse.png"))
            print(f"  '{hero}': saved texture -> {user_dir}\\flat_diffuse.png")
        else:
            print(f"  '{hero}': NO texture found - mesh will render untextured")

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

    print(f"\nDone. {len(staged)}/{len(heroes)} hero mesh(es) converted to")
    print(f"{USER_DATA_DIR}\\<hero>\\flat_0.tres - Godot will pick these up next run.")


if __name__ == "__main__":
    main()
