class_name TilePlacement
extends OutlineNode

## Unlike TileEntry (the flattened, per-cell logical result), this records
## the actual paint action: which mesh, at which origin cell, at what
## orientation. Needed to repaint FloorGridMap when loading a saved mission
## - TileEntry alone doesn't carry enough info to know WHICH origin cell to
## paint at, since multiple covered cells share one entry.
##
## id/parent_id/reference_name/visible come from OutlineNode - see that
## script's own comments. Both FLOOR and UNDERLAY placements appear in the
## outline tree (requested 2026-09-10). A WALL layer/GridMap existed
## earlier but was removed 2026-09-11 - the game has no wall concept, it
## was never used in real missions.

enum Layer { FLOOR, UNDERLAY }

@export var layer: Layer = Layer.FLOOR
@export var origin_cell: Vector3i = Vector3i.ZERO
@export var mesh_item_name: String = ""
@export var orientation: int = 0
