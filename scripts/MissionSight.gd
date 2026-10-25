class_name MissionSight
extends RefCounted

## What the Player's line-of-sight tool needs, built from a LOADED mission (what is on the board right now): the SightLine context, the floor
## squares, and the routes between them. Static and free of scene nodes, so it can be tested without a Player. Experimental, branch
## experiment/ai-map-generation.
##
## Heights: a placed piece's LEVEL (origin_cell.y, the editor's PageUp/PageDown level) is taken as its height in height units - a level is
## 3.6 mesh units tall, exactly one height unit (see BuildRules). Squares are 0-based game units (fine cell / 2), like the plan validator's.
## Only pieces that are revealed (MissionData.is_effectively_visible) and not held back by a running stage reveal count.


## {"sight": SightLine context, "squares": {Vector3i (x, height, z): true}, "links": Array of [Vector3i, Vector3i] (a stair or ladder step)}.
static func build(mission: MissionData, held_back: Dictionary = {}) -> Dictionary:
	var floors: Dictionary = {}
	_collect_floor(mission, held_back, mission.floor_placements, mission.floor_occupied_cells, floors)
	_collect_floor(mission, held_back, mission.underlay_placements, mission.underlay_occupied_cells, floors)
	var blockers: Dictionary = {}
	var props: Array[InteractableEntry] = []
	for entry in mission.interactables:
		if held_back.has(entry) or not mission.is_effectively_visible(entry):
			continue
		props.append(entry)
		var base: int = entry.origin_cell.y
		var cells := _cells_of(entry)
		for cell in BuildRules.sight_cells_from_footprint(entry.mesh_item_name, cells):
			var key := Vector2i(cell.x, cell.z)
			if not blockers.has(key):
				blockers[key] = []
			blockers[key].append(Vector2(float(base), float(base) + BuildRules.piece_height(entry.mesh_item_name)))
	# Virtual LOS walls (LosBlocker) in force: an infinitely high wall over the whole tile square (1-based square -> its 2x2 fine cells), on every level.
	var cpt_fine := FootprintRegistry.CELLS_PER_TILE
	for blocker in mission.los_blockers:
		if held_back.has(blocker) or not mission.is_effectively_visible(blocker):
			continue
		for tile: Vector3i in blocker.cells:
			for dx in cpt_fine:
				for dz in cpt_fine:
					var fine := Vector2i((tile.x - 1) * cpt_fine + dx, (tile.z - 1) * cpt_fine + dz)
					if not blockers.has(fine):
						blockers[fine] = []
					blockers[fine].append(Vector2(-1000.0, 1000.0))
	# A bridge is walkable: its two ramp ends count as floor at its own height (also where they rest on the bare ground) and its middle
	# deck as floor one unit higher, so ranges and sight cross a gap by it and a figure can stand on the deck.
	for entry in props:
		if BuildRules.is_bridge(entry.mesh_item_name):
			var bridge_cells := _cells_of(entry)
			var bridge_base: int = entry.origin_cell.y
			for cell in BuildRules.bridge_end_cells(bridge_cells):
				_add_floor_cell(floors, bridge_base, cell)
			for cell in BuildRules.bridge_middle_cells(bridge_cells):
				_add_floor_cell(floors, bridge_base + BuildRules.BRIDGE_RISE, cell)
	var sight := SightLine.context_from(blockers, floors)
	var squares: Dictionary = {}
	for square: Vector3i in sight["squares"]:
		squares[square] = true
	return {"sight": sight, "squares": squares, "links": _links(props, squares)}


## The 8 neighbours of a column: moving diagonally costs one step like any other.
const STEPS_8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

## The shortest route (in steps) from `start` (x, height, z) to every square it can reach: one step to a touching square at the same height,
## and one step along a stair or ladder to the height above. Solid pieces are NOT in the way (they can be destroyed or opened).
static func routes(data: Dictionary, start: Vector3i) -> Dictionary:
	# RANGE: the shortest route in squares, diagonals included (every square touching the start's corner or edge is 1, like a circle expanding) between the two columns (holes are walked around). HEIGHT DOES NOT COUNT:
	# a square one or two levels up or down is as far away as the same square on the ground, and levels do not have to be walkable to each
	# other (a shot does not need a stair), so every square of every level gets the number of its column. A square on another level in
	# the viewer's own column gets 1 (the viewer's own square is 0).
	var squares: Dictionary = data["squares"]
	var columns: Dictionary = {}
	for square: Vector3i in squares:
		columns[Vector2i(square.x, square.z)] = true
	var origin := Vector2i(start.x, start.z)
	var column_distance: Dictionary = {origin: 0}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for step in STEPS_8:
			var next: Vector2i = current + step
			if columns.has(next) and not column_distance.has(next):
				column_distance[next] = column_distance[current] + 1
				queue.append(next)
	var distance: Dictionary = {}
	for square: Vector3i in squares:
		var column := Vector2i(square.x, square.z)
		if column_distance.has(column):
			distance[square] = column_distance[column]
	for square: Vector3i in distance.keys():
		if distance[square] == 0 and square != start:
			distance[square] = 1
	distance[start] = 0
	return distance


static func _add_floor_cell(floors: Dictionary, height: int, cell: Vector3i) -> void:
	if not floors.has(height):
		floors[height] = {}
	floors[height][Vector2i(cell.x, cell.z)] = true


static func _collect_floor(mission: MissionData, held_back: Dictionary, placements: Array, occupied: Dictionary, floors: Dictionary) -> void:
	var visible_origins: Dictionary = {}
	for placement in placements:
		if not held_back.has(placement) and mission.is_effectively_visible(placement):
			visible_origins[placement.origin_cell] = true
	for fine: Vector3i in occupied:
		if visible_origins.has(occupied[fine]):
			if not floors.has(fine.y):
				floors[fine.y] = {}
			floors[fine.y][Vector2i(fine.x, fine.z)] = true


## A placed prop's absolute fine cells.
static func _cells_of(entry: InteractableEntry) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for offset in entry.footprint:
		cells.append(entry.origin_cell + offset)
	return cells


## The steps stairs and ladders add. A stair links each square of its high end to the floor one unit up that it holds or touches; a ladder
## links the floor squares touching it to the floor squares touching it `rise` units up.
static func _links(props: Array[InteractableEntry], squares: Dictionary) -> Array:
	var links: Array = []
	var cpt := FootprintRegistry.CELLS_PER_TILE
	for entry in props:
		var mesh := entry.mesh_item_name
		var base: int = entry.origin_cell.y
		var cells := _cells_of(entry)
		if mesh == "stair":
			var seen: Dictionary = {}
			for cell in BuildRules.stair_high_end(entry.origin_cell, cells):
				seen[Vector2i(floori(float(cell.x) / cpt), floori(float(cell.z) / cpt))] = true
			for square: Vector2i in seen:
				var lower := Vector3i(square.x, base, square.y)
				for rise: int in BuildRules.support_rises("stair"):
					for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var upper := Vector3i(square.x + offset.x, base + rise, square.y + offset.y)
						if squares.has(lower) and squares.has(upper):
							links.append([lower, upper])
		var climbs := BuildRules.climb_rises(mesh)
		if not climbs.is_empty():
			var own: Dictionary = {}
			for cell in cells:
				own[Vector2i(floori(float(cell.x) / cpt), floori(float(cell.z) / cpt))] = true
			var touching: Array[Vector2i] = []
			for square: Vector2i in own:
				for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = square + offset
					if not own.has(next) and not touching.has(next):
						touching.append(next)
			for rise: int in climbs:
				for below in touching:
					for above in touching:
						var lower := Vector3i(below.x, base, below.y)
						var upper := Vector3i(above.x, base + rise, above.y)
						if squares.has(lower) and squares.has(upper):
							links.append([lower, upper])
	return links
