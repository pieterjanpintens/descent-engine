class_name InteractableEntry
extends Resource

enum Type {
	PROP,       ## purely decorative or minor interaction (bookshelf, well, table)
	DOOR,
	OBJECTIVE,
	HAZARD,
}

@export var type: Type = Type.PROP
@export var mesh_item_name: String = ""   ## matches the GridMap MeshLibrary item
@export var origin_cell: Vector3i = Vector3i.ZERO
@export var footprint: Vector3i = Vector3i.ONE  ## already rotation-adjusted, see FootprintRegistry
@export var orientation: int = 0                ## GridMap cell orientation index (0-23)
@export var blocks_movement: bool = true
@export var blocks_los: bool = false
@export var props: Dictionary = {}   ## free-form: linked_region, locked, loot_table, etc.
