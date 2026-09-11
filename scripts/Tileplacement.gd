class_name TilePlacement
extends OutlineNode

## Unlike TileEntry (the flattened, per-cell logical result), this records
## the actual paint action: which mesh, at which origin cell, at what
## orientation. Needed to repaint FloorGridMap/WallGridMap when loading a
## saved mission - TileEntry alone doesn't carry enough info to know WHICH
## origin cell to paint at, since multiple covered cells share one entry.
##
## id/parent_id/reference_name/visible come from OutlineNode - see that
## script's own comments. Only FLOOR and UNDERLAY placements actually
## appear in the outline tree (requested 2026-09-10) - WALL placements
## still get an id assigned by LayeredMap.rebuild_floor_tiles() (simplest
## to treat uniformly there) but CreatorOutline.gd deliberately skips them
## when building the tree. Wall painting isn't actually used in real
## missions - flagged for possible removal later, not attempted here.

enum Layer { FLOOR, WALL, UNDERLAY }

@export var layer: Layer = Layer.FLOOR
@export var origin_cell: Vector3i = Vector3i.ZERO
@export var mesh_item_name: String = ""
@export var orientation: int = 0
