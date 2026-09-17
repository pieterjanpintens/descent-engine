"""Dumps EVERY asset from the official "Descent: Legends of the Dark"
companion app's Unity bundles into a local-only folder, for manually
browsing/searching - a much broader companion to import_official_assets.py's
narrow, name-matched texture import (that one only ever pulls the handful of
textures OfficialAssetMap.gd already knows the exact names of; this one is
for exploring what's actually IN the bundles, e.g. to find monster meshes,
before anything has a name mapped for it yet).

Same rule as import_official_assets.py: this reads Unity AssetBundle files
that already exist on YOUR OWN machine, from YOUR OWN legally-purchased game
install. Nothing here ships, gets committed, or gets bundled into an export -
everything is written to a folder outside the git repo entirely (see
OUTPUT_DIR below), same as that script's OVERRIDE_DIR.

Requires: pip install UnityPy (same dependency as import_official_assets.py)

Usage:
    python dump_all_assets.py <path to game's StreamingAssets/bundles folder> [output_dir]

Writes, under output_dir (default: OUTPUT_DIR below):
    manifest.tsv     - one line per object: type, name, container path (if
                        any), source bundle file - the actual "so we can
                        check" list. grep this for likely monster names/
                        folders before digging into meshes/ one file at a
                        time.
    meshes/*.obj      - every Mesh object, exported via UnityPy's own built-in
                        OBJ exporter (Mesh.export() -> str of OBJ text -
                        confirmed against the actually-installed UnityPy
                        1.25.3 here, not assumed).
    textures/*.png    - every Texture2D/Sprite, same .image.save() pattern
                        import_official_assets.py already uses - lets you
                        cross-reference a mesh against its material's texture
                        name (e.g. "GoblinArcher_Diffuse") when the mesh's own
                        internal name is just "Mesh_00234" and tells you
                        nothing on its own.

Names collide across many different monster/prop meshes sharing generic
Unity-internal names (e.g. multiple "Mesh"/"Cylinder") - every exported
filename is prefixed with the object's path_id to guarantee uniqueness
rather than silently overwriting same-named files.
"""
import sys
import os
import UnityPy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\asset_dump")

# Every object type worth trying to export outright - anything else just
# gets a manifest line (name + container path), which is usually enough to
# tell whether it's worth coming back for.
MESH_TYPES = {"Mesh"}
TEXTURE_TYPES = {"Texture2D", "Sprite"}


def safe_name(obj, data) -> str:
    name = getattr(data, "m_Name", "") if data is not None else ""
    if not name:
        try:
            name = obj.peek_name()
        except Exception:
            name = ""
    return name or "unnamed"


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        sys.exit(1)
    bundles_dir = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) == 3 else OUTPUT_DIR

    mesh_dir = os.path.join(output_dir, "meshes")
    texture_dir = os.path.join(output_dir, "textures")
    os.makedirs(mesh_dir, exist_ok=True)
    os.makedirs(texture_dir, exist_ok=True)
    manifest_path = os.path.join(output_dir, "manifest.tsv")

    print("Loading bundles folder (this can take a while for a full game)...")
    env = UnityPy.load(bundles_dir)

    total = 0
    mesh_count = 0
    texture_count = 0
    type_counts: dict[str, int] = {}

    with open(manifest_path, "w", encoding="utf-8") as manifest:
        manifest.write("type\tname\tcontainer\tpath_id\n")
        for obj in env.objects:
            total += 1
            type_name = obj.type.name
            type_counts[type_name] = type_counts.get(type_name, 0) + 1

            data = None
            if type_name in MESH_TYPES or type_name in TEXTURE_TYPES:
                try:
                    data = obj.read()
                except Exception:
                    data = None

            name = safe_name(obj, data)
            container = getattr(obj, "container", "") or ""
            manifest.write(f"{type_name}\t{name}\t{container}\t{obj.path_id}\n")

            if type_name in MESH_TYPES and data is not None:
                try:
                    obj_text = data.export()
                    out_path = os.path.join(mesh_dir, f"{obj.path_id}_{name}.obj")
                    with open(out_path, "w", encoding="utf-8") as f:
                        f.write(obj_text)
                    mesh_count += 1
                except Exception as e:
                    print(f"  mesh export failed for '{name}' ({obj.path_id}): {e}")

            elif type_name in TEXTURE_TYPES and data is not None:
                try:
                    image = data.image
                    out_path = os.path.join(texture_dir, f"{obj.path_id}_{name}.png")
                    image.save(out_path)
                    texture_count += 1
                except Exception as e:
                    print(f"  texture export failed for '{name}' ({obj.path_id}): {e}")

            if total % 2000 == 0:
                print(f"  ...{total} objects scanned so far")

    print(f"\nScanned {total} objects.")
    print("Breakdown by type:")
    for type_name, count in sorted(type_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {count:6d}  {type_name}")
    print(f"\nExported {mesh_count} mesh(es) to {mesh_dir}")
    print(f"Exported {texture_count} texture(s) to {texture_dir}")
    print(f"Full manifest (every object, all types) written to {manifest_path}")
    print("\nNothing here is committed or read by the Godot project - purely")
    print("for local browsing. Search manifest.tsv for likely monster names")
    print("(e.g. by folder/container path) before digging through meshes/.")


if __name__ == "__main__":
    main()
