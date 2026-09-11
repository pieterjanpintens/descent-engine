class_name InteractableEntry
extends OutlineNode

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

## Free-form: linked_region, locked, loot_table, etc. "interactible" (bool,
## default true when absent) is the one well-known key here, toggling
## whether this prop's actions[] can currently be used - read by the
## runtime directly, not looked up by name from anywhere else. Visibility
## used to live here too ("visible" key) but graduated to OutlineNode's
## own explicit `visible` field (2026-09-10) since every outline node ends
## up needing it, not just props with genuinely free-form extra data -
## this dict is deliberately Object-only, TilePlacement/MissionGroup don't
## have one.
@export var props: Dictionary = {}
## What a player can report doing to this prop (push a lever, search a
## bookshelf) - see PropAction. Empty means purely decorative, nothing to
## report.
@export var actions: Array[PropAction] = []

## Only meaningful when type == LEVEL_LINK. Two cells this connector joins -
## covers both "real" floor-to-floor stairs (large Y difference) and a
## localized dais/ledge step within one room (often just Y+1). Movement/LOS
## logic should treat these as an explicit traversable link rather than
## assuming any adjacency between cells at different Y.
@export var link_from_cell: Vector3i = Vector3i.ZERO
@export var link_to_cell: Vector3i = Vector3i.ZERO
@export var link_bidirectional: bool = true
