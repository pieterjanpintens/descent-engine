class_name InteractableEntry
extends Resource

enum Type {
	PROP,       ## purely decorative or minor interaction (bookshelf, well, table)
	DOOR,
	OBJECTIVE,
	HAZARD,
	LEVEL_LINK, ## stairs, ramps, ledges - anything connecting cells at different Y
}

@export var type: Type = Type.PROP
@export var mesh_item_name: String = ""   ## matches the GridMap MeshLibrary item
@export var origin_cell: Vector3i = Vector3i.ZERO
@export var footprint: Array[Vector3i] = [Vector3i.ZERO]  ## cell offsets from origin_cell, already rotation-adjusted, see FootprintRegistry
@export var orientation: int = 0                ## GridMap cell orientation index (0-23)
@export var blocks_movement: bool = true
@export var blocks_los: bool = false
@export var props: Dictionary = {}   ## free-form: linked_region, locked, loot_table, etc.

## Only meaningful when type == LEVEL_LINK. Two cells this connector joins -
## covers both "real" floor-to-floor stairs (large Y difference) and a
## localized dais/ledge step within one room (often just Y+1). Movement/LOS
## logic should treat these as an explicit traversable link rather than
## assuming any adjacency between cells at different Y.
@export var link_from_cell: Vector3i = Vector3i.ZERO
@export var link_to_cell: Vector3i = Vector3i.ZERO
@export var link_bidirectional: bool = true
