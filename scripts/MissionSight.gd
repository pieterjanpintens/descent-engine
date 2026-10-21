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
	var sight := SightLine.context_from(blockers, floors)
	var squares: Dictionary = {}
	for square: Vector3i in sight["squares"]:
		squares[square] = true
	return {"sight": sight, "squares": squares, "links": _links(props, squares)}


## The shortest route (in steps) from `start` (x, height, z) to every square it can reach: one step to a touching square at the same height,
## and one step along a stair or ladder to the height above. Solid pieces are NOT in the way (they can be destroyed or opened).
static func routes(data: Dictionary, start: Vector3i) -> Dictionary:
	var squares: Dictionary = data["squares"]
	var neighbours: Dictionary = {}
	for link: Array in data["links"]:
		for pair in [[link[0], link[1]], [link[1], link[0]]]:
			if not neighbours.has(pair[0]):
				neighbours[pair[0]] = []
			neighbours[pair[0]].append(pair[1])
	var distance: Dictionary = {start: 0}
	var queue: Array[Vector3i] = [start]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var next_squares: Array[Vector3i] = []
		for step in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			next_squares.append(current + step)
		for extra: Vector3i in neighbours.get(current, []):
			next_squares.append(extra)
		for next in next_squares:
			if squares.has(next) and not distance.has(next):
				distance[next] = distance[current] + 1
				queue.append(next)
	return distance


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
