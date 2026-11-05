"""EXPERIMENT (2026-11-05): exports ONE figure's rigged "flat" model with its idle animation, so the game can play the idle loop.

The flat monster / hero figures are skinned meshes (a bone skeleton + vertex weights) and the game ships an idle AnimationClip for each. The normal
import (import_monster_meshes.py) only keeps the static mesh. This tool writes, for one monster folder, `flat_rig.json`:

  bones     [{name, parent, pos, rot, scl}]   the whole transform hierarchy of the prefab, parents first, LOCAL rest transforms
  skin      {bones: [bone index per skin slot], bind: [16 floats per slot]}   the mesh's bind poses (mesh space -> bone space)
  mesh      {pos, nrm, uv, bones, weights, indices}   flat arrays, 4 bone slots per vertex
  anim      {name, length, fps, tracks: {bone name: {pos: [..], rot: [..], scl: [..]}}}   sampled keyframes

Everything is mirrored along X (x -> -x) - the same conversion UnityPy's OBJ exporter applies, so the geometry lines up with the static
meshes the app already uses - and triangles are written with reversed winding, as the OBJ exporter does. The texture is the diffuse the
normal import already saved.

Usage: python import_flat_rig.py <bundles folder> <monster folder, e.g. wolf> <output folder>
"""
import json
import os
import struct
import sys
import zlib

import UnityPy


def f32(word):
    return struct.unpack("<f", struct.pack("<I", word & 0xFFFFFFFF))[0]


def mirror_pos(v):
    return [-v[0], v[1], v[2]]


def mirror_quat(q):
    return [q[0], -q[1], -q[2], q[3]]


def mirror_matrix(m):
    """M * m * M with M = diag(-1, 1, 1, 1); m is 16 floats, row-major (e00 e01 ...)."""
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
    """UnityPy gives a bind pose as an object with e00..e33 (or a plain sequence)."""
    if hasattr(m, "e00"):
        return [getattr(m, "e%d%d" % (r, c)) for r in range(4) for c in range(4)]
    return [float(x) for x in m]


def decode_streamed(words, curve_count):
    """The streamed part of a compiled clip: frames of (time, [(curve index, 4 cubic coefficients)])."""
    frames = []
    i = 0
    while i < len(words):
        time = f32(words[i])
        count = words[i + 1]
        i += 2
        keys = []
        for _ in range(count):
            index = words[i]
            keys.append((index, [f32(words[i + 1 + k]) for k in range(4)]))
            i += 5
        frames.append((time, keys))
    per_curve = [[] for _ in range(curve_count)]
    for time, keys in frames:
        for index, coeffs in keys:
            if index < curve_count:
                per_curve[index].append((time, coeffs))
    return per_curve


def sample_curve(keys, t):
    """Cubic segment of the latest key at or before t (coefficients x t^3 + y t^2 + z t + w, t relative to the key)."""
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


def main():
    bundles, folder, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    needle = "enemies/%s/prefabs/%s flat.prefab" % (folder, folder.replace("_", " "))
    print("Loading bundles (this can take a while)...")
    env = UnityPy.load(bundles)
    smr = animator = clip = None
    clips = []
    for obj in env.objects:
        t = obj.type.name
        if t not in ("SkinnedMeshRenderer", "Animator", "AnimationClip"):
            continue
        cont = (obj.container or "").lower()
        if needle not in cont:
            continue
        if t == "SkinnedMeshRenderer" and smr is None:
            smr = obj.read()
        elif t == "Animator" and animator is None:
            animator = obj.read()
        elif t == "AnimationClip":
            clips.append(obj.read())
    if smr is None or animator is None or not clips:
        sys.exit("Nothing found for " + needle)
    clip = next((c for c in clips if "idle" in c.m_Name.lower()), clips[0])
    print("clips:", [c.m_Name for c in clips], "-> using", clip.m_Name)

    # ---- the transform hierarchy under the animator's object
    root_go = animator.m_GameObject.read()
    root_t = None
    for comp in root_go.m_Components:
        obj = comp.read() if hasattr(comp, "read") else comp.component.read()
        if obj.object_reader.type.name == "Transform":
            root_t = obj
            break
    bones = []
    by_path_id = {}
    path_hash_to_index = {0: None}

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

    walk(root_t, -1, "")
    print("transforms:", len(bones))

    # ---- skin: which transform each skin slot is, and the bind poses
    mesh = smr.m_Mesh.read()
    slot_bones = []
    for ref in smr.m_Bones:
        slot_bones.append(by_path_id[ref.read().object_reader.path_id])
    from UnityPy.helpers.MeshHelper import MeshHandler
    handler = MeshHandler(mesh)
    handler.process()
    bind = []
    for m in mesh.m_BindPose:
        bind.extend(mirror_matrix(matrix_floats(m)))
    print("vertices:", handler.m_VertexCount, "skin slots:", len(slot_bones), "bind poses:", len(mesh.m_BindPose))

    pos, nrm, uv = [], [], []
    for p in handler.m_Vertices:
        pos.extend(mirror_pos(p))
    for n in handler.m_Normals or []:
        nrm.extend(mirror_pos(n))
    for u in handler.m_UV0 or []:
        uv.extend([u[0], 1.0 - u[1]])
    skin_bones, skin_weights = [], []
    for idx, w in zip(handler.m_BoneIndices, handler.m_BoneWeights):
        skin_bones.extend(int(i) for i in idx)
        skin_weights.extend(float(x) for x in w)
    indices = []
    for triangles in handler.get_triangles():
        for a, b, c in triangles:
            indices.extend([c, b, a])
    print("triangles:", len(indices) // 3)

    # ---- the animation
    mc = clip.m_MuscleClip
    data = mc.m_Clip.data
    streamed_words = list(data.m_StreamedClip.data)
    streamed_count = data.m_StreamedClip.curveCount
    dense = data.m_DenseClip
    constants = list(data.m_ConstantClip.data)
    bindings = clip.m_ClipBindingConstant.genericBindings
    length = float(mc.m_StopTime)
    per_curve = decode_streamed(streamed_words, streamed_count)
    print("streamed curves:", streamed_count, "dense:", dense.m_CurveCount, "constant:", len(constants), "bindings:", len(bindings), "length:", length)
    print("first frame times:", sorted({k[0] for c in per_curve for k in c})[:5], "...")
    channels_for = {1: 3, 2: 4, 3: 3, 4: 3}
    channel = 0
    layout = []
    for b in bindings:
        n = channels_for.get(b.attribute, 1)
        layout.append((b, channel, n))
        channel += n
    print("total channels:", channel, "streamed+dense+const:", streamed_count + dense.m_CurveCount + len(constants))

    fps = 30
    frame_count = int(round(length * fps)) + 1
    tracks = {}
    for b, first, n in layout:
        if b.typeID != 4 or b.attribute not in (1, 2, 3):
            continue
        index = path_hash_to_index.get(b.path)
        if index is None:
            continue
        values = []
        for f in range(frame_count):
            t = min(f / fps, length)
            row = []
            for k in range(n):
                c = first + k
                if c < streamed_count:
                    row.append(sample_curve(per_curve[c], t))
                elif c < streamed_count + dense.m_CurveCount:
                    row.append(0.0)  # dense curves are not used by this clip (checked: 0 of them)
                else:
                    row.append(constants[c - streamed_count - dense.m_CurveCount])
            values.append(row)
        name = bones[index]["name"]
        track = tracks.setdefault(name, {"index": index})
        key = {1: "pos", 2: "rot", 3: "scl"}[b.attribute]
        flat = []
        for row in values:
            if b.attribute == 1:
                row = mirror_pos(row)
            elif b.attribute == 2:
                length_q = sum(x * x for x in row) ** 0.5 or 1.0
                row = mirror_quat([x / length_q for x in row])
            flat.extend(row)
        track[key] = flat
    print("animated bones:", len(tracks))

    os.makedirs(out_dir, exist_ok=True)
    result = {
        "bones": bones,
        "skin": {"bones": slot_bones, "bind": bind},
        "mesh": {"pos": pos, "nrm": nrm, "uv": uv, "bones": skin_bones, "weights": skin_weights, "indices": indices},
        "anim": {"name": clip.m_Name, "length": length, "fps": fps, "frames": frame_count, "tracks": tracks},
    }
    path = os.path.join(out_dir, "flat_rig.json")
    with open(path, "w") as handle:
        json.dump(result, handle)
    print("wrote", path, os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    main()
