class_name TutorialAssists
extends RefCounted

## The "Do it for me" buttons of the tutorial steps (data/tutorials/*.json: "assist": "<name>"). Each does what the user is asked to do,
## through the editor's own code (same undo steps, same limits, same working group as a click would give), so the result is exactly
## what a person would have made. `run()` returns a short sentence for the panel.

## The tiles of the room the tutorial builds, in the order they are placed: three plain rectangles (19a is 4 x 3 squares, 1a and 2a
## are 3 x 2), which always fit together into one connected room.
const ROOM_TILES := ["19a", "1a", "2a"]


static func run(name: String, r: TutorialRunner) -> String:
	match name:
		"new_mission":
			r.start_empty_mission()
			return ""
		"make_stage":
			return _make_stage(r)
		"place_first_floor":
			return _place_room(r, 1)
		"place_room":
			return _place_room(r, ROOM_TILES.size())
		"rotate_tile":
			return _rotate_tile(r)
		"move_tile":
			return _move_tile(r)
		"undo_twice":
			r.history.undo()
			r.history.undo()
			return "Undone twice."
		"place_props":
			return _place_props(r)
		"name_chest":
			return _name_chest(r)
		"add_starts":
			return _add_starts(r)
		"fit_players":
			return _fit_players(r)
	push_warning("TutorialAssists: unknown assist '%s'" % name)
	return ""


static func _make_stage(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	if mission.groups.is_empty():
		r.history.record("New group", func():
			var group := MissionGroup.new()
			group.id = mission.allocate_object_id()
			group.reference_name = "Cave"
			mission.groups.append(group)
		)
		r.layered_map.notify_objects_changed()
	r.controller.set_working_group(mission.groups[0].id)
	return "Made the stage \"%s\" and chose it as the working group." % mission.groups[0].reference_name


## Places the next `count` tiles of the room that are still free in the box: the first one just right of whatever is on the map,
## the others touching the floor that is there (so it also works when the user placed a first tile somewhere themselves).
static func _place_room(r: TutorialRunner, count: int) -> String:
	var mission := r.layered_map.mission
	var placed := 0
	for mesh: String in ROOM_TILES:
		if placed >= count:
			break
		if _is_placed(mission, mesh):
			continue
		var spot = _spot_for(mission, mesh)
		if spot != null and r.controller.place_mesh_at_tile_square(mesh, spot):
			placed += 1
	if placed == 0:
		return "Those tiles are already used - place any tiles you like, touching each other."
	return "Placed %d tile(s)." % placed


## Where the room's tiles go, relative to the top-left square of the first tile (19a, 4 x 3 squares): the other two (3 x 2 each) sit
## side by side right below it, making an L shaped room of 6 x 5 squares.
const ROOM_OFFSETS := {"1a": Vector2i(0, 3), "2a": Vector2i(3, 3)}


## The tile square to put `mesh`'s origin on: with no floor yet, the top-left of the free spot; else its place in the room under the
## first tile; else (the user placed other tiles) the first free place that touches the floor. null when there is none.
static func _spot_for(mission: MissionData, mesh: String) -> Variant:
	var offsets := FootprintRegistry.get_footprint(mesh)
	var bounds := _bounds(offsets)
	var cpt := FootprintRegistry.CELLS_PER_TILE
	if mission.floor_occupied_cells.is_empty():
		var corner := StageBuilder.free_spot(mission, 1) + Vector2i.ONE  # top-left tile square (they count from 1)
		var origin := corner - bounds.position
		return Vector3i(origin.x, 0, origin.y)
	if ROOM_OFFSETS.has(mesh):
		for placement in mission.floor_placements:
			if placement.mesh_item_name == ROOM_TILES[0]:
				var room_offset: Vector2i = ROOM_OFFSETS[mesh]
				var top_left: Vector2i = _top_left(mission, placement) + room_offset
				var origin: Vector2i = top_left - bounds.position
				var free := true
				for offset in offsets:
					if mission.floor_occupied_cells.has(Vector3i(origin.x * cpt, 0, origin.y * cpt) + offset):
						free = false
				if free:
					return Vector3i(origin.x, 0, origin.y)
	var low := Vector2i(999999, 999999)
	var high := Vector2i(-999999, -999999)
	for square in _floor_squares(mission):
		low = Vector2i(mini(low.x, square.x), mini(low.y, square.z))
		high = Vector2i(maxi(high.x, square.x), maxi(high.y, square.z))
	for z in range(low.y - 8, high.y + 9):
		for x in range(low.x - 8, high.x + 9):
			var fine_origin := Vector3i(x * cpt, 0, z * cpt)
			var touches := false
			var overlaps := false
			for offset in offsets:
				var cell := fine_origin + offset
				if mission.floor_occupied_cells.has(cell):
					overlaps = true
					break
				for step in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					if mission.floor_occupied_cells.has(cell + step):
						touches = true
			if touches and not overlaps:
				return Vector3i(x, 0, z)
	return null


## The tile squares a footprint (fine cells relative to its origin) covers, as a rectangle relative to the origin square.
static func _bounds(offsets: Array[Vector3i]) -> Rect2i:
	var bounds := Rect2i()
	var first := true
	for offset in offsets:
		var square := FootprintRegistry.fine_cell_to_tile_square(offset)
		var point := Vector2i(square.x, square.z)
		bounds = Rect2i(point, Vector2i.ZERO) if first else bounds.expand(point)
		first = false
	return bounds


## The top-left tile square a placed floor tile covers.
static func _top_left(mission: MissionData, placement: TilePlacement) -> Vector2i:
	var low := Vector2i(999999, 999999)
	for cell: Vector3i in mission.floor_occupied_cells:
		if mission.floor_occupied_cells[cell] == placement.origin_cell:
			var square := FootprintRegistry.fine_cell_to_tile_square(cell)
			low = Vector2i(mini(low.x, square.x), mini(low.y, square.z))
	return low


static func _is_placed(mission: MissionData, mesh: String) -> bool:
	for placement in mission.floor_placements:
		if placement.mesh_item_name == mesh:
			return true
	return false


static func _rotate_tile(r: TutorialRunner) -> String:
	var tiles := r.layered_map.mission.floor_placements
	if tiles.is_empty():
		return "Place a tile first."
	r.controller.selected_placed_id = tiles[0].id
	r.controller.rotate_selected_placed()
	return "Rotated a tile a quarter turn. You will undo it in a moment."


static func _move_tile(r: TutorialRunner) -> String:
	var tiles := r.layered_map.mission.floor_placements
	if tiles.is_empty():
		return "Place a tile first."
	var tile: TilePlacement = tiles[tiles.size() - 1]
	var target := tile.origin_cell + Vector3i(FootprintRegistry.CELLS_PER_TILE * 3, 0, 0)
	r.history.record("Move", func(): r.layered_map.move_node(tile.id, target))
	return "Moved a tile three squares sideways. You will undo it in a moment."


## Tile squares of the floor, and the ones that already hold a prop.
static func _floor_squares(mission: MissionData) -> Array[Vector3i]:
	var squares: Array[Vector3i] = []
	for cell: Vector3i in mission.floor_occupied_cells:
		var square := FootprintRegistry.fine_cell_to_tile_square(cell)
		if not squares.has(square):
			squares.append(square)
	return squares


static func _prop_squares(mission: MissionData) -> Array[Vector3i]:
	var squares: Array[Vector3i] = []
	for cell: Vector3i in mission.occupied_cells:
		var square := FootprintRegistry.fine_cell_to_tile_square(cell)
		if not squares.has(square):
			squares.append(square)
	return squares


## Floor squares without a prop or a start square on them, west to east, north to south.
static func _free_squares(mission: MissionData) -> Array[Vector3i]:
	var taken := _prop_squares(mission)
	for start in mission.player_spawn_cells:
		taken.append(start)
	var free: Array[Vector3i] = []
	for square in _floor_squares(mission):
		if not taken.has(square):
			free.append(square)
	free.sort_custom(func(a: Vector3i, b: Vector3i): return a.x < b.x or (a.x == b.x and a.z < b.z))
	return free


static func _place_props(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var free := _free_squares(mission)
	if free.is_empty():
		return "There is no free floor to put props on."
	var placed := 0
	var have := TutorialChecks.placed_props(mission)
	var names := ["chest", "tree"]
	var tree_spot := free[0]
	for square in free:  # the tree in the north-east nook: the northmost row, its eastmost square
		if square.z < tree_spot.z or (square.z == tree_spot.z and square.x > tree_spot.x):
			tree_spot = square
	var spots: Array[Vector3i] = [free[free.size() - 1], tree_spot]  # the chest in the far east
	for i in names.size():
		var already := false
		for entry in have:
			if entry.mesh_item_name == names[i]:
				already = true
		if not already and r.controller.place_mesh_at_tile_square(names[i], spots[i]):
			placed += 1
	return "Placed %d prop(s)." % placed if placed > 0 else "Those props are already there (or used up)."


static func _name_chest(r: TutorialRunner) -> String:
	var props := TutorialChecks.placed_props(r.layered_map.mission)
	if props.is_empty():
		return "Place a prop first."
	var target := props[0]
	for entry in props:
		if entry.mesh_item_name == "chest":
			target = entry
	r.history.record("Set name", func(): target.reference_name = "treasure_chest")
	r.layered_map.notify_objects_changed()
	return "Named it treasure_chest."


static func _add_starts(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var wanted := 4 - mission.player_spawn_cells.size()
	if wanted <= 0:
		return "There are already four or more."
	var free := _free_squares(mission)
	if free.is_empty():
		return "There is no free floor to start on."
	r.history.record("Toggle spawn cell", func():
		for i in mini(wanted, free.size()):
			mission.player_spawn_cells.append(free[i])
		r.layered_map.set_spawn_overlay_cells(mission.player_spawn_cells)
	)
	return "Marked %d start square(s)." % mini(wanted, free.size())


static func _fit_players(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var starts := mission.player_spawn_cells.size()
	if starts < 1:
		return "Mark some start squares first."
	r.history.record("Set max players", func():
		mission.max_players = clampi(starts, 1, 6)
		mission.min_players = mini(mission.min_players, mission.max_players)
	)
	r.layered_map.notify_objects_changed()
	return "Max players is now %d." % mission.max_players
