class_name PlayerStart
extends OutlineNode

## A player start AREA (2026-11-06): the tile squares ("game unit" coordinates, 1-based like MonsterSpawn.cells; the y is the level the
## square was drawn on) where the heroes may stand when a Table begins. An OutlineNode entity like MonsterSpawn / LosBlocker, so it shows in
## the Creator outline tree and sits in a Table (or a stage inside one): MissionData.table_of(start) says which Table it starts. Replaces the
## old flat MissionData.player_spawn_cells list (see MissionData.upgrade_legacy_starts()). A mission can have several (e.g. one per Table, or
## one per stage); all the squares of a Table together are where its heroes start.
@export var cells: Array[Vector3i] = []
