# Footprint extraction from mesh geometry

Derives `FootprintRegistry.FOOTPRINTS` entries directly from
`models/floors.glb`'s actual mesh geometry, instead of hand-typing ASCII art
per tile.

## Why this works

`models/floors.glb` has one named node per tile face (`"1a"`, `"3b"`,
`"18a"`, ...) matching `FootprintRegistry.FOOTPRINTS`'s keys exactly, and each
node sits at its own local origin with no transform (translation/rotation/
scale all identity) - so raw vertex positions are already in the
pivot-relative space `FootprintRegistry` expects. 1 tile-square = 3.2 world
units in this file, calibrated against the tiles already hand-authored in
`FootprintRegistry.gd`.

## Usage

No third-party dependencies - parses the GLB/glTF container by hand.

```
python tools/footprint_extraction/extract_footprints.py
```

Run from the repo root. It:

1. Re-derives every tile already in `FootprintRegistry.gd`'s `FOOTPRINTS` and
   refuses to print anything for new tiles unless every known one matches
   exactly (stderr, "Calibration OK" / "CALIBRATION FAILED").
2. Prints an ASCII-art preview of every tile face in `floors.glb` that isn't
   already in `FOOTPRINTS` (stderr) - eyeball these, same as the hand-authored
   comments in `FootprintRegistry.gd`, to confirm e.g. `a`/`b` faces are
   proper mirror images.
3. Flags any tile whose mesh origin sits in the shape's interior instead of
   on a real corner (cells extend in both directions along the origin's own
   row and/or column) - these are excluded from the pasteable output with a
   warning, since no uniform pivot correction can fix them. The mesh's origin
   needs moving to an actual corner in Blender and re-exporting.
4. Prints ready-to-paste `Vector3i` entries (stdout) for every tile that
   passed both checks.

Re-run any time new tile faces are added to `floors.glb`.
