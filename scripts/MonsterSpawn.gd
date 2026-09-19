class_name MonsterSpawn
extends OutlineNode

## A monster spawn AREA (reworked 2026-09-19): an ordered list of
## tile-square ("game unit") cells drawn with the Creator's Monster Spawn
## tool. Tile N is `cells[N - 1]` - the number shown in the Creator is just
## the list position, so deleting or reordering a tile renumbers the rest
## automatically. An OutlineNode entity (id/parent_id/reference_name/
## visible) so it appears in the Creator outline tree and an
## Effect.Type.SPAWN_MONSTERS effect can reference it by id: that effect's
## monster list is matched to these cells in order (first monster -> tile
## 1, ...).
@export var cells: Array[Vector3i] = []
