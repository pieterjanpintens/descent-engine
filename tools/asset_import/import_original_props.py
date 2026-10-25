"""Stages the game's own prop models (chest, gate, tree, well, statue...) so the app can build a mesh library from them.

Same rule as the other import tools: this reads the game files on YOUR machine and writes only to the app's user
folder - nothing here is ever committed or shipped.

ORIGINAL_PROPS maps one of OUR mesh library item names to the game's prefab below assets/d3/terrain/ (or a (prefab, mesh name part) pair when one prefab holds several models) (several of
ours are matched to differently named game props, and the game has props we never made - those become new items).
For every prop it writes:
    <staging>/props/<our name>/mesh.obj   the model (surfaces "body" = textured, "edge" = the black card edge), UVs kept
    <staging>/props/<our name>/edge.obj   only when the game keeps the black edge in a separate mesh
    <user folder>/original_props/<our name>/diffuse.png   its texture
The prefab's other renderers - the "Outline" selection glow, shadow and reflection planes, the transparent copies the
game fades props with, the flame attachments - are skipped.

The app (OriginalPropsLibrary) then stands the models upright, scales them, fits them to our footprints, adds the
collision shapes and saves the finished mesh library to user://original_props/descent-meshes.res.

Usage (the app runs this itself, see asset_importer.py):
    python import_original_props.py <game bundles folder>
    (without DESCENT_STAGING_DIR the files are staged in models/original/prop_staging inside the project)
"""
import os
import shutil
import sys

import UnityPy
from UnityPy.export.MeshExporter import export_mesh_obj

from user_data import staging_dir, user_data_dir

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# our mesh library item name -> the game's prefab (below assets/d3/terrain/). Names we do not have yet are new items.
ORIGINAL_PROPS = {
    # ours, matched to a game prop
    "fence": "gate/gate.prefab",  # the game's "gate" is the see-through fence
    "gate": "door/door.prefab",
    "archway": "archway/archway.prefab",
    "tree": "tree/tree.prefab",
    "well": "well/well.prefab",
    "chest": "chest/chest.prefab",
    "cart": "wagon/wagon.prefab",
    "table": "stone table/stone table.prefab",
    "small-table": "round table/round table.prefab",
    "barricade": "spiked barricade/spiked barricade.prefab",
    "big-ladder": "ladder/medium/ladder_medium.prefab",
    "small-ladder": "ladder/short/ladder_short.prefab",
    "pot": "cauldron/terrain_cauldron.prefab",
    "stair": "staircase/staircase.prefab",
    "tall": "pillar/tall/pillar_tall.prefab",
    "medium": "pillar/medium/pillar.prefab",
    "mini": "pillar/short/pillar_short.prefab",
    # new props
    "altar": "altar/altar.prefab",
    "bell": "bell/bell.prefab",
    "bloodshrine": "bloodshrine/blood shrine.prefab",
    "bookshelf": "bookshelf/bookshelf.prefab",
    "dragonarch": "dragonarch/terrain_dragonarch.prefab",
    "dragonhead": "dragonhead/terrain_dragonhead.prefab",
    "fire": "fire/fire.prefab",
    # one prefab holds two statue models (Artboard_5.017 and Artboard_5.016): a (prefab, part of the mesh name) pair picks one
    "statue": ("statue/statue.prefab", "Artboard_5.017"),
    "statue2": ("statue/statue.prefab", "Artboard_5.016"),
    "bridge": "bridge/bridge.prefab",
}
TERRAIN = "assets/d3/terrain/"
# renderers of a prefab that are not the prop itself
SKIP_WORDS = ("transparent", "outline", "shadow", "reflection", "attachfire", "blackedge-transparent", "ground")


def prefab_renderers(env):
    """container path (lower case) -> [{"go": name, "mesh": Mesh, "materials": [(name, Texture2D or None)]}]"""
    filters = {}
    renderers = {}
    for obj in env.objects:
        if obj.type.name not in ("MeshFilter", "MeshRenderer"):
            continue
        container = (getattr(obj, "container", "") or "").lower()
        if not container.startswith(TERRAIN):
            continue
        data = obj.read()
        go_id = data.m_GameObject.path_id
        key = (container, go_id)
        if obj.type.name == "MeshFilter":
            filters[key] = data
        else:
            renderers[key] = data
    result = {}
    for key, filt in filters.items():
        renderer = renderers.get(key)
        if renderer is None:
            continue
        try:
            mesh = filt.m_Mesh.read()
            go_name = filt.m_GameObject.read().m_Name
        except Exception:
            continue
        materials = []
        for ptr in renderer.m_Materials:
            try:
                material = ptr.read()
            except Exception:
                materials.append(("?", None))
                continue
            texture = None
            for prop, tex_env in material.m_SavedProperties.m_TexEnvs:
                if prop == "_MainTex" and tex_env.m_Texture.path_id:
                    try:
                        texture = tex_env.m_Texture.read()
                    except Exception:
                        texture = None
                    break
            materials.append((material.m_Name, texture))
        result.setdefault(key[0], []).append({"go": go_name, "mesh": mesh, "materials": materials})
    return result


def usable(entry, allow_flame):
    words = [entry["go"].lower(), entry["mesh"].m_Name.lower()] + [name.lower() for name, _ in entry["materials"]]
    for word in SKIP_WORDS:
        if any(word in w for w in words):
            return False
    if not allow_flame and any("flame" in w for w in words):
        return False
    return True


def same_size(a, b):
    ea, eb = a.m_LocalAABB.m_Extent, b.m_LocalAABB.m_Extent
    return abs(ea.x - eb.x) < 0.03 and abs(ea.y - eb.y) < 0.03 and abs(ea.z - eb.z) < 0.03


def main():
    app_staging = staging_dir("props")
    staging = app_staging or os.path.join(PROJECT_DIR, "models", "original", "prop_staging")
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    bundles = sys.argv[1]
    print("Loading the game files...")
    env = UnityPy.load(bundles)
    print("Reading the prefabs...")
    index = prefab_renderers(env)

    if os.path.isdir(staging):
        shutil.rmtree(staging)
    os.makedirs(staging, exist_ok=True)
    staged = 0
    for name, prefab in ORIGINAL_PROPS.items():
        prefab, part = prefab if isinstance(prefab, tuple) else (prefab, "")
        entries = index.get((TERRAIN + prefab).lower(), [])
        entries = [e for e in entries if usable(e, "flame" in prefab) and part in e["mesh"].m_Name]
        body = next((e for e in entries if any(tex is not None for _, tex in e["materials"])), None)
        if body is None:
            print("  '%s': no textured mesh in %s - skipped" % (name, prefab))
            continue
        texture = next(tex for _, tex in body["materials"] if tex is not None)
        mesh = body["mesh"]
        submeshes = max(1, len(mesh.m_SubMeshes))
        names = []
        for i in range(submeshes):
            has_texture = i < len(body["materials"]) and body["materials"][i][1] is not None
            names.append("body" if has_texture else "edge")
        out_dir = os.path.join(staging, name)
        os.makedirs(out_dir, exist_ok=True)
        text = export_mesh_obj(mesh, material_names=names)
        if not text:
            print("  '%s': mesh export failed - skipped" % name)
            continue
        with open(os.path.join(out_dir, "mesh.obj"), "w", encoding="utf-8") as handle:
            handle.write(text)
        # a separate black-edge mesh of the same size (the game's .obj props keep it apart)
        edge_note = ""
        if "edge" not in names:
            edge = next((e for e in entries if e is not body and all(tex is None for _, tex in e["materials"]) and same_size(e["mesh"], mesh)), None)
            if edge is not None:
                edge_text = export_mesh_obj(edge["mesh"], material_names=["edge"] * max(1, len(edge["mesh"].m_SubMeshes)))
                if edge_text:
                    with open(os.path.join(out_dir, "edge.obj"), "w", encoding="utf-8") as handle:
                        handle.write(edge_text)
                    edge_note = " + separate edge mesh"
        tex_dir = user_data_dir("original_props", name)
        os.makedirs(tex_dir, exist_ok=True)
        texture.image.save(os.path.join(tex_dir, "diffuse.png"))
        staged += 1
        print("  '%s': staged %s (%d submeshes%s)" % (name, mesh.m_Name, submeshes, edge_note))
    print("Staged %d of %d props -> %s" % (staged, len(ORIGINAL_PROPS), staging))
    if staged == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
