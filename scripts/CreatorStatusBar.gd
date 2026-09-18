class_name CreatorStatusBar
extends Label

## Bottom-left coordinate readout, requested 2026-09-18 as a small editor
## convenience - shows the tile-square ("game unit") coordinate the mouse
## is currently hovering, NOT GridMap's own twice-as-fine internal cell
## resolution (get_hovered_cell() converts via
## FootprintRegistry.fine_cell_to_tile_square() - see that getter's own
## doc) - a designer thinks in game units, not raw grid cells.
##
## Polls creator_controller.get_hovered_cell()/has_hover() every frame
## rather than listening for a signal - a continuously-changing value while
## the mouse moves reads more naturally as polled state, the same way
## CreatorController itself recomputes its hovered cell every _process()
## tick.

@export var creator_controller: CreatorController


func _process(_delta: float) -> void:
	if creator_controller == null or not creator_controller.has_hover():
		text = ""
		return
	var cell := creator_controller.get_hovered_cell()
	text = "Tile: (%d, %d, %d)" % [cell.x, cell.y, cell.z]
