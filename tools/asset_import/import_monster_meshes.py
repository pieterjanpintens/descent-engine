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

**Extended 2026-09-27 to also fetch each monster's FLAT ("card") mesh +
texture** - used by the combat view's monster side (CombatView.gd) instead
of the tab-image croptop. Same container-path idea as the plastic pool
mesh, but at "<folder> flat.prefab" instead - however Unity's own per-
object `container` attribution turned out to be far less reliable for
these nested prefabs (most sub-objects - the actual MeshRenderer/Material -
don't carry a usable container path at all, only the top-level Mesh/
Texture2D objects do), and several monsters have MULTIPLE Mesh/Texture2D
objects sharing that one container path (particle/glow/background-effect
pieces alongside the real card). Resolved with a JUNK-NAME EXCLUDE LIST
(`FLAT_JUNK_MESH_WORDS`/`FLAT_JUNK_TEXTURE_WORDS` below) rather than a full
material-graph walk (tried first, unreliable here - a `MeshRenderer`'s own
`m_Materials[0]` frequently turned out to be an unrelated effect's, not the
card's) - confirmed by hand against the real dump that filtering out
names containing "smoke"/"particle"/"glow"/"bg"/"background" (meshes) or
those plus "diamond"/"rune"/"lava"/"circle" (textures) leaves EXACTLY one
correct candidate for every monster checked. One monster (Fae) legitimately
has THREE separate mesh pieces after filtering (its card is a multi-piece
composition, not a single quad) - every kept mesh is staged and converted,
not just the first, so `flat_0.tres`/`flat_1.tres`/... all exist for it
while every other monster gets just `flat_0.tres`.

**Centurion is a genuine one-off, handled by its own dedicated function**
(`stage_centurion_flat()` below) - its regular "centurion flat.prefab" has
no plain Mesh at that container path at all (unlike every other monster);
its card is a single rigged `SkinnedMeshRenderer` with THREE submeshes,
each its own material: "Regular_ID1_Body" (the body, texture
`Centurion_ID1_DiffuseMap`), "Regular_ID2_Wings" (the wings, texture
`Centurion_ID2_DiffuseMap`), and "Regular_ID3_Cloth" (a cloth/cape piece,
REUSING the body's `Centurion_ID1_DiffuseMap`) - confirmed directly from
the SkinnedMeshRenderer's own `m_Materials`/`m_Mesh.m_SubMeshes`, not
guessed; there is no separate "rock" mesh/texture anywhere in this prefab.
Exported via UnityPy's `export_mesh_obj(mesh, material_names=[...])`
(bypassing the plain `Mesh.export()` every other monster uses, which
doesn't take a `material_names` argument) - this tags each submesh's
triangles with a "g"/"usemtl" group name in the .obj text, and Godot's own
native OBJ importer was CONFIRMED (a synthetic multi-group test through
this exact staging/import/convert pipeline) to split that into one
MULTI-SURFACE mesh, surfaces named after each group, even with no real
.mtl file present (the exporter never writes one, only the reference
line) - `mesh.tres`/`flat_0.tres` for Centurion therefore comes out as a
3-surface mesh, unlike every other monster's single-surface one. Grouped
as `["body", "wings", "body"]` (the cloth submesh reuses the "body" group
name on purpose, since it wants the same texture - Godot keeps same-named
groups as separate surfaces rather than merging them, confirmed
separately, but `MonsterDisplay.flat_surface_texture_overrides()`'s
name-keyed lookup handles that identically either way, so this needed no
special-casing on the Godot side). The wings' distinct texture is saved
alongside the body's as `flat_diffuse_wings.png`; `MonsterDisplay.
flat_surface_texture_overrides()` is what tells `MonsterCombatPreview.
show_meshes()` to use it only for surfaces literally named "wings".

**Not independently re-verified in-editor per monster** - the junk-word
filter was checked against the raw Unity dump, not against how each
extracted mesh actually LOOKS once rendered; treat these the same way
REAL_MONSTERS' own per-monster pitch/rotation corrections were treated -
a first pass, likely needing a real per-monster look and fix once seen.

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


FLAT_JUNK_MESH_WORDS = ["smoke", "particle", "glow", "bg", "background"]
FLAT_JUNK_TEXTURE_WORDS = FLAT_JUNK_MESH_WORDS + ["diamond", "rune", "lava", "circle"]


def find_flat_mesh_and_texture(env, folder):
    """Finds the card mesh piece(s) + diffuse Texture2D for one monster's
    "flat" card, by exact CONTAINER PATH plus a junk-name exclude list (see
    module docstring for why a material-graph walk wasn't used instead).
    Returns (list_of_mesh_data, texture_data) - the mesh list has more than
    one entry only for a genuinely multi-piece card (confirmed: Fae only)."""
    prefab_container = f"assets/d3/enemies/{folder}/prefabs/{folder} flat.prefab".lower()
    meshes = []
    textures = []
    for obj in env.objects:
        type_name = obj.type.name
        if type_name not in ("Mesh", "Texture2D"):
            continue
        container = (getattr(obj, "container", "") or "").lower()
        if container != prefab_container:
            continue
        try:
            data = obj.read()
        except Exception:
            continue
        (meshes if type_name == "Mesh" else textures).append(data)

    kept_meshes = [
        m for m in meshes
        if not any(word in getattr(m, "m_Name", "").lower() for word in FLAT_JUNK_MESH_WORDS)
    ]
    kept_textures = [
        t for t in textures
        if not any(word in getattr(t, "m_Name", "").lower() for word in FLAT_JUNK_TEXTURE_WORDS)
    ]
    texture = None
    if kept_textures:
        texture = kept_textures[0]
        if len(kept_textures) > 1:
            names = [getattr(t, "m_Name", "?") for t in kept_textures]
            print(f"  '{folder}' flat: {len(kept_textures)} candidate textures after filtering {names}, using the first")
    elif textures:
        texture = textures[0]
    return kept_meshes, texture


def stage_centurion_flat(env, monster_staging_dir, user_dir):
    """Centurion's own one-off flat-card extraction - see module docstring
    for why this can't go through find_flat_mesh_and_texture() like every
    other monster. Returns True if anything was staged."""
    from UnityPy.export.MeshExporter import export_mesh_obj

    prefab_container = "assets/d3/enemies/centurion/prefabs/centurion flat.prefab"
    skinned_renderers = []
    for obj in env.objects:
        if obj.type.name != "SkinnedMeshRenderer":
            continue
        if (getattr(obj, "container", "") or "") != prefab_container:
            continue
        skinned_renderers.append(obj.read())
    if not skinned_renderers:
        print("  'centurion': NO SkinnedMeshRenderer found for the flat card - keeping the crop mockup")
        return False
    renderer = skinned_renderers[0]

    group_names = []
    wings_texture = None
    body_texture = None
    for mat_ptr in renderer.m_Materials:
        mat = mat_ptr.read()
        is_wings = "wing" in mat.m_Name.lower()
        group_names.append("wings" if is_wings else "body")
        for key, tex_env in mat.m_SavedProperties.m_TexEnvs:
            if key != "_MainTex" or tex_env.m_Texture.path_id == 0:
                continue
            tex_data = tex_env.m_Texture.read()
            if is_wings and wings_texture is None:
                wings_texture = tex_data
            elif not is_wings and body_texture is None:
                body_texture = tex_data

    mesh = renderer.m_Mesh.read()
    obj_text = export_mesh_obj(mesh, material_names=group_names)
    if not obj_text:
        print("  'centurion': mesh export failed - keeping the crop mockup")
        return False

    os.makedirs(monster_staging_dir, exist_ok=True)
    obj_path = os.path.join(monster_staging_dir, "flat_0.obj")
    with open(obj_path, "w", encoding="utf-8") as f:
        f.write(obj_text)
    print(f"  'centurion': staged flat card mesh (body+wings+cloth, {len(group_names)} submeshes) -> {obj_path}")

    os.makedirs(user_dir, exist_ok=True)
    if body_texture is not None:
        body_texture.image.save(os.path.join(user_dir, "flat_diffuse.png"))
        print(f"  'centurion': saved body texture -> {user_dir}\\flat_diffuse.png")
    if wings_texture is not None:
        wings_texture.image.save(os.path.join(user_dir, "flat_diffuse_wings.png"))
        print(f"  'centurion': saved wings texture -> {user_dir}\\flat_diffuse_wings.png")
    return True


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
        user_dir = os.path.join(USER_DATA_DIR, folder)
        monster_staging_dir = os.path.join(STAGING_DIR, folder)

        if mesh is not None:
            os.makedirs(monster_staging_dir, exist_ok=True)
            obj_path = os.path.join(monster_staging_dir, "mesh.obj")
            with open(obj_path, "w", encoding="utf-8") as f:
                f.write(mesh.export())
            staged.append(folder)
            print(f"  '{folder}': staged plastic-pool mesh -> {obj_path}")

            os.makedirs(user_dir, exist_ok=True)
            if texture is not None:
                texture.image.save(os.path.join(user_dir, "diffuse.png"))
                print(f"  '{folder}': saved plastic-pool texture -> {user_dir}\\diffuse.png")
            else:
                print(f"  '{folder}': NO plastic-pool texture found - figure will render untextured")
        else:
            print(f"  '{folder}': NO plastic-pool mesh found - skipping")

        # The combat view's flat "card" - see module docstring. Centurion is
        # its own one-off (stage_centurion_flat()), everyone else goes
        # through the generic exclude-list resolution below.
        if folder == "centurion":
            if stage_centurion_flat(env, monster_staging_dir, user_dir) and folder not in staged:
                staged.append(folder)
            continue
        flat_meshes, flat_texture = find_flat_mesh_and_texture(env, folder)
        if not flat_meshes:
            print(f"  '{folder}': NO flat card mesh found - combat view keeps the crop mockup")
            continue
        os.makedirs(monster_staging_dir, exist_ok=True)
        for i, flat_mesh in enumerate(flat_meshes):
            flat_obj_path = os.path.join(monster_staging_dir, f"flat_{i}.obj")
            with open(flat_obj_path, "w", encoding="utf-8") as f:
                f.write(flat_mesh.export())
            print(f"  '{folder}': staged flat card mesh {i} -> {flat_obj_path}")
        if folder not in staged:
            staged.append(folder)
        os.makedirs(user_dir, exist_ok=True)
        if flat_texture is not None:
            flat_texture.image.save(os.path.join(user_dir, "flat_diffuse.png"))
            print(f"  '{folder}': saved flat card texture -> {user_dir}\\flat_diffuse.png")
        else:
            print(f"  '{folder}': NO flat card texture found - card will render untextured")

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
