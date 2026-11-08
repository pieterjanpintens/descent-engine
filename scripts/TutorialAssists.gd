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
		"make_template":
			return _make_template()
		"add_spawn_area":
			return _add_spawn_area(r)
		"add_blocker":
			return _add_blocker(r)
		"add_variables":
			return _add_variables(r)
		"add_chest_action":
			return _add_chest_action(r)
		"add_spawn_trigger":
			return _add_spawn_trigger(r)
		"add_defeat_effect":
			return _add_defeat_effect(r)
		"add_objectives":
			return _add_objectives(r)
		"play_now":
			r.play()
			return ""
		# ---- tutorial 2: the fork ----
		"load_start":
			r.load_start_mission()
			return ""
		"make_lair_stage":
			return _make_lair_stage(r)
		"place_lair":
			return _place_fork_tiles(r, true)
		"place_paths":
			return _place_fork_tiles(r, false)
		"place_door":
			return _place_door(r)
		"add_encounter_variable":
			return _add_encounter_variable(r)
		"add_lair_spawn":
			return _add_lair_spawn(r)
		"add_door_action":
			return _add_door_action(r)
		"add_door_stage_effects":
			return _add_door_stage_effects(r)
		"add_door_spawn":
			return _add_door_spawn(r)
		"add_spawn_guard":
			return _add_spawn_guard(r)
		"make_group":
			return _make_group(r)
		"place_token":
			return _place_token(r)
		"add_token_action":
			return _add_token_action(r)
		"add_token_effects":
			return _add_token_effects(r)
		"add_door_wake":
			return _add_door_wake(r)
		"add_restless_trigger":
			return _add_restless_trigger(r)
		"add_reinforcements":
			return _add_reinforcements(r)
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


## Floor squares without a prop, a start square, a monster spawn tile or a LOS blocker on them, west to east, north to south.
static func _free_squares(mission: MissionData) -> Array[Vector3i]:
	var taken := _prop_squares(mission)
	for start in mission.all_start_cells():
		taken.append(start)
	for spawn in mission.monster_spawns:
		taken.append_array(spawn.cells)
	for blocker in mission.los_blockers:
		taken.append_array(blocker.cells)
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
	var wanted := 4 - mission.all_start_cells().size()
	if wanted <= 0:
		return "There are already four or more."
	var free := _free_squares(mission)
	if free.is_empty():
		return "There is no free floor to start on."
	r.history.record("Toggle spawn cell", func():
		var area: PlayerStart = null
		for candidate in mission.player_starts:
			if mission.table_of(candidate) == r.controller.working_table_id():
				area = candidate
				break
		if area == null:
			area = PlayerStart.new()
			area.id = mission.allocate_object_id()
			area.parent_id = r.controller.working_group_id
			mission.player_starts.append(area)
		for i in mini(wanted, free.size()):
			area.cells.append(free[i])
		r.layered_map.refresh_start_overlay()
	)
	r.layered_map.notify_objects_changed()
	return "Marked %d start square(s)." % mini(wanted, free.size())


static func _fit_players(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var starts := mission.all_start_cells().size()
	if starts < 1:
		return "Mark some start squares first."
	r.history.record("Set max players", func():
		mission.max_players = clampi(starts, 1, 6)
		mission.min_players = mini(mission.min_players, mission.max_players)
	)
	r.layered_map.notify_objects_changed()
	return "Max players is now %d." % mission.max_players


# ---- Monsters, variables, actions, triggers, objectives ----

static func _rows(value: int) -> Array[LevelValue]:
	var row := LevelValue.new()
	row.min_level = 1
	row.max_level = 99
	row.value = value
	var rows: Array[LevelValue] = [row]
	return rows


## A simple base monster template for people who have not imported the game's monsters.
static func _make_template() -> String:
	if not MonsterArchetypeLibrary.names_of_kind(MonsterArchetype.Kind.BASE).is_empty():
		return "You already have a base template."
	var archetype := MonsterArchetype.new()
	archetype.template_name = "Tutorial monster"
	archetype.kind = MonsterArchetype.Kind.BASE
	archetype.hitpoints_scaling = _rows(10)
	archetype.attack_scaling = _rows(3)
	archetype.defense_scaling = _rows(1)
	archetype.speed_scaling = _rows(4)
	if MonsterArchetypeLibrary.save_template(archetype) == "":
		return "The template could not be saved."
	return "Saved a simple base template, 'Tutorial monster' (10 hitpoints, attack 3, defense 1, speed 4)."


static func _add_spawn_area(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var free := _free_squares(mission)
	if free.size() < 2:
		return "There is no free floor for a spawn area."
	var id := r.controller.create_monster_spawn()
	var spawn: MonsterSpawn = r.controller._find_monster_spawn(id)
	var tiles: Array[Vector3i] = [free[free.size() - 1], free[free.size() - 2]]  # the far east of the room
	r.history.record("Toggle spawn tile", func(): spawn.cells.append_array(tiles))
	r.layered_map.refresh_monster_spawn_overlay()
	r.layered_map.notify_objects_changed()
	return "Drew a spawn area of two squares at the far end of the room."


static func _add_blocker(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var free := _free_squares(mission)
	if free.size() < 2:
		return "There is no free floor for a blocker."
	var id := r.controller.create_los_blocker()
	var blocker: LosBlocker = r.controller._find_los_blocker(id)
	var middle := free.size() / 2
	var tiles: Array[Vector3i] = [free[middle], free[middle + 1]]
	r.history.record("Toggle LOS blocker square", func(): blocker.cells.append_array(tiles))
	r.layered_map.refresh_blocker_overlay()
	r.layered_map.notify_objects_changed()
	return "Drew a blocker on two squares in the middle of the room."


static func _add_variables(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var added := 0
	for variable_name: String in [TutorialChecks.MONSTER_DEAD, TutorialChecks.CHEST_LOOTED]:
		var exists := false
		for variable in mission.custom_variables:
			if variable.name == variable_name:
				exists = true
		if exists:
			continue
		r.history.record("Add variable", func():
			var variable := MissionVariable.new()
			variable.name = variable_name
			variable.type = MissionVariable.Type.BOOL
			variable.default_value = false
			mission.custom_variables.append(variable)
		)
		added += 1
	r.layered_map.notify_objects_changed()
	return "Added %d variable(s)." % added


static func _set_true(variable_name: String) -> Effect:
	var effect := Effect.new()
	effect.type = Effect.Type.SET_VARIABLE
	effect.variable_name = variable_name
	effect.value = true
	return effect


static func _add_chest_action(r: TutorialRunner) -> String:
	var props := TutorialChecks.placed_props(r.layered_map.mission)
	if props.is_empty():
		return "Place a chest first."
	var target := props[0]
	for entry in props:
		if entry.mesh_item_name == "chest":
			target = entry
	var action := PropAction.new()
	action.action_id = "search"
	action.action_name = "Search"
	action.description = "You search the chest."
	action.single_shot = true
	var loot := Effect.new()
	loot.type = Effect.Type.LOOT
	loot.loot_materials = {LootMaterials.GOLD: 50}
	loot.loot_title = "The monster's hoard"
	action.effects.append(loot)
	action.effects.append(_set_true(TutorialChecks.CHEST_LOOTED))
	r.history.record("Add action", func(): target.actions.append(action))
	r.layered_map.notify_objects_changed()
	return "Gave the chest a 'Search' action: it gives 50 gold and sets chest_looted."


static func _add_spawn_trigger(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	if mission.monster_spawns.is_empty():
		return "Draw the monster spawn area first."
	var monster := MonsterTemplate.create_with_default_base()
	if monster == null:
		return "Make a base monster template first (File > Monster Templates)."
	monster.folder = "wolf"
	var effect := Effect.new()
	effect.type = Effect.Type.SPAWN_MONSTERS
	effect.target_object_id = mission.monster_spawns[0].id
	effect.spawn_monsters.append(monster)
	var trigger := MissionTrigger.new()
	trigger.id = mission.allocate_object_id()
	trigger.checkpoint = RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE
	trigger.one_shot = true
	trigger.effects.append(effect)
	r.history.record("Add trigger", func(): mission.triggers.append(trigger))
	r.layered_map.notify_objects_changed()
	return "Added a trigger that puts a wolf on the spawn area before the first player phase."


static func _add_defeat_effect(r: TutorialRunner) -> String:
	var effects := TutorialChecks.spawn_effects(r.layered_map.mission)
	if effects.is_empty():
		return "Add the trigger that spawns the monster first."
	r.history.record("Edit defeat effects", func():
		for effect in effects:
			for monster in effect.spawn_monsters:
				if not TutorialChecks.sets_variable(monster.defeat_effects, TutorialChecks.MONSTER_DEAD):
					monster.defeat_effects.append(_set_true(TutorialChecks.MONSTER_DEAD))
	)
	r.layered_map.notify_objects_changed()
	return "The monster now sets monster_dead when it is defeated."


static func _condition(variable_name: String) -> Condition:
	var condition := Condition.new()
	condition.variable_name = variable_name
	condition.operator = Condition.Operator.EQUALS
	condition.value = true
	return condition


static func _add_objectives(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	if TutorialChecks.objective_chain_ok(mission):
		return "The objectives are already there."
	var first := MissionObjective.new()
	first.id = mission.allocate_object_id()
	first.description = "Defeat the monster"
	first.conditions.append(_condition(TutorialChecks.MONSTER_DEAD))
	var second := MissionObjective.new()
	second.id = mission.allocate_object_id()
	second.description = "Loot the monster's lair"
	second.outcome = MissionObjective.Outcome.WIN
	second.conditions.append(_condition(TutorialChecks.CHEST_LOOTED))
	first.children.append(second)
	first.editor_position = Vector2(60, 80)
	second.editor_position = Vector2(360, 80)
	r.history.record("Add objective", func(): mission.objectives.append(first))
	r.layered_map.notify_objects_changed()
	return "Added the two objectives: defeat the monster, then loot the lair (that wins the mission)."


# ---- Tutorial 2: the fork ----

## The Lair tile and the four tiles of the two paths, with the top-left square of each relative to the top-left square of the cave's 19a:
## the north path (3a, 15a) is a wide corridor with the door, the east path (6a, 21a) the side passage; both end at the Lair (17a). The
## layout is fixed for the example cave (19a, 1a and 2a); `ascii()` in a test prints it.
const LAIR_TILE := ["17a", Vector2i(12, -3)]
const PATH_TILES := [["3a", Vector2i(0, -3)], ["15a", Vector2i(4, -3)], ["6a", Vector2i(6, 2)], ["21a", Vector2i(10, 2)]]
## Where the door (a gate across the two-wide north corridor), the side passage's token and the guards' spawn squares go, relative to the same square.
const DOOR_SPOT := Vector2i(8, -1)
const DOOR_TURNS := 0
const TOKEN_SPOT := Vector2i(11, 3)
const LAIR_SPAWN_SQUARES := [Vector2i(16, -1), Vector2i(17, -1), Vector2i(16, 0)]


## The top-left tile square of the example cave's 19a, or null when the mission has none.
static func _cave_anchor(mission: MissionData) -> Variant:
	for placement in mission.floor_placements:
		if placement.mesh_item_name == ROOM_TILES[0]:
			return _top_left(mission, placement)
	return null


static func _shown_stage(mission: MissionData) -> MissionGroup:
	for group in mission.groups:
		if group.visible:
			return group
	return null


static func _make_lair_stage(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var stage := TutorialChecks.hidden_stage(mission)
	if stage == null:
		r.history.record("New group", func():
			var group := MissionGroup.new()
			group.id = mission.allocate_object_id()
			group.reference_name = "Lair"
			group.visible = false
			mission.groups.append(group)
		)
		r.layered_map.notify_objects_changed()
		stage = TutorialChecks.hidden_stage(mission)
	r.controller.set_working_group(stage.id)
	return "Made the stage \"%s\", hidden from the start, and chose it as the working group." % stage.reference_name


## Puts the Lair's tile (`lair`) or the four tiles of the two paths in place, each in the stage it belongs to: the Lair in the hidden stage,
## the paths in the stage the heroes start in.
static func _place_fork_tiles(r: TutorialRunner, lair: bool) -> String:
	var mission := r.layered_map.mission
	var anchor = _cave_anchor(mission)
	if anchor == null:
		return "This needs the example cave (the tiles 19a, 1a and 2a). Place the tiles yourself, or load the example mission from the first step."
	var stage: MissionGroup = TutorialChecks.hidden_stage(mission) if lair else _shown_stage(mission)
	if stage == null:
		return "Make the hidden Lair stage first." if lair else "There is no stage the heroes start in."
	r.controller.set_working_group(stage.id)
	var tiles: Array = [LAIR_TILE] if lair else PATH_TILES
	var placed := 0
	for tile: Array in tiles:
		var mesh: String = tile[0]
		if _is_placed(mission, mesh):
			continue
		var top_left: Vector2i = anchor + tile[1]
		var origin: Vector2i = top_left - _bounds(FootprintRegistry.get_footprint(mesh)).position
		if r.controller.place_mesh_at_tile_square(mesh, Vector3i(origin.x, 0, origin.y)):
			placed += 1
	return "Placed %d tile(s)." % placed if placed > 0 else "Those tiles are already placed (or used up)."


static func _name_prop(r: TutorialRunner, entry: InteractableEntry, prop_name: String) -> void:
	r.history.record("Set name", func(): entry.reference_name = prop_name)
	r.layered_map.notify_objects_changed()


static func _place_door(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var existing := TutorialChecks.door(mission)
	if existing == null:
		var anchor = _cave_anchor(mission)
		if anchor == null:
			return "This needs the example cave. Place a gate across the corridor yourself."
		var stage := _shown_stage(mission)
		if stage != null:
			r.controller.set_working_group(stage.id)
		var spot: Vector2i = anchor + DOOR_SPOT
		if not r.controller.place_mesh_at_tile_square("gate", Vector3i(spot.x, 0, spot.y), DOOR_TURNS):
			return "The gate could not be placed (are all four used up?)."
		existing = TutorialChecks.door(mission)
	_name_prop(r, existing, "lair_door")
	return "Placed a gate across the north corridor and named it lair_door."


static func _add_encounter_variable(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	for variable in mission.custom_variables:
		if variable.name == TutorialChecks.ENCOUNTER_STARTED:
			return "The variable is already there."
	r.history.record("Add variable", func():
		var variable := MissionVariable.new()
		variable.name = TutorialChecks.ENCOUNTER_STARTED
		variable.type = MissionVariable.Type.BOOL
		variable.default_value = false
		mission.custom_variables.append(variable)
	)
	r.layered_map.notify_objects_changed()
	return "Added encounter_started (yes/no, no at the start)."


static func _add_lair_spawn(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var anchor = _cave_anchor(mission)
	var stage := TutorialChecks.hidden_stage(mission)
	if anchor == null or stage == null:
		return "Make the hidden Lair stage and its floor first."
	var floor_squares := _floor_squares(mission)
	var tiles: Array[Vector3i] = []
	for offset: Vector2i in LAIR_SPAWN_SQUARES:
		var square := Vector3i(anchor.x + offset.x, 0, anchor.y + offset.y)
		if floor_squares.has(square):
			tiles.append(square)
	if tiles.size() < 2:
		return "The Lair floor is not in place yet."
	r.controller.set_working_group(stage.id)
	var id := r.controller.create_monster_spawn()
	var spawn: MonsterSpawn = r.controller._find_monster_spawn(id)
	r.history.record("Toggle spawn tile", func(): spawn.cells.append_array(tiles))
	r.layered_map.refresh_monster_spawn_overlay()
	r.layered_map.notify_objects_changed()
	return "Drew a spawn area of %d squares at the back of the Lair." % tiles.size()


static func _condition_on(variable_name: String, operator: Condition.Operator, value: Variant) -> Condition:
	var condition := Condition.new()
	condition.variable_name = variable_name
	condition.operator = operator
	condition.value = value
	return condition


## The door's first action, made on the spot when the gate has none.
static func _door_action(r: TutorialRunner) -> PropAction:
	var entry := TutorialChecks.door(r.layered_map.mission)
	if entry == null:
		return null
	if entry.actions.is_empty():
		var action := PropAction.new()
		action.action_id = "open"
		action.action_name = "Open the door"
		action.description = "You heave the heavy door open."
		action.single_shot = true
		r.history.record("Add action", func(): entry.actions.append(action))
	return entry.actions[0]


static func _add_door_action(r: TutorialRunner) -> String:
	var entry := TutorialChecks.door(r.layered_map.mission)
	if entry == null:
		return "Place the door first."
	if entry.actions.is_empty():
		_door_action(r)
		r.layered_map.notify_objects_changed()
		return "Gave the door the action 'Open the door': a name and a description for the players, single shot."
	var action := entry.actions[0]
	r.history.record("Edit action", func():
		if action.action_name == "":
			action.action_name = "Open the door"
		if action.description == "":
			action.description = "You heave the heavy door open."
		action.single_shot = true
	)
	r.layered_map.notify_objects_changed()
	return "Filled in the door's action."


static func _add_door_stage_effects(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var stage := TutorialChecks.hidden_stage(mission)
	var action := _door_action(r)
	if action == null or stage == null:
		return "Place the door and make the hidden Lair stage first."
	r.history.record("Add effects", func():
		var has_remove := false
		var has_show := false
		for effect in action.effects:
			has_remove = has_remove or (effect.type == Effect.Type.REMOVE_OBJECT and effect.target_object_id == Effect.SELF_ID)
			has_show = has_show or (effect.type == Effect.Type.SHOW_STAGE and effect.target_group_id == stage.id)
		if not has_remove:
			var remove := Effect.new()
			remove.type = Effect.Type.REMOVE_OBJECT
			remove.target_object_id = Effect.SELF_ID
			action.effects.append(remove)
		if not has_show:
			var show := Effect.new()
			show.type = Effect.Type.SHOW_STAGE
			show.target_group_id = stage.id
			action.effects.append(show)
	)
	r.layered_map.notify_objects_changed()
	return "The door now removes itself and shows the Lair."


static func _guard() -> MonsterTemplate:
	if MonsterArchetypeLibrary.names_of_kind(MonsterArchetype.Kind.BASE).is_empty():
		_make_template()  # nobody made a base template yet (tutorial 1 skipped): a simple one
	var guard := MonsterTemplate.create_with_default_base()
	if guard != null:
		guard.folder = "bandit"
		guard.custom_name = "Lair guard"
	return guard


static func _add_door_spawn(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var spawn := TutorialChecks.lair_spawn(mission)
	var action := _door_action(r)
	if spawn == null or action == null:
		return "Draw the Lair's spawn area and place the door first."
	if TutorialChecks.door_spawn(mission) != null:
		return "The door already spawns monsters."
	var first := _guard()
	var second := _guard()
	if first == null:
		return "Make a base monster template first (File > Monster Templates)."
	second.custom_name = "Extra guard"
	second.conditions.append(_condition_on("player_count", Condition.Operator.GREATER_EQUAL, 3))
	var effect := Effect.new()
	effect.type = Effect.Type.SPAWN_MONSTERS
	effect.target_object_id = spawn.id
	effect.spawn_monsters.append(first)
	effect.spawn_monsters.append(second)
	r.history.record("Add effect", func(): action.effects.append(effect))
	r.layered_map.notify_objects_changed()
	return "The door now spawns a guard, and a second one only when three or more heroes play."


static func _add_spawn_guard(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var effect := TutorialChecks.door_spawn(mission)
	var action := _door_action(r)
	if effect == null or action == null:
		return "Add the door's Spawn Monsters effect first."
	r.history.record("Add condition", func():
		if not TutorialChecks.mentions(effect.conditions, TutorialChecks.ENCOUNTER_STARTED):
			effect.conditions.append(_condition_on(TutorialChecks.ENCOUNTER_STARTED, Condition.Operator.EQUALS, false))
		if not TutorialChecks.sets_variable(action.effects, TutorialChecks.ENCOUNTER_STARTED):
			action.effects.append(_set_true(TutorialChecks.ENCOUNTER_STARTED))
	)
	r.layered_map.notify_objects_changed()
	return "The spawn now only happens while encounter_started is no, and the door sets it to yes."


static func _make_group(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var effect := TutorialChecks.door_spawn(mission)
	if effect == null:
		return "Add the door's Spawn Monsters effect first."
	if effect.spawn_group_id != "":
		return "The door already uses a group."
	r.history.record("Make monster group", func():
		var group := MonsterGroup.new()
		group.id = mission.allocate_object_id()
		group.group_name = "Lair guards"
		group.monsters.assign(effect.spawn_monsters)
		effect.spawn_monsters = []
		mission.monster_groups.append(group)
		effect.spawn_group_id = group.id
	)
	r.layered_map.notify_objects_changed()
	return "Made the group \"Lair guards\" and pointed the door's spawn at it."


static func _place_token(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var existing := TutorialChecks.token(mission)
	if existing == null:
		var anchor = _cave_anchor(mission)
		if anchor == null:
			return "This needs the example cave. Place an exploration token on the east path yourself."
		var stage := _shown_stage(mission)
		if stage != null:
			r.controller.set_working_group(stage.id)
		var spot: Vector2i = anchor + TOKEN_SPOT
		if not r.controller.place_mesh_at_tile_square("exploration", Vector3i(spot.x, 0, spot.y)):
			return "The token could not be placed."
		existing = TutorialChecks.token(mission)
	_name_prop(r, existing, "side_passage")
	return "Placed an exploration token on the east path and named it side_passage."


static func _token_action(r: TutorialRunner) -> PropAction:
	var entry := TutorialChecks.token(r.layered_map.mission)
	if entry == null:
		return null
	if entry.actions.is_empty():
		var action := PropAction.new()
		action.action_id = "sneak"
		action.action_name = "Sneak in"
		action.description = "You slip through the side passage, quiet as a mouse."
		r.history.record("Add action", func(): entry.actions.append(action))
	return entry.actions[0]


static func _add_token_action(r: TutorialRunner) -> String:
	var action := _token_action(r)
	if action == null:
		return "Place the token first."
	r.history.record("Edit action", func():
		action.auto_apply = true
		action.single_shot = true
		if not TutorialChecks.mentions(action.conditions, TutorialChecks.ENCOUNTER_STARTED):
			action.conditions.append(_condition_on(TutorialChecks.ENCOUNTER_STARTED, Condition.Operator.EQUALS, false))
	)
	r.layered_map.notify_objects_changed()
	return "The token's action 'Sneak in' fires by itself, once, and only while encounter_started is no."


static func _add_token_effects(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	var stage := TutorialChecks.hidden_stage(mission)
	var door_effect := TutorialChecks.door_spawn(mission)
	var action := _token_action(r)
	if action == null or stage == null or door_effect == null or door_effect.spawn_group_id == "":
		return "Finish the door's spawn (with its group) and place the token first."
	r.history.record("Add effects", func():
		var show := Effect.new()
		show.type = Effect.Type.SHOW_STAGE
		show.target_group_id = stage.id
		var spawn := Effect.new()
		spawn.type = Effect.Type.SPAWN_MONSTERS
		spawn.target_object_id = door_effect.target_object_id
		spawn.spawn_group_id = door_effect.spawn_group_id
		spawn.spawn_unaware = true
		action.effects.append(show)
		action.effects.append(spawn)
		action.effects.append(_set_true(TutorialChecks.ENCOUNTER_STARTED))
	)
	r.layered_map.notify_objects_changed()
	return "The token shows the Lair, spawns the same group unaware, and sets encounter_started."


static func _wake_effect() -> Effect:
	var wake := Effect.new()
	wake.type = Effect.Type.WAKE_MONSTERS
	return wake


static func _add_door_wake(r: TutorialRunner) -> String:
	var action := _door_action(r)
	if action == null:
		return "Place the door first."
	if TutorialChecks.has_effect_type(action.effects, Effect.Type.WAKE_MONSTERS):
		return "The door already wakes monsters."
	r.history.record("Add effect", func(): action.effects.append(_wake_effect()))
	r.layered_map.notify_objects_changed()
	return "The door now wakes any sleeping guards."


static func _add_restless_trigger(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	if TutorialChecks.restless_trigger_ok(mission):
		return "The trigger is already there."
	var trigger := MissionTrigger.new()
	trigger.id = mission.allocate_object_id()
	trigger.checkpoint = RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE
	trigger.one_shot = true
	trigger.conditions.append(_condition_on("round_number", Condition.Operator.GREATER_EQUAL, 5))
	trigger.effects.append(_wake_effect())
	r.history.record("Add trigger", func(): mission.triggers.append(trigger))
	r.layered_map.notify_objects_changed()
	return "Added a trigger: from round 5 on, before the player phase, the sleeping guards wake up."


## The reinforcement trigger as data (tutorial 2, "Reinforcements"): before the monster phase of every third round, while fewer than three monsters are on
## the board, one random monster of the guards' group spawns at the Lair. null when the Lair spawn area or the guards' group is missing.
static func reinforcement_trigger(mission: MissionData) -> MissionTrigger:
	var spawn := TutorialChecks.lair_spawn(mission)
	var door_effect := TutorialChecks.door_spawn(mission)
	if spawn == null or door_effect == null or door_effect.spawn_group_id == "":
		return null
	var trigger := MissionTrigger.new()
	trigger.id = mission.allocate_object_id()
	trigger.checkpoint = RoundCheckpoint.Checkpoint.BEFORE_DARKNESS_PHASE
	trigger.one_shot = false  # a stream: it may fire again every third round
	trigger.conditions.append(_condition_on("round_number", Condition.Operator.MULTIPLE_OF, 3))
	trigger.conditions.append(_condition_on("monsters_on_the_map", Condition.Operator.LESS, 3))
	var spawn_effect := Effect.new()
	spawn_effect.type = Effect.Type.SPAWN_RANDOM_MONSTERS
	spawn_effect.target_object_id = spawn.id
	spawn_effect.spawn_group_id = door_effect.spawn_group_id
	spawn_effect.random_spawn_count = "1"
	trigger.effects.append(spawn_effect)
	return trigger


static func _add_reinforcements(r: TutorialRunner) -> String:
	var mission := r.layered_map.mission
	if TutorialChecks.reinforcements_ok(mission):
		return "The reinforcement trigger is already there."
	var trigger := reinforcement_trigger(mission)
	if trigger == null:
		return "Draw the Lair's spawn area and give the door its guards' group first."
	r.history.record("Add trigger", func(): mission.triggers.append(trigger))
	r.layered_map.notify_objects_changed()
	return "Added a trigger: every third round, while fewer than three monsters are on the board, one random guard spawns in the Lair."
