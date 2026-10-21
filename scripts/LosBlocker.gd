class_name LosBlocker
extends OutlineNode

## A virtual line-of-sight wall (2026-10-21): tile squares (1-based "game unit" coordinates, same as MonsterSpawn.cells and
## MissionData.player_spawn_cells; the y is the level the square was drawn on and is ignored) that block LINE OF SIGHT ONLY, as an infinitely
## high wall on every level, even over open space - to stop shots where the author does not want them. An OutlineNode entity so it can sit in
## a group (a stage): MissionData.is_effectively_visible() decides whether it is in force, so a blocker in a hidden stage neither blocks sight
## nor shows its outline, and does not give the level design away. Drawn in the Creator with the Palette Misc tab's LOS Blocker tool.
@export var cells: Array[Vector3i] = []
