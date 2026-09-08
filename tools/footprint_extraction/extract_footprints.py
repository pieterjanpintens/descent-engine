#!/usr/bin/env python3
"""Derives FootprintRegistry.FOOTPRINTS entries directly from tile-face mesh
geometry in models/floors.glb, instead of hand-typing ASCII art.

Why this works for this project specifically: floors.glb has one named node
per tile face ("1a", "3b", "18a", ...) matching FootprintRegistry's keys
exactly, each sitting at its own local origin with NO transform (translation/
rotation/scale all identity) - so raw vertex positions are already in the
pivot-relative space FootprintRegistry expects. Calibrated and verified
against every tile already hand-authored in FootprintRegistry.gd (1a/1b,
2a/2b, 3a/3b, 4a/4b, 5a/5b, 7a/7b, 18a/18b) before trusting it on new tiles -
see main() below, which refuses to print anything if any known tile mismatches.

No third-party deps (pygltflib/trimesh aren't installed in this environment) -
parses the glTF/GLB container by hand. Good enough for this one-shot use;
not meant as a general glTF library.
"""
import json
import re
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GLB_PATH = REPO_ROOT / "models" / "floors.glb"

# Calibrated from mesh AABBs vs. already-authored FOOTPRINTS entries (see
# module docstring): 1 tile-square = 3.2 world units in floors.glb.
TILE_SQUARE_SIZE = 3.2

# Ground truth to calibrate/validate against - copied from FootprintRegistry.gd's
# FOOTPRINTS dict (the RAW, pre-_apply_pivot_correction() form, exactly as
# authored there).
KNOWN_FOOTPRINTS = {
    "1a": [(-2, -1), (-1, -1), (0, -1), (-2, 0), (-1, 0), (0, 0)],
    "1b": [(-2, -1), (-1, -1), (0, -1), (-2, 0), (-1, 0), (0, 0)],
    "2a": [(-2, -1), (-1, -1), (0, -1), (-2, 0), (-1, 0), (0, 0)],
    "2b": [(-2, -1), (-1, -1), (0, -1), (-2, 0), (-1, 0), (0, 0)],
    "3a": [(-3, -2), (-2, -2), (-3, -1), (-2, -1), (-1, -1), (0, -1), (-3, 0), (-2, 0), (-1, 0), (0, 0)],
    "3b": [(2, -2), (3, -2), (0, -1), (1, -1), (2, -1), (3, -1), (0, 0), (1, 0), (2, 0), (3, 0)],
    "4a": [(0, -3), (1, -3), (0, -2), (1, -2), (0, -1), (1, -1), (2, -1), (3, -1), (0, 0), (1, 0), (2, 0), (3, 0)],
    "4b": [(-1, -3), (0, -3), (-1, -2), (0, -2), (-3, -1), (-2, -1), (-1, -1), (0, -1), (-3, 0), (-2, 0), (-1, 0), (0, 0)],
    "5a": [(0, -3), (1, -3), (0, -2), (1, -2), (0, -1), (1, -1), (2, -1), (3, -1), (0, 0), (1, 0), (2, 0), (3, 0)],
    "5b": [(-1, -3), (0, -3), (-1, -2), (0, -2), (-3, -1), (-2, -1), (-1, -1), (0, -1), (-3, 0), (-2, 0), (-1, 0), (0, 0)],
    "7a": [(-3, -2), (-2, -2), (-5, -1), (-4, -1), (-3, -1), (-2, -1), (-1, -1), (0, -1),
           (-5, 0), (-4, 0), (-3, 0), (-2, 0), (-1, 0), (0, 0), (-3, 1), (-2, 1)],
    "7b": [(-3, -2), (-2, -2), (-5, -1), (-4, -1), (-3, -1), (-2, -1), (-1, -1), (0, -1),
           (-5, 0), (-4, 0), (-3, 0), (-2, 0), (-1, 0), (0, 0), (-3, 1), (-2, 1)],
    "18a": [
        (-2, -6), (-1, -6),
        (-3, -5), (-2, -5), (-1, -5), (0, -5),
        (-4, -4), (-3, -4), (-2, -4), (-1, -4), (0, -4), (1, -4),
        (-4, -3), (-3, -3), (-2, -3), (-1, -3), (0, -3), (1, -3), (2, -3),
        (-4, -2), (-3, -2), (-2, -2), (-1, -2), (0, -2), (1, -2), (2, -2),
        (-4, -1), (-3, -1), (-2, -1), (-1, -1), (0, -1), (1, -1),
        (-3, 0), (-2, 0), (-1, 0), (0, 0),
    ],
    "18b": [
        (-2, -6), (-1, -6),
        (-3, -5), (-2, -5), (-1, -5), (0, -5),
        (-4, -4), (-3, -4), (-2, -4), (-1, -4), (0, -4), (1, -4),
        (-5, -3), (-4, -3), (-3, -3), (-2, -3), (-1, -3), (0, -3), (1, -3),
        (-5, -2), (-4, -2), (-3, -2), (-2, -2), (-1, -2), (0, -2), (1, -2),
        (-4, -1), (-3, -1), (-2, -1), (-1, -1), (0, -1), (1, -1),
        (-3, 0), (-2, 0), (-1, 0), (0, 0),
    ],
}

# Names present in floors.glb that are NOT tile faces (a prop merged into the
# same export by accident, per the user) - skipped entirely, never treated
# as floor tile data.
IGNORED_NODE_NAMES = {"bridge.001", "stair.001"}

TILE_FACE_RE = re.compile(r"^\d+[ab]$")


def load_glb(path: Path) -> dict:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a glb file")
    offset = 12
    json_chunk = None
    bin_chunk = None
    while offset < len(data):
        chunk_len, chunk_type = struct.unpack_from("<I4s", data, offset)
        chunk_data = data[offset + 8: offset + 8 + chunk_len]
        if chunk_type == b"JSON":
            json_chunk = chunk_data
        elif chunk_type == b"BIN\x00":
            bin_chunk = chunk_data
        offset += 8 + chunk_len
    gltf = json.loads(json_chunk)
    return gltf, bin_chunk


COMPONENT_TYPES = {
    5121: ("B", 1),   # unsigned byte
    5123: ("H", 2),   # unsigned short
    5125: ("I", 4),   # unsigned int
    5126: ("f", 4),   # float
}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(gltf: dict, bin_chunk: bytes, accessor_idx: int) -> list:
    acc = gltf["accessors"][accessor_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    fmt_char, comp_size = COMPONENT_TYPES[acc["componentType"]]
    n_comp = TYPE_COUNTS[acc["type"]]
    count = acc["count"]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", n_comp * comp_size)
    values = []
    for i in range(count):
        base = start + i * stride
        vals = struct.unpack_from("<" + fmt_char * n_comp, bin_chunk, base)
        values.append(vals if n_comp > 1 else vals[0])
    return values


def get_triangles(gltf: dict, bin_chunk: bytes, mesh_idx: int) -> list:
    """Returns a list of ((x0,z0),(x1,z1),(x2,z2)) triangles, XZ-projected,
    for every primitive in the mesh (Y/up is dropped - floor tiles are flat)."""
    mesh = gltf["meshes"][mesh_idx]
    triangles = []
    for prim in mesh["primitives"]:
        positions = read_accessor(gltf, bin_chunk, prim["attributes"]["POSITION"])
        xz = [(p[0], p[2]) for p in positions]
        if "indices" in prim:
            indices = read_accessor(gltf, bin_chunk, prim["indices"])
        else:
            indices = list(range(len(positions)))
        for i in range(0, len(indices) - 2, 3):
            a, b, c = indices[i], indices[i + 1], indices[i + 2]
            triangles.append((xz[a], xz[b], xz[c]))
    return triangles


def point_in_triangle(p, a, b, c) -> bool:
    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

    d1 = sign(p, a, b)
    d2 = sign(p, b, c)
    d3 = sign(p, c, a)
    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)


def point_in_mesh(point, triangles) -> bool:
    return any(point_in_triangle(point, a, b, c) for a, b, c in triangles)


def derive_footprint(triangles: list) -> list:
    """Returns the FINAL, geometrically-correct tile-square offsets (as if
    _apply_pivot_correction() had already been applied) for one mesh's
    triangles, by sampling each candidate tile-square cell's center point
    against the mesh's XZ footprint. See module docstring for the offset<->
    world-space mapping (calibrated/verified against known tiles)."""
    all_x = [v[0] for tri in triangles for v in tri]
    all_z = [v[1] for tri in triangles for v in tri]
    i_min = int(min(all_x) // TILE_SQUARE_SIZE) - 1
    i_max = int(max(all_x) // TILE_SQUARE_SIZE) + 1
    j_min = int(min(all_z) // TILE_SQUARE_SIZE) - 1
    j_max = int(max(all_z) // TILE_SQUARE_SIZE) + 1

    offsets = []
    for i in range(i_min, i_max + 1):
        for j in range(j_min, j_max + 1):
            cx = (i + 0.5) * TILE_SQUARE_SIZE
            cz = (j + 0.5) * TILE_SQUARE_SIZE
            if point_in_mesh((cx, cz), triangles):
                offsets.append((i + 1, j + 1))
    return offsets


def pivot_correction_needed(offsets: list) -> tuple:
    """Mirrors FootprintRegistry._apply_pivot_correction()'s detection
    heuristic exactly (see FootprintRegistry.gd), applied here to FINAL
    (already-correct) offsets to figure out what correction the runtime code
    would apply if these were stored as-is - so we can pre-subtract it and
    keep FOOTPRINTS in the same "pre-correction" form the existing hand-
    authored entries use (3b/4a/5a already rely on this mechanism)."""
    needs_x = any(z == 0 and x > 0 for x, z in offsets)
    needs_z = any(x == 0 and z > 0 for x, z in offsets)
    return (1 if needs_x else 0, 1 if needs_z else 0)


def pivot_is_valid(final_offsets: list) -> bool:
    """Checks the actual invariant FootprintRegistry's whole rotate/expand
    pipeline depends on (see the "Hard-won lessons" pivot-correction note in
    CLAUDE.md): along the origin's OWN row (z=0) and OWN column (x=0), cells
    must extend in only ONE direction, never both - not a bounding-box-corner
    check, since e.g. tile 7's cross shape legitimately bulges past the
    origin's row/column elsewhere in the piece. If this doesn't hold, no
    +1 correction can fix it - the mesh's Blender pivot itself needs moving."""
    own_row_x = [x for x, z in final_offsets if z == 0]
    own_col_z = [z for x, z in final_offsets if x == 0]
    row_ok = not (any(x > 0 for x in own_row_x) and any(x < 0 for x in own_row_x))
    col_ok = not (any(z > 0 for z in own_col_z) and any(z < 0 for z in own_col_z))
    return row_ok and col_ok


def to_raw_footprint(final_offsets: list) -> list:
    """Final (correct) offsets -> raw FOOTPRINTS storage form, i.e. the
    inverse of get_tile_square_footprint()'s _apply_pivot_correction() step."""
    if len(final_offsets) <= 1:
        return sorted(final_offsets)
    cx, cz = pivot_correction_needed(final_offsets)
    return sorted((x - cx, z - cz) for x, z in final_offsets)


def format_footprint_gdscript(name: str, offsets: list) -> str:
    cells = ", ".join(f"Vector3i({x}, 0, {z})" for x, z in offsets)
    return f'\t"{name}": [{cells}],'


def render_ascii(final_offsets: list) -> str:
    """Human-readable grid of a mesh's FINAL (already-correct) footprint, in
    the same top-down x/z-as-rows/cols style the user hand-authors tiles in -
    for eyeballing that a/b faces are proper mirror images etc. before
    trusting the extracted data. 'y' marks (0,0) - the mesh's own pivot."""
    xs = [x for x, _ in final_offsets]
    zs = [z for _, z in final_offsets]
    filled = set(final_offsets)
    lines = []
    for z in range(min(zs), max(zs) + 1):
        row = []
        for x in range(min(xs), max(xs) + 1):
            if (x, z) == (0, 0):
                row.append("y")
            elif (x, z) in filled:
                row.append("x")
            else:
                row.append(".")
        lines.append("".join(row))
    return "\n".join(lines)


def main() -> int:
    if not GLB_PATH.exists():
        print(f"error: {GLB_PATH} not found", file=sys.stderr)
        return 1

    gltf, bin_chunk = load_glb(GLB_PATH)
    nodes = gltf["nodes"]

    name_to_mesh_idx = {}
    for node in nodes:
        name = node.get("name")
        if name is None or "mesh" not in node:
            continue
        name_to_mesh_idx[name] = node["mesh"]

    # --- Calibration check: re-derive every already-authored tile and
    # refuse to print anything for new tiles unless every known one matches
    # EXACTLY (order-independent). This is the whole reason this script can
    # be trusted at all - see module docstring.
    mismatches = []
    for name, expected in KNOWN_FOOTPRINTS.items():
        if name not in name_to_mesh_idx:
            mismatches.append((name, "missing from floors.glb", None))
            continue
        triangles = get_triangles(gltf, bin_chunk, name_to_mesh_idx[name])
        final_offsets = derive_footprint(triangles)
        raw = to_raw_footprint(final_offsets)
        if raw != sorted(expected):
            mismatches.append((name, raw, sorted(expected)))

    if mismatches:
        print("CALIBRATION FAILED - not trusting extraction for new tiles.", file=sys.stderr)
        for name, got, expected in mismatches:
            print(f"  {name}: got={got} expected={expected}", file=sys.stderr)
        return 1

    print(f"Calibration OK - all {len(KNOWN_FOOTPRINTS)} known tiles matched exactly.\n", file=sys.stderr)

    # --- Extract every tile-face node NOT already in KNOWN_FOOTPRINTS and
    # not explicitly ignored.
    new_names = []
    skipped = []
    for name in name_to_mesh_idx:
        if name in KNOWN_FOOTPRINTS:
            continue
        if name in IGNORED_NODE_NAMES:
            skipped.append(name)
            continue
        if not TILE_FACE_RE.match(name):
            skipped.append(name)
            continue
        new_names.append(name)

    def natural_key(n: str):
        m = re.match(r"^(\d+)([ab])$", n)
        return (int(m.group(1)), m.group(2))

    new_names.sort(key=natural_key)

    if skipped:
        print(f"Skipped (not a tile-face name / explicitly ignored): {skipped}\n", file=sys.stderr)

    invalid_pivot = []
    valid_names = []
    for name in new_names:
        triangles = get_triangles(gltf, bin_chunk, name_to_mesh_idx[name])
        final_offsets = derive_footprint(triangles)
        ok = pivot_is_valid(final_offsets)
        tag = "" if ok else "  <-- INVALID PIVOT, see below"
        print(f"--- {name} ({len(final_offsets)} cells){tag} ---", file=sys.stderr)
        print(render_ascii(final_offsets), file=sys.stderr)
        print(file=sys.stderr)
        (valid_names if ok else invalid_pivot).append(name)

    if invalid_pivot:
        print(
            f"WARNING: {invalid_pivot} have their mesh origin somewhere in the "
            "shape's interior (cells extend in BOTH directions along the "
            "origin's own row and/or column) instead of at a genuine corner. "
            "FootprintRegistry's pivot-correction can only fix a uniform "
            "wrong-corner offset, not this - the mesh's origin needs moving "
            "to an actual corner of the piece in Blender and re-exporting. "
            "Excluded from the output below.\n",
            file=sys.stderr,
        )

    print("# Paste into FootprintRegistry.gd's FOOTPRINTS dict:\n")
    for name in valid_names:
        triangles = get_triangles(gltf, bin_chunk, name_to_mesh_idx[name])
        final_offsets = derive_footprint(triangles)
        raw = to_raw_footprint(final_offsets)
        print(format_footprint_gdscript(name, raw))

    return 0


if __name__ == "__main__":
    sys.exit(main())
