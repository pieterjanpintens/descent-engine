class_name TileEntry
extends Resource

## Logical description of one floor/wall cell. This is derived data - the
## Creator tool fills it in automatically from the mesh item's naming
## convention (see FootprintRegistry.LOGICAL_DEFAULTS) but individual cells
## can always be overridden by hand for special cases (a "floor" mesh that's
## actually a chasm edge, etc).

@export var mesh_item_name: String = ""
@export var walkable: bool = true
@export var blocks_los: bool = false
@export var region_id: String = ""
