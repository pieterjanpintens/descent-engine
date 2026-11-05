"""EXPERIMENT (2026-11-05): exports the rigged "flat" figures with their idle animation, in groups.

Replaces the one-figure import_flat_rig.py. For every target it writes `<mesh basename>_rig.json` beside the static mesh the app already has
(monsters: user://monster_assets/<folder>/flat_0_rig.json, heroes: user://hero_assets/<hero>/weapon_<0|1>_rig.json) plus the textures it needs
(`<mesh basename>_rig_<n>.png`). FlatRig (scripts/FlatRig.gd) plays them.

The figures are built from pieces: a SkinnedMeshRenderer (skeleton + vertex weights) or a plain MeshRenderer that sits on one transform of the
prefab. Both are exported as pieces of the prefab's transform hierarchy; a rigid piece is skinned to its own transform with weight 1.
  bones   [{name, parent, pos, rot, scl}]    the whole transform hierarchy under the Animator, parents first, local rest transforms
  pieces  [{host, skin_bones, bind, mesh, surfaces}]
            host = the piece's own transform (the app undoes its rest world transform so the rig matches the static mesh)
            skin_bones = bone index per skin slot, bind = 16 floats (row-major) per slot
            mesh = flat arrays (pos nrm uv bones weights), surfaces = [{indices, texture}] (one per submesh)
  anim    {name, length, fps, frames, tracks: {bone name: {index, pos, rot, scl}}}   sampled keyframes (30 fps)
Everything is mirrored along X like UnityPy's OBJ export, so the geometry lines up with the static meshes the app uses.

Usage: python import_flat_rigs.py <bundles folder> [<target> ...]   target = monster folder ("wolf") or "hero:<name>:<act index 0|1>"
With no target every figure is exported (the app's import step). With targets: at most 8 per run (run_flat_rigs.py runs everything in groups).
"""
import json
import math
import os
import re
import struct
import sys
import zlib

import UnityPy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import user_data  # noqa: E402

JUNK_MESH_WORDS = ["smoke", "particle", "glow", "bg", "background"]
JUNK_TEXTURE_WORDS = JUNK_MESH_WORDS + ["diamond", "rune", "lava", "circle"]
TEX_KEYS = ["_MainTex", "_Diffuse", "_BaseMap", "_BaseColorMap"]
ACTS = ["acti", "actii"]
FPS = 30


def f32(word):
    return struct.unpack("<f", struct.pack("<I", word & 0xFFFFFFFF))[0]


def mirror_pos(v):
    return [-v[0], v[1], v[2]]


def mirror_quat(q):
    return [q[0], -q[1], -q[2], q[3]]


def mirror_matrix(m):
    out = list(m)
    for r in range(4):
        for c in range(4):
            sign = 1.0
            if r == 0:
                sign = -sign
            if c == 0:
                sign = -sign
            out[r * 4 + c] = m[r * 4 + c] * sign
    return out


def matrix_floats(m):
    if hasattr(m, "e00"):
        return [getattr(m, "e%d%d" % (r, c)) for r in range(4) for c in range(4)]
    return [float(x) for x in m]


EULER_ORDER = "zyx"  # verified: with this order the clip's first frame reproduces the prefab rest pose exactly (rms 0.000); Quaternion.Euler order (yxz) did not
EULER_SCALE = 1.0    # degrees (1.0) - only changed by experiments


def euler_to_quat(x_deg, y_deg, z_deg):
    """Euler angles (degrees) -> (x, y, z, w). EULER_ORDER names the axes left to right of the quaternion product (Unity: "yxz")."""
    angles = {"x": math.radians(x_deg * EULER_SCALE) / 2, "y": math.radians(y_deg * EULER_SCALE) / 2, "z": math.radians(z_deg * EULER_SCALE) / 2}

    def axis_quat(axis):
        h = angles[axis]
        q = [0.0, 0.0, 0.0, math.cos(h)]
        q["xyz".index(axis)] = math.sin(h)
        return tuple(q)

    def mul(a, b):
        ax, ay, az, aw = a
        bx, by, bz, bw = b
        return (aw * bx + ax * bw + ay * bz - az * by,
                aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw,
                aw * bw - ax * bx - ay * by - az * bz)
    first, second, third = EULER_ORDER
    return mul(mul(axis_quat(first), axis_quat(second)), axis_quat(third))


def decode_streamed(words, curve_count):
    frames = []
    i = 0
    while i < len(words):
        time = f32(words[i])
        count = words[i + 1]
        i += 2
        keys = []
        for _ in range(count):
            keys.append((words[i], [f32(words[i + 1 + k]) for k in range(4)]))
            i += 5
        frames.append((time, keys))
    per_curve = [[] for _ in range(curve_count)]
    for time, keys in frames:
        for index, coeffs in keys:
            if index < curve_count:
                per_curve[index].append((time, coeffs))
    return per_curve


def sample_curve(keys, t):
    if not keys:
        return 0.0
    chosen = keys[0]
    for key in keys:
        if key[0] <= t + 1e-6:
            chosen = key
        else:
            break
    dt = max(t - chosen[0], 0.0)
    c = chosen[1]
    return ((c[0] * dt + c[1]) * dt + c[2]) * dt + c[3]


def components(game_object):
    for comp in game_object.m_Components:
        try:
            yield comp.read() if hasattr(comp, "read") else comp.component.read()
        except Exception:
            continue


def component_of(game_object, type_name):
    for obj in components(game_object):
        if obj.object_reader.type.name == type_name:
            return obj
    return None


def collect(env, container):
    """Every object of the types we need whose container is exactly `container` (lower case)."""
    found = {"SkinnedMeshRenderer": [], "MeshRenderer": [], "Animator": [], "AnimationClip": []}
    for obj in env.objects:
        name = obj.type.name
        if name not in found:
            continue
        if (obj.container or "").lower() != container:
            continue
        try:
            found[name].append(obj.read())
        except Exception:
            continue
    return found


def pick_clip(animator, loose_clips):
    clips = []
    try:
        controller = animator.m_Controller.read()
        for ref in controller.m_AnimationClips:
            try:
                clips.append(ref.read())
            except Exception:
                pass
    except Exception:
        pass
    if not clips:
        clips = loose_clips
    if not clips:
        return None, []
    idle = [c for c in clips if "idle" in c.m_Name.lower()]
    return (idle or clips)[0], [c.m_Name for c in clips]


def build_hierarchy(root_transform):
    bones = []
    by_path_id = {}
    path_hash_to_index = {}

    def walk(transform, parent_index, path):
        go = transform.m_GameObject.read()
        index = len(bones)
        by_path_id[transform.object_reader.path_id] = index
        bones.append({
            "name": go.m_Name,
            "parent": parent_index,
            "pos": mirror_pos([transform.m_LocalPosition.x, transform.m_LocalPosition.y, transform.m_LocalPosition.z]),
            "rot": mirror_quat([transform.m_LocalRotation.x, transform.m_LocalRotation.y, transform.m_LocalRotation.z, transform.m_LocalRotation.w]),
            "scl": [transform.m_LocalScale.x, transform.m_LocalScale.y, transform.m_LocalScale.z],
        })
        path_hash_to_index[zlib.crc32(path.encode())] = index
        for child in transform.m_Children:
            ct = child.read()
            child_name = ct.m_GameObject.read().m_Name
            walk(ct, index, (path + "/" + child_name) if path else child_name)

    walk(root_transform, -1, "")
    return bones, by_path_id, path_hash_to_index


def main_texture(material):
    try:
        envs = material.m_SavedProperties.m_TexEnvs
    except Exception:
        return None
    for key in TEX_KEYS:
        for tex_key, tex_env in envs:
            if tex_key == key and tex_env.m_Texture.path_id != 0:
                try:
                    return tex_env.m_Texture.read()
                except Exception:
                    return None
    return None


def export_piece(renderer, mesh, kind, by_path_id, texture_for, junk_check=True):
    """One piece (see the module docstring), or None when it should be left out."""
    from UnityPy.helpers.MeshHelper import MeshHandler
    host_t = component_of(renderer.m_GameObject.read(), "Transform")
    host = by_path_id.get(host_t.object_reader.path_id) if host_t is not None else None
    if host is None:
        return None
    handler = MeshHandler(mesh)
    handler.process()
    if not handler.m_Vertices:
        return None
    pos, nrm, uv = [], [], []
    for p in handler.m_Vertices:
        pos.extend(mirror_pos(p))
    for n in handler.m_Normals or []:
        nrm.extend(mirror_pos(n))
    for u in handler.m_UV0 or []:
        uv.extend([u[0], 1.0 - u[1]])
    vertex_count = len(handler.m_Vertices)
    if kind == "skinned":
        slots = [by_path_id[ref.read().object_reader.path_id] for ref in renderer.m_Bones]
        bind = []
        for m in mesh.m_BindPose:
            bind.extend(mirror_matrix(matrix_floats(m)))
        bones_arr, weights_arr = [], []
        per_vertex = None
        for idx, w in zip(handler.m_BoneIndices, handler.m_BoneWeights):
            bones_arr.extend(int(i) for i in idx)
            weights_arr.extend(float(x) for x in w)
        per_vertex = len(bones_arr) // max(vertex_count, 1)
    else:
        slots = [host]
        bind = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        bones_arr = [0] * vertex_count
        weights_arr = [1.0] * vertex_count
        per_vertex = 1
    surfaces = []
    materials = list(renderer.m_Materials)
    for i, triangles in enumerate(handler.get_triangles()):
        indices = []
        for a, b, c in triangles:
            indices.extend([c, b, a])
        texture = None
        if i < len(materials):
            try:
                texture = main_texture(materials[i].read())
            except Exception:
                texture = None
        if texture is not None and junk_check and any(w in texture.m_Name.lower() for w in JUNK_TEXTURE_WORDS):
            continue
        surfaces.append({"indices": indices, "texture": texture_for(texture)})
    if not surfaces:
        return None
    return {
        "host": host, "skin_bones": slots, "bind": bind, "per_vertex": per_vertex,
        "mesh": {"pos": pos, "nrm": nrm, "uv": uv, "bones": bones_arr, "weights": weights_arr},
        "surfaces": surfaces,
    }


def export_animation(clip, bones, path_hash_to_index):
    mc = clip.m_MuscleClip
    data = mc.m_Clip.data
    streamed_count = data.m_StreamedClip.curveCount
    dense = data.m_DenseClip
    constants = list(data.m_ConstantClip.data)
    bindings = clip.m_ClipBindingConstant.genericBindings
    length = float(mc.m_StopTime)
    per_curve = decode_streamed(list(data.m_StreamedClip.data), streamed_count)
    channels_for = {1: 3, 2: 4, 3: 3, 4: 3}
    channel = 0
    layout = []
    for b in bindings:
        n = channels_for.get(b.attribute, 1)
        layout.append((b, channel, n))
        channel += n
    if channel != streamed_count + dense.m_CurveCount + len(constants):
        raise RuntimeError("clip channel count mismatch: %d vs %d" % (channel, streamed_count + dense.m_CurveCount + len(constants)))
    if dense.m_CurveCount:
        print("    note: clip has %d dense curves (treated as 0)" % dense.m_CurveCount)
    frame_count = max(int(round(length * FPS)) + 1, 2)
    tracks = {}
    skipped_euler = 0
    for b, first, n in layout:
        if b.typeID != 4:
            continue
        if b.attribute not in (1, 2, 3, 4):
            continue
        index = path_hash_to_index.get(b.path)
        if index is None:
            continue
        flat = []
        for f in range(frame_count):
            t = min(f / FPS, length)
            row = []
            for k in range(n):
                c = first + k
                if c < streamed_count:
                    row.append(sample_curve(per_curve[c], t))
                elif c < streamed_count + dense.m_CurveCount:
                    row.append(0.0)
                else:
                    row.append(constants[c - streamed_count - dense.m_CurveCount])
            if b.attribute == 1:
                row = mirror_pos(row)
            elif b.attribute == 2:
                q = sum(x * x for x in row) ** 0.5 or 1.0
                row = mirror_quat([x / q for x in row])
            elif b.attribute == 4:
                row = mirror_quat(list(euler_to_quat(row[0], row[1], row[2])))
            flat.extend(row)
        track = tracks.setdefault(bones[index]["name"] + "#%d" % index, {"index": index})
        track[{1: "pos", 2: "rot", 3: "scl", 4: "rot"}[b.attribute]] = flat
    if skipped_euler:
        print("    note: %d euler rotation bindings skipped" % skipped_euler)
    return {"name": clip.m_Name, "length": length, "fps": FPS, "frames": frame_count, "tracks": tracks}


def export_target(env, target, existing_pieces=None):
    """Returns (output basename path without extension, report string)."""
    if target.startswith("hero:"):
        _, hero, act_index = target.split(":")
        act = ACTS[int(act_index)]
        container = ("assets/d3/heroes/%s/%s/prefabs/%s.prefab" % (hero, act, hero)).lower()
        out_dir = user_data.user_data_dir("hero_assets", hero)
        base = os.path.join(out_dir, "weapon_%s" % act_index)
    else:
        container = ("assets/d3/enemies/%s/prefabs/%s flat.prefab" % (target, target.replace("_", " "))).lower()
        out_dir = user_data.user_data_dir("monster_assets", target)
        base = os.path.join(out_dir, "flat_0")
    found = collect(env, container)
    skinned, rigid, animators, loose_clips = found["SkinnedMeshRenderer"], found["MeshRenderer"], found["Animator"], found["AnimationClip"]
    if not animators:
        raise RuntimeError("no Animator in " + container)
    animator = animators[0]
    clip, clip_names = pick_clip(animator, loose_clips)
    if clip is None:
        raise RuntimeError("no animation clip")
    root_go = animator.m_GameObject.read()
    root_t = component_of(root_go, "Transform")
    bones, by_path_id, path_hash_to_index = build_hierarchy(root_t)

    os.makedirs(out_dir, exist_ok=True)
    texture_files = []
    texture_ids = {}

    def texture_for(texture):
        if texture is None:
            return -1
        key = texture.object_reader.path_id
        if key not in texture_ids:
            name = "%s_rig_%d.png" % (os.path.basename(base), len(texture_files))
            texture.image.save(os.path.join(out_dir, name))
            texture_ids[key] = len(texture_files)
            texture_files.append(name)
        return texture_ids[key]

    pieces = []
    candidates = []
    for renderer in skinned:
        candidates.append((renderer, "skinned"))
    for renderer in rigid:
        candidates.append((renderer, "rigid"))
    if target.startswith("hero:") and skinned:
        # the hero's own body, not a companion creature's: the renderer whose mesh is named after the hero (see import_hero_meshes.py)
        import import_hero_meshes as heroes
        wanted = heroes.HERO_BODY_MESH_NAME_OVERRIDES.get((hero, act), hero)
        named = [c for c in candidates if c[1] == "skinned" and c[0].m_Mesh.read().m_Name.lower() == wanted]
        if named:
            candidates = named
        else:
            candidates = [max((c for c in candidates if c[1] == "skinned"), key=lambda c: len(c[0].m_Bones))]
            print("    note: no mesh named '%s', using the renderer with the most bones" % wanted)
    for renderer, kind in candidates:
        try:
            if kind == "skinned":
                mesh = renderer.m_Mesh.read()
            else:
                mesh_filter = component_of(renderer.m_GameObject.read(), "MeshFilter")
                if mesh_filter is None:
                    continue
                mesh = mesh_filter.m_Mesh.read()
        except Exception:
            continue
        if any(w in mesh.m_Name.lower() for w in JUNK_MESH_WORDS):
            continue
        piece = export_piece(renderer, mesh, kind, by_path_id, texture_for, junk_check=not target.startswith("hero:"))
        if piece is not None:
            pieces.append(piece)
    if not pieces:
        raise RuntimeError("no usable mesh piece")
    anim = export_animation(clip, bones, path_hash_to_index)
    result = {"bones": bones, "pieces": pieces, "textures": texture_files, "anim": anim}
    path = base + "_rig.json"
    with open(path, "w") as handle:
        json.dump(result, handle)
    kinds = sorted({"rigid" if len(p["skin_bones"]) == 1 and p["per_vertex"] == 1 else "skinned" for p in pieces})
    note = "clip '%s' (of %s), %d bones, %d pieces (%s), %d animated bones, %d KB" % (
        clip.m_Name, clip_names, len(bones), len(pieces), ",".join(kinds), len(anim["tracks"]), os.path.getsize(path) // 1024)
    return path, note


def all_targets():
    """Every monster and hero figure the app knows: from the app's manifest, or from the project's own scripts when run from the project."""
    here = os.path.dirname(os.path.abspath(__file__))
    scripts = os.path.join(os.path.dirname(os.path.dirname(here)), "scripts")
    monsters = user_data.manifest_list("monster_folders")
    if monsters is None:
        text = open(os.path.join(scripts, "MonsterDisplay.gd"), encoding="utf-8").read()
        block = re.search(r"const REAL_MONSTERS := \[(.*?)\n\]", text, re.DOTALL).group(1)
        monsters = re.findall(r'"folder"\s*:\s*"([^"]+)"', block)
    heroes = user_data.manifest_list("hero_names")
    if heroes is None:
        text = open(os.path.join(scripts, "HeroCatalog.gd"), encoding="utf-8").read()
        heroes = re.findall(r'"([^"]+)"', re.search(r"const HERO_NAMES[^=]*=\s*\[(.*?)\]", text, re.DOTALL).group(1))
    found = list(monsters)
    for hero in heroes:
        for act in (0, 1):
            found.append("hero:%s:%d" % (hero.lower(), act))
    return found


def main():
    bundles = sys.argv[1]
    targets = sys.argv[2:]
    if len(targets) > 8:
        sys.exit("At most 8 targets per run (got %d)" % len(targets))
    explicit = bool(targets)
    if not explicit:
        targets = all_targets()  # the import step: everything, with the bundles loaded once
    print("Loading bundles (this can take a while)...", flush=True)
    env = UnityPy.load(bundles)
    failed = 0
    for target in targets:
        try:
            path, note = export_target(env, target)
            print("OK   %-22s %s" % (target, note), flush=True)
        except Exception as error:  # one figure failing must not stop the others
            failed += 1
            print("FAIL %-22s %s: %s" % (target, type(error).__name__, error), flush=True)
    return 1 if failed == len(targets) else 0


if __name__ == "__main__":
    sys.exit(main())
