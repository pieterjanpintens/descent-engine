class_name TilePlacement
extends Resource

## Unlike TileEntry (the flattened, per-cell logical result), this records
## the actual paint action: which mesh, at which origin cell, at what
## orientation. Needed to repaint FloorGridMap/WallGridMap when loading a
## saved mission - TileEntry alone doesn't carry enough info to know WHICH
## origin cell to paint at, since multiple covered cells share one entry.

enum Layer { FLOOR, WALL }

@export var layer: Layer = Layer.FLOOR
@export var origin_cell: Vector3i = Vector3i.ZERO
@export var mesh_item_name: String = ""
@export var orientation: int = 0
