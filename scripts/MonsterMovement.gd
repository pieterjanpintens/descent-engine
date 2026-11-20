class_name MonsterMovement
extends RefCounted

## Monster movement for a campaign that TRACKS POSITIONS (a campaign option, off by default - branch feature/position-tracking).
## Pure data, no scene nodes: a BOARD is built from the mission as it is on the table now (build_board), and plan() works out what one
## monster does in its activation - who it goes for, where it walks, whether it attacks. Nothing here changes any state: the caller moves
## the token, applies the hazard events and runs the attack.
##
## The rules (agreed with the author 2026-11-17):
## - An activation is TWO ACTIONS: a move and an attack when an attack position can be reached with one move; otherwise two moves and no
##   attack (even when the second move ends in range). A monster that can already attack may still use its move (a ranged one backs away).
## - TARGET: the template's target rules among the heroes it can attack THIS activation; when there is none, among the heroes it can
##   reach at all (else every hero - it then gets as close as it can). A hero next to a barricade wins ties.
## - ATTACK POSITION: the target is within range (melee 1 = touching, also diagonally, and at most one level apart; reach 2; ranged = its
##   range; counted like the line-of-sight tool: one per square, diagonals one, height not counted) and in line of sight (SightLine).
## - IMPEDED (the author, 2026-11-20): ENTERING a square next to a hero (also diagonally, at most one level apart) ends that move - the
##   rest of its points are lost. A monster that ends its first move like that attacks with its second action when a hero is in range.
## - MOVING: its speed in points per move action; a move that starts next to a hero is IMPEDED (1 point). Eight directions, never
##   diagonally between two blocked squares. Not into squares without floor, solid pieces or heroes; other monsters may be passed, not
##   stopped on. Water costs 2 to enter, a ladder up 2, stairs 1, and stepping off an edge to a lower floor 1 (any height).
## - HAZARDS: spikes = 2 damage, impeded, and entering them ends that move; poison = Enfeebled; ember = Doomed + Afflicted. A monster
##   walks around these three and crosses them only when there is no hazard-free route to the target at all.
## - RANGED monsters take the attack position farthest from every hero.
## - LARGE monsters (2x2): one point = choose a square next to the base and put the base anywhere over it, so up to two squares per
##   point; every landing needs room for the whole base, and on a stair the whole base must be on stair squares.
## - A figure NEXT TO A BARRICADE takes +1 damage; an attacker NEXT TO A FIRE does +1. Monsters keep away from barricades and like fires.
##
## Positions are squares (x, height, z) in 0-based game units like MissionSight's; a large monster's position is the corner of its base
## with the lowest x and z.

enum Hazard { NONE, WATER, SPIKES, POISON, EMBER }

const HAZARD_OF_MESH := {"water": Hazard.WATER, "spikes": Hazard.SPIKES, "acid": Hazard.POISON, "lava": Hazard.EMBER}
const WATER_COST := 2
const LADDER_UP_COST := 2
const SPIKE_DAMAGE := 2
const IMPEDED_POINTS := 1
const MELEE_RANGE := 1
const REACH_RANGE := 2
const LARGE_SIZE := 2
const BARRICADE_MESH := "barricade"
const FIRE_MESH := "fire"
const FAR := 1 << 20
## Activation abilities that make a monster FLY: while moving it ignores elevation, terrain and underlays and cannot be impeded.
const FLYING_KEYS := ["ENEMY_ACTIVATION_FAE_BASIC", "ENEMY_ACTIVATION_HARBINGER_VANGUARD"]
## Tactics (activation key part) during which the monster cannot be impeded: the Wight's Blade Sweep. The dragons' Trample can't be
## impeded either, but no dragon has a figure.
const UNIMPEDED_TACTICS := ["WIGHT_TACTIC_BLADE_SWEEP"]


## The tactic with this activation key moves without being impeded (pass {"unimpeded": true} in plan()'s stats).
static func tactic_unimpeded(activation_key: String) -> bool:
	for part: String in UNIMPEDED_TACTICS:
		if activation_key.contains(part):
			return true
	return false


# ---------------------------------------------------------------- the board

## Everything movement needs to know about the mission as it is on the table: {"sight" (SightLine context), "squares" {square: true}
## (floor, stairs included), "blocked" {square: true} (a solid piece stands there), "room" {square: free height above it}, "stairs",
## "hazard" {square: Hazard}, "links" {square: Array of {"to", "cost"}} (stairs and ladders), "columns" {Vector2i: Array of heights},
## "near_barricade" / "near_fire" {square: true}}. Only revealed pieces count (and not those a running stage reveal still holds back).
static func build_board(mission: MissionData, held_back: Dictionary = {}) -> Dictionary:
	var data := MissionSight.build(mission, held_back)
	var sight: Dictionary = data["sight"]
	var squares: Dictionary = (data["squares"] as Dictionary).duplicate()
	var props: Array[InteractableEntry] = []
	for entry in mission.interactables:
		if not held_back.has(entry) and mission.is_effectively_visible(entry):
			props.append(entry)

	var ceilings: Dictionary = {}  # Vector2i fine column -> Array[int] heights of floors / archway tops
	var floors: Dictionary = sight["floors"]
	for height: int in floors:
		for cell: Vector2i in floors[height]:
			_add_ceiling(ceilings, cell, height)

	var stairs: Dictionary = {}
	var solid_fine: Dictionary = {}  # Vector3i fine cell (x, height, z) -> true
	var barricades: Dictionary = {}
	var fires: Dictionary = {}
	var gates: Dictionary = {}
	var trees: Dictionary = {}
	var pillars: Dictionary = {}
	for entry in props:
		var mesh := entry.mesh_item_name
		var base: int = entry.origin_cell.y
		var cells := MissionSight.cells_of(entry)
		if mesh == "stair" or BuildRules.is_bridge(mesh):
			# a stair is walked on, also when it stands on bare ground; a bridge is two stairs placed against each other
			for cell in cells:
				var stair_square := _square_of(cell, base)
				squares[stair_square] = true
				stairs[stair_square] = true
		# a statue's spaces are walked on like stair squares (level 1 at its base height, which is then not solid there)
		var raised := BuildRules.raised_squares(mesh, entry.origin_cell, cells)
		var open: Dictionary = {}
		for raised_square: Vector3i in raised:
			squares[raised_square] = true
			stairs[raised_square] = true
			if raised_square.y == base:
				open[Vector2i(raised_square.x, raised_square.z)] = true
		for cell in BuildRules.solid_cells_from_footprint(mesh, cells):
			if not open.has(Vector2i(floori(float(cell.x) / FootprintRegistry.CELLS_PER_TILE), floori(float(cell.z) / FootprintRegistry.CELLS_PER_TILE))):
				solid_fine[Vector3i(cell.x, base, cell.z)] = true
		if BuildRules.CEILING_RISES.has(mesh):
			for cell in cells:
				_add_ceiling(ceilings, Vector2i(cell.x, cell.z), base + int(BuildRules.CEILING_RISES[mesh]))
		if mesh == BARRICADE_MESH:
			for cell in cells:
				barricades[_square_of(cell, base)] = true
		elif mesh == FIRE_MESH:
			for cell in cells:
				fires[_square_of(cell, base)] = true
		var heads_for: Variant = gates if mesh == "gate" else (trees if mesh == "tree" else (pillars if ["tall", "medium", "mini"].has(mesh) else null))
		if heads_for != null:
			for cell in cells:
				(heads_for as Dictionary)[_square_of(cell, base)] = true

	# a square is blocked when solid pieces cover at least half of it (a pillar on the corner between four squares leaves them free)
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var solid_count: Dictionary = {}
	for fine: Vector3i in solid_fine:
		var covered := _square_of(fine, fine.y)
		solid_count[covered] = int(solid_count.get(covered, 0)) + 1
	var blocked: Dictionary = {}
	for covered: Vector3i in solid_count:
		if int(solid_count[covered]) * 2 >= cpt * cpt:
			blocked[covered] = true
			# a piece standing on top of a stair, a bridge or a statue space (a door at the top of a stair, on the middle of a bridge) is placed
			# one level up in the editor: it blocks the stair square under it
			var under := covered - Vector3i(0, 1, 0)
			if not squares.has(covered) and stairs.has(under):
				blocked[under] = true

	# hazards show where no floor tile lies over the hazard card
	var floor_fine: Dictionary = {}
	var floor_origins: Dictionary = {}
	for placement in mission.floor_placements:
		if not held_back.has(placement) and mission.is_effectively_visible(placement):
			floor_origins[placement.origin_cell] = true
	for fine: Vector3i in mission.floor_occupied_cells:
		if floor_origins.has(mission.floor_occupied_cells[fine]):
			floor_fine[fine] = true
	var hazard_origins: Dictionary = {}  # origin cell -> Hazard
	for placement in mission.underlay_placements:
		if not held_back.has(placement) and mission.is_effectively_visible(placement):
			hazard_origins[placement.origin_cell] = int(HAZARD_OF_MESH.get(placement.mesh_item_name, Hazard.NONE))
	var hazard: Dictionary = {}
	for fine: Vector3i in mission.underlay_occupied_cells:
		var origin: Vector3i = mission.underlay_occupied_cells[fine]
		if not hazard_origins.has(origin) or floor_fine.has(fine):
			continue
		var kind: int = hazard_origins[origin]
		var hazard_square := _square_of(fine, fine.y)
		if stairs.has(hazard_square):
			continue  # on a stair or a bridge over the hazard card a figure is not in it
		if kind != Hazard.NONE and squares.has(hazard_square) and kind > int(hazard.get(hazard_square, Hazard.NONE)):
			hazard[hazard_square] = kind

	var room: Dictionary = {}
	var columns: Dictionary = {}
	for square: Vector3i in squares:
		var free := FAR
		for dx in cpt:
			for dz in cpt:
				for ceiling: int in ceilings.get(Vector2i(square.x * cpt + dx, square.z * cpt + dz), []):
					if ceiling > square.y:
						free = mini(free, ceiling - square.y)
		room[square] = free
		var column := Vector2i(square.x, square.z)
		if not columns.has(column):
			columns[column] = []
		columns[column].append(square.y)

	var links: Dictionary = {}
	for link: Array in MissionSight.step_links(props, squares):
		var lower: Vector3i = link[0]
		var upper: Vector3i = link[1]
		_add_link(links, lower, upper, LADDER_UP_COST if str(link[2]) == "ladder" else 1)
		_add_link(links, upper, lower, 1)

	return {
		"sight": sight, "squares": squares, "blocked": blocked, "room": room, "stairs": stairs, "hazard": hazard,
		"links": links, "columns": columns, "near_barricade": _around(barricades), "near_fire": _around(fires),
		"near_gate": _around(gates), "near_tree": _around(trees), "near_pillar": _around(pillars),
	}


static func _square_of(fine: Vector3i, height: int) -> Vector3i:
	var cpt := FootprintRegistry.CELLS_PER_TILE
	return Vector3i(floori(float(fine.x) / cpt), height, floori(float(fine.z) / cpt))


static func _add_ceiling(ceilings: Dictionary, column: Vector2i, height: int) -> void:
	if not ceilings.has(column):
		ceilings[column] = []
	ceilings[column].append(height)


static func _add_link(links: Dictionary, from: Vector3i, to: Vector3i, cost: int) -> void:
	if not links.has(from):
		links[from] = []
	links[from].append({"to": to, "cost": cost})


## The squares touching any of `pieces` (the pieces' own squares included).
static func _around(pieces: Dictionary) -> Dictionary:
	var near: Dictionary = {}
	for square: Vector3i in pieces:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				near[Vector3i(square.x + dx, square.y, square.z + dz)] = true
	return near


# ---------------------------------------------------------------- questions about a position

## The squares a figure of `size` (1, or 2 for a large monster) covers with its position on `anchor`.
static func block(anchor: Vector3i, size: int) -> Array[Vector3i]:
	var covered: Array[Vector3i] = []
	for dx in size:
		for dz in size:
			covered.append(Vector3i(anchor.x + dx, anchor.y, anchor.z + dz))
	return covered


## Whether a figure of `size` may be put on `anchor` at all: floor under all of it, no solid piece, enough headroom, and none of the
## `occupied` squares ({square: anything} - the other figures). For the table dragging a token.
static func can_place(board: Dictionary, anchor: Vector3i, size: int, occupied: Dictionary = {}) -> bool:
	var ctx := {"board": board, "size": size, "hero_squares": occupied, "monster_squares": {}}
	return _can_stop(ctx, anchor)


## +1 for an attacker standing next to a fire, +1 for a defender standing next to a barricade (`attacker` / `defender`: the squares each
## covers). The same for heroes and monsters.
static func damage_bonus(board: Dictionary, attacker: Array[Vector3i], defender: Array[Vector3i]) -> int:
	return (1 if _any_in(attacker, board["near_fire"]) else 0) + (1 if _any_in(defender, board["near_barricade"]) else 0)


static func _any_in(squares: Array[Vector3i], lookup: Dictionary) -> bool:
	for square in squares:
		if lookup.has(square):
			return true
	return false


## The monster flies (one of FLYING_KEYS among its activation abilities).
static func is_flying(monster: RuntimeMonster) -> bool:
	for ability in monster.attack_abilities:
		if FLYING_KEYS.has(ability.game_key):
			return true
	return false


static func _need(size: int) -> int:
	return BuildRules.CENTAUR_HEIGHT if size > 1 else BuildRules.FIGURE_HEIGHT


## A square as the board knows it: a spawn tile drawn on a bridge's deck (one unit up) becomes the bridge square under it.
static func settle(board: Dictionary, square: Vector3i) -> Vector3i:
	var below := square - Vector3i(0, 1, 0)
	if not board["squares"].has(square) and board["stairs"].has(below):
		return below
	return square


## One square: floor, no solid piece, no hero.
static func _open(ctx: Dictionary, square: Vector3i) -> bool:
	var board: Dictionary = ctx["board"]
	return board["squares"].has(square) and not board["blocked"].has(square) and not ctx["hero_squares"].has(square)


## The figure may be on `anchor` while moving (other monsters do not stop it).
static func _can_pass(ctx: Dictionary, anchor: Vector3i) -> bool:
	var board: Dictionary = ctx["board"]
	if ctx.get("flying", false):
		for square in block(anchor, ctx["size"]):
			if not board["squares"].has(square) or ctx["hero_squares"].has(square):
				return false
		return true
	var need := _need(ctx["size"])
	var size: int = ctx["size"]
	var on_stairs := 0
	for square in block(anchor, size):
		if not _open(ctx, square):
			return false
		if board["stairs"].has(square):
			on_stairs += 1
		elif int(board["room"].get(square, FAR)) < need:
			return false
	# a large figure on a stair stands on it with its whole base (the steps' own height differences do not matter)
	return on_stairs == 0 or on_stairs == size * size


## The figure may END a move on `anchor`: room for all of it, no other monster, and not on a stair step that lies under a floor.
static func _can_stop(ctx: Dictionary, anchor: Vector3i) -> bool:
	if not _can_pass(ctx, anchor):
		return false
	var board: Dictionary = ctx["board"]
	var need := _need(ctx["size"])
	for square in block(anchor, ctx["size"]):
		if ctx["monster_squares"].has(square) or int(board["room"].get(square, FAR)) < need:
			return false
	return true


## The worst hazard under a figure on `anchor`.
static func _hazard_at(ctx: Dictionary, anchor: Vector3i) -> int:
	if ctx.get("flying", false):
		return Hazard.NONE  # a flying monster ignores the underlays
	var hazards: Dictionary = ctx["board"]["hazard"]
	var worst: int = Hazard.NONE
	for square in block(anchor, ctx["size"]):
		worst = maxi(worst, int(hazards.get(square, Hazard.NONE)))
	return worst


static func _is_bad(hazard: int) -> bool:
	return hazard == Hazard.SPIKES or hazard == Hazard.POISON or hazard == Hazard.EMBER


## What one step out of `from` costs: moving OUT of a water space costs one extra point (the game's rule), everything else 1.
static func _step_cost(board: Dictionary, from: Vector3i) -> int:
	return WATER_COST if int(board["hazard"].get(from, Hazard.NONE)) == Hazard.WATER else 1


## A figure on `anchor` touches a hero (also diagonally, at most one level apart).
static func _next_to_hero(ctx: Dictionary, anchor: Vector3i) -> bool:
	for square in block(anchor, ctx["size"]):
		for hero: Vector3i in ctx["hero_squares"]:
			if absi(hero.x - square.x) <= 1 and absi(hero.z - square.z) <= 1 and absi(hero.y - square.y) <= 1:
				return true
	return false


## Entering `anchor` ends the move: the figure can be impeded (not flying, not a shift) and touches a hero there.
static func _impeded_at(ctx: Dictionary, anchor: Vector3i) -> bool:
	return ctx.get("impede", false) and not ctx.get("flying", false) and _next_to_hero(ctx, anchor)


## The movement points of a move action that starts on `anchor`.
static func _action_points(ctx: Dictionary, anchor: Vector3i, speed: int) -> int:
	if speed <= 0:
		return 0
	if ctx.get("flying", false) or not ctx.get("impede", true):
		return speed  # cannot be impeded
	return mini(speed, IMPEDED_POINTS) if _next_to_hero(ctx, anchor) else speed


# ---------------------------------------------------------------- steps and routes

## The single steps out of ONE square: to the eight squares around it at the same height, down from an edge, and along stairs / ladders.
## Array of {"to": square, "cost": points}.
static func _square_steps(ctx: Dictionary, from: Vector3i) -> Array:
	var board: Dictionary = ctx["board"]
	var steps: Array = []
	if ctx.get("flying", false):
		# flying: to any floor of the eight columns around, at any height (elevation and terrain do not matter), 1 point each
		for step: Vector2i in MissionSight.STEPS_8:
			var column := Vector2i(from.x + step.x, from.z + step.y)
			for height: int in board["columns"].get(column, []):
				var to := Vector3i(column.x, height, column.y)
				if not ctx["hero_squares"].has(to):
					steps.append({"to": to, "cost": 1})
		return steps
	for step: Vector2i in MissionSight.STEPS_8:
		var level := Vector3i(from.x + step.x, from.y, from.z + step.y)
		if board["squares"].has(level):
			if not _open(ctx, level):
				continue
			# the game's rule: figures can move diagonally between two spaces that contain 3D terrain
			steps.append({"to": level, "cost": _step_cost(board, from)})
			continue
		# no floor at this height there: step off the edge onto the highest floor below
		var landing := -1
		for height: int in board["columns"].get(Vector2i(level.x, level.z), []):
			if height < from.y and height > landing and _open(ctx, Vector3i(level.x, height, level.z)):
				landing = height
		if landing >= 0:
			var below := Vector3i(level.x, landing, level.z)
			steps.append({"to": below, "cost": _step_cost(board, from)})
	for link: Dictionary in board["links"].get(from, []):
		var to: Vector3i = link["to"]
		if _open(ctx, to):
			steps.append({"to": to, "cost": maxi(int(link["cost"]), _step_cost(board, from))})
	return steps


## Where a figure on `anchor` can be after ONE step, with what it costs. A large figure chooses a square next to its base and lands
## anywhere over it.
static func _moves(ctx: Dictionary, anchor: Vector3i) -> Array:
	var size: int = ctx["size"]
	var cheapest: Dictionary = {}
	if size <= 1:
		for step: Dictionary in _square_steps(ctx, anchor):
			var to: Vector3i = step["to"]
			if _can_pass(ctx, to):
				cheapest[to] = mini(int(step["cost"]), int(cheapest.get(to, FAR)))
	else:
		var base := block(anchor, size)
		for square in base:
			for step: Dictionary in _square_steps(ctx, square):
				var chosen: Vector3i = step["to"]
				if base.has(chosen):
					continue
				for dx in size:
					for dz in size:
						var landing := Vector3i(chosen.x - dx, chosen.y, chosen.z - dz)
						if landing != anchor and _can_pass(ctx, landing):
							cheapest[landing] = mini(int(step["cost"]), int(cheapest.get(landing, FAR)))
	var moves: Array = []
	for to: Vector3i in cheapest:
		moves.append({"to": to, "cost": cheapest[to]})
	return moves


## The cheapest way from `start` to every position within `budget` points: {position: {"cost", "from", "step"}}. Without `allow_bad`
## spikes, poison and ember are never entered; with `one_move` a route ends where it enters spikes or, when ctx["impede"], a square next to
## a hero (both end the move).
static func _reach(ctx: Dictionary, start: Vector3i, budget: int, allow_bad: bool, one_move: bool) -> Dictionary:
	var best: Dictionary = {start: {"cost": 0, "from": start, "step": 0}}
	var open: Array[Vector3i] = [start]
	var done: Dictionary = {}
	while not open.is_empty():
		var pick := 0
		for i in open.size():
			if int(best[open[i]]["cost"]) < int(best[open[pick]]["cost"]):
				pick = i
		var current: Vector3i = open[pick]
		open.remove_at(pick)
		if done.has(current):
			continue
		done[current] = true
		if one_move and current != start and (_hazard_at(ctx, current) == Hazard.SPIKES or _impeded_at(ctx, current)):
			continue
		var cost_here: int = best[current]["cost"]
		for move: Dictionary in _moves(ctx, current):
			var to: Vector3i = move["to"]
			if done.has(to) or (not allow_bad and _is_bad(_hazard_at(ctx, to))):
				continue
			var total := cost_here + int(move["cost"])
			if total > budget:
				continue
			if not best.has(to) or total < int(best[to]["cost"]):
				best[to] = {"cost": total, "from": current, "step": int(move["cost"])}
				open.append(to)
	return best


## The route to `to` out of a _reach() result: Array of {"pos", "cost" (of the step into it)}, the start first.
static func _route(reach: Dictionary, to: Vector3i) -> Array:
	var route: Array = []
	var current := to
	while true:
		var entry: Dictionary = reach[current]
		route.push_front({"pos": current, "cost": int(entry["step"])})
		var from: Vector3i = entry["from"]
		if from == current:
			break
		current = from
	return route


## The positions a figure can attack a hero on `hero_square` from: {position: true}. `distance` = MissionSight.routes() from the hero.
static func _attack_positions(ctx: Dictionary, hero_square: Vector3i, attack_range: int, distance: Dictionary) -> Dictionary:
	var board: Dictionary = ctx["board"]
	var size: int = ctx["size"]
	var hero_column := Vector2i(hero_square.x, hero_square.z)
	var positions: Dictionary = {}
	for square: Vector3i in distance:
		var steps: int = distance[square]
		if steps < 1 or steps > attack_range or square == hero_square or not board["squares"].has(square):
			continue
		if attack_range <= MELEE_RANGE and absi(square.y - hero_square.y) > 1:
			continue
		if not SightLine.can_see(board["sight"], Vector2i(square.x, square.z), square.y, hero_column, hero_square.y):
			continue
		for dx in size:
			for dz in size:
				positions[Vector3i(square.x - dx, square.y, square.z - dz)] = true
	return positions


## The heroes (slots) a figure on `position` can attack WITHOUT moving (a second attack after the first, Bloodlust...).
static func attackable_from(board: Dictionary, monster: RuntimeMonster, position: Vector3i, size: int, heroes: Dictionary) -> Array[int]:
	var ranged := monster.effective_attack_range() > 0
	var attack_range := monster.effective_attack_range() if ranged else (REACH_RANGE if monster.attack_reach else MELEE_RANGE)
	var ctx := {"board": board, "size": size}
	var slots: Array[int] = []
	for slot: int in heroes:
		var distance := MissionSight.routes({"squares": board["squares"]}, heroes[slot])
		if _attack_positions(ctx, heroes[slot], attack_range, distance).has(position):
			slots.append(slot)
	return slots


# ---------------------------------------------------------------- confused moves

## Where a Confused monster goes for a built-in action (MonsterAction.builtin_kind()), in ONE move of up to its speed; it never walks
## into spikes, poison or ember. "retreat" = as far from the heroes as it can, "wander" = a random square, "lunge" = towards the nearest
## hero (no attack), "gate" / "tree" / "cover" = towards the nearest gate / tree / pillar. Returns {"path", "end", "events", "note"};
## any other kind stays put.
static func confused_move(board: Dictionary, monster: RuntimeMonster, position: Vector3i, size: int, heroes: Dictionary, others: Array, kind: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var start_path: Array[Vector3i] = [position]
	var result := {"path": start_path, "end": position, "moves": 0, "events": [], "note": ""}
	var hero_squares: Dictionary = {}
	for slot: int in heroes:
		hero_squares[heroes[slot]] = slot
	var monster_squares: Dictionary = {}
	for other: Dictionary in others:
		for square in block(other["square"], int(other.get("size", 1))):
			monster_squares[square] = true
	var ctx := {"board": board, "size": size, "hero_squares": hero_squares, "monster_squares": monster_squares, "flying": is_flying(monster), "impede": true}
	var points := _action_points(ctx, position, maxi(monster.effective_speed(), 0))
	if points <= 0:
		result["note"] = "it has no speed"
		return result
	var within := _reach(ctx, position, points, false, true)
	var stops: Array[Vector3i] = []
	for spot: Vector3i in within:
		if spot != position and _can_stop(ctx, spot):
			stops.append(spot)
	match kind:
		"retreat":
			var distance_of: Dictionary = {}
			for slot: int in heroes:
				distance_of[slot] = MissionSight.routes({"squares": board["squares"]}, heroes[slot])
			var best := position
			var best_score: Array = [_distance_to_heroes(distance_of, position, size), 0]
			for spot in stops:
				var score: Array = [_distance_to_heroes(distance_of, spot, size), -int(within[spot]["cost"])]
				if _beats(score, best_score):
					best = spot
					best_score = score
			if best != position:
				_fill(result, ctx, _route(within, best), _route(within, best).size() - 1, 1)
		"wander":
			if not stops.is_empty():
				var spot := _pick(stops, rng)
				_fill(result, ctx, _route(within, spot), _route(within, spot).size() - 1, 1)
		"lunge", "gate", "tree", "cover":
			var goal: Dictionary = _around(hero_squares) if kind == "lunge" else board.get({"gate": "near_gate", "tree": "near_tree", "cover": "near_pillar"}[kind], {})
			if _any_in(block(position, size), goal):
				result["note"] = "it is already there"
				return result
			var far := _reach(ctx, position, FAR, false, false)
			var target := position
			var lowest := FAR
			for spot: Vector3i in far:
				if spot != position and _can_stop(ctx, spot) and _any_in(block(spot, size), goal) and int(far[spot]["cost"]) < lowest:
					lowest = int(far[spot]["cost"])
					target = spot
			if target == position:
				result["note"] = "it cannot get there"
				return result
			var route := _route(far, target)
			var index := 0
			var left := points
			while index < route.size() - 1 and int(route[index + 1]["cost"]) <= left:
				index += 1
				left -= int(route[index]["cost"])
				if _impeded_at(ctx, route[index]["pos"]):
					break
			while index > 0 and not _can_stop(ctx, route[index]["pos"]):
				index -= 1
			if index > 0:
				_fill(result, ctx, route, index, 1)
	return result


## A SHIFT (the game's keyword): an ordinary move of up to `points` movement points (water and ladders cost what they always cost), but
## never cut short by being next to a hero. It moves as far from (`away`) or as close to the `target` squares as it can, never into
## spikes, poison or ember and never ending on another figure. Returns {"path", "end"}; end == position when it stays put.
static func shift(board: Dictionary, position: Vector3i, size: int, points: int, target: Array[Vector3i], away: bool, heroes: Dictionary, others: Array) -> Dictionary:
	var start_path: Array[Vector3i] = [position]
	var result := {"path": start_path, "end": position}
	if points <= 0 or target.is_empty():
		return result
	var hero_squares: Dictionary = {}
	for slot: int in heroes:
		hero_squares[heroes[slot]] = slot
	var monster_squares: Dictionary = {}
	for other: Dictionary in others:
		for square in block(other["square"], int(other.get("size", 1))):
			monster_squares[square] = true
	var ctx := {"board": board, "size": size, "hero_squares": hero_squares, "monster_squares": monster_squares}
	var within := _reach(ctx, position, points, false, true)
	var distance := {}
	for square in target:
		var from_here := MissionSight.routes({"squares": board["squares"]}, square)
		for key: Vector3i in from_here:
			distance[key] = mini(int(distance.get(key, FAR)), int(from_here[key]))
	var best := position
	var best_score: Array = [_steps_to(distance, position, size) * (1 if away else -1), 0]
	for spot: Vector3i in within:
		if spot == position or not _can_stop(ctx, spot):
			continue
		var score: Array = [_steps_to(distance, spot, size) * (1 if away else -1), -int(within[spot]["cost"])]
		if _beats(score, best_score):
			best = spot
			best_score = score
	if best != position:
		var path: Array[Vector3i] = []
		for step: Dictionary in _route(within, best):
			path.append(step["pos"])
		result["path"] = path
		result["end"] = best
	return result


## LEAP (Harbinger "Prey on the Weak"): the free position touching `hero_square` (also diagonally, at most one level apart) nearest to
## where the monster stands now; null when there is none.
static func leap_spot(board: Dictionary, position: Vector3i, size: int, hero_square: Vector3i, occupied: Dictionary) -> Variant:
	var best: Variant = null
	var best_distance := INF
	for dx in range(-size, 2):
		for dz in range(-size, 2):
			for dy in range(-1, 2):
				var anchor := Vector3i(hero_square.x + dx, hero_square.y + dy, hero_square.z + dz)
				if block(anchor, size).has(hero_square) or not can_place(board, anchor, size, occupied):
					continue
				var distance := Vector3(anchor - position).length()
				if distance < best_distance:
					best_distance = distance
					best = anchor
	return best


## The other monster nearest to a figure of `size` on `position` (steps over the floor), or null. `others`: Array of RuntimeMonster.
static func nearest_monster(board: Dictionary, position: Vector3i, size: int, others: Array) -> RuntimeMonster:
	var distance := {}
	for square in block(position, size):
		var from_here := MissionSight.routes({"squares": board["squares"]}, square)
		for key: Vector3i in from_here:
			distance[key] = mini(int(distance.get(key, FAR)), int(from_here[key]))
	var nearest: RuntimeMonster = null
	var fewest := FAR
	for other: RuntimeMonster in others:
		var steps := _steps_to(distance, other.position, other.size)
		if steps < fewest:
			fewest = steps
			nearest = other
	return nearest


# ---------------------------------------------------------------- one activation

## What `monster` (on `position`, covering `size` x `size` squares) does in its activation.
## `heroes`: {hero slot: square}. `others`: the other monsters as Array of {"square", "size"}. `context`: MonsterTargeting's context
## (weapons, attacks_made, times_targeted, wounds); the distances and the barricade preference are added here.
## Returns {"target" (hero slot, -1 none), "attack" (bool), "path" (Array[Vector3i] of positions, the start first), "end", "moves"
## (move actions used: 0, 1 or 2), "events" (Array of {"square", "hazard"}: the hazards it walks into, in order), "damage_bonus"
## (fire / barricade, when it attacks), "note" (why it does nothing, for the log)}.
## `stats` overrides the monster's own numbers for a tactic: {"speed", "range" (0 = melee), "reach"}.
static func plan(board: Dictionary, monster: RuntimeMonster, position: Vector3i, size: int, heroes: Dictionary, others: Array, context: Dictionary = {}, rng: RandomNumberGenerator = null, stats: Dictionary = {}) -> Dictionary:
	var start_path: Array[Vector3i] = [position]
	var result := {"target": -1, "attack": false, "path": start_path, "end": position, "moves": 0, "events": [], "damage_bonus": 0, "note": ""}
	if heroes.is_empty():
		result["note"] = "no heroes on the board"
		return result
	var hero_squares: Dictionary = {}
	for slot: int in heroes:
		hero_squares[heroes[slot]] = slot
	var monster_squares: Dictionary = {}
	for other: Dictionary in others:
		for square in block(other["square"], int(other.get("size", 1))):
			monster_squares[square] = true
	var ctx := {"board": board, "size": size, "hero_squares": hero_squares, "monster_squares": monster_squares, "flying": is_flying(monster), "impede": not bool(stats.get("unimpeded", false))}

	var speed := maxi(int(stats.get("speed", monster.effective_speed())), 0)
	var own_range := int(stats.get("range", monster.effective_attack_range()))
	var ranged := own_range > 0
	var attack_range := own_range if ranged else (REACH_RANGE if bool(stats.get("reach", monster.attack_reach)) else MELEE_RANGE)
	var points := _action_points(ctx, position, speed)
	var move_safe := _reach(ctx, position, points, false, true)
	var move_any := _reach(ctx, position, points, true, true)
	var far_safe := _reach(ctx, position, FAR, false, false)
	var far_any := _reach(ctx, position, FAR, true, false)

	var distance_of: Dictionary = {}  # slot -> {square: steps from the hero}
	var spots_of: Dictionary = {}     # slot -> {position: true} it could attack the hero from
	var now_of: Dictionary = {}       # slot -> Array[Vector3i] attack positions it can reach with one move
	var now: Array[int] = []
	var reachable: Array[int] = []
	var everyone: Array[int] = []
	var nearness: Dictionary = {}
	var prefer: Array[int] = []
	for slot: int in heroes:
		everyone.append(slot)
		var hero_square: Vector3i = heroes[slot]
		var distance := MissionSight.routes({"squares": board["squares"]}, hero_square)
		distance_of[slot] = distance
		var spots := _attack_positions(ctx, hero_square, attack_range, distance)
		spots_of[slot] = spots
		var safe_way := _shares_key(spots, far_safe)
		var any_way := safe_way or _shares_key(spots, far_any)
		if any_way:
			reachable.append(slot)
		# a monster walks into spikes, poison or ember only when no clean route leads to this hero
		var within: Dictionary = move_safe if safe_way else move_any
		var found: Array[Vector3i] = []
		for spot: Vector3i in spots:
			if within.has(spot) and (spot == position or _can_stop(ctx, spot)):
				found.append(spot)
		if not found.is_empty():
			now.append(slot)
			now_of[slot] = found
		var cheapest := FAR
		for spot: Vector3i in spots:
			if far_any.has(spot):
				cheapest = mini(cheapest, int(far_any[spot]["cost"]))
		nearness[slot] = cheapest if cheapest < FAR else FAR / 2 + _steps_to(distance, position, size)
		if board["near_barricade"].has(hero_square):
			prefer.append(slot)
	var targeting := context.duplicate()
	targeting["distances"] = nearness
	targeting["prefer"] = prefer

	if not now.is_empty():
		# move (when that helps) and attack
		var target := MonsterTargeting.choose_target(monster, now, targeting, rng)
		var within: Dictionary = move_safe if _shares_key(spots_of[target], far_safe) else move_any
		var best: Array[Vector3i] = []
		var best_score: Array = []
		for spot: Vector3i in now_of[target]:
			var score: Array = []
			if ranged:
				score.append(_distance_to_heroes(distance_of, spot, size))
			var covered := block(spot, size)
			score.append(0 if _any_in(covered, board["near_barricade"]) else 1)
			score.append(1 if _any_in(covered, board["near_fire"]) else 0)
			score.append(-int(within[spot]["cost"]))
			if best.is_empty() or _beats(score, best_score):
				best = [spot]
				best_score = score
			elif score == best_score:
				best.append(spot)
		var chosen := _pick(best, rng)
		var route := _route(within, chosen)
		result["target"] = target
		result["attack"] = true
		_fill(result, ctx, route, route.size() - 1, 1 if route.size() > 1 else 0)
		var target_square: Array[Vector3i] = [heroes[target]]
		result["damage_bonus"] = damage_bonus(board, block(chosen, size), target_square)
		return result

	# no attack this activation: two moves towards the target
	var goal := MonsterTargeting.choose_target(monster, reachable if not reachable.is_empty() else everyone, targeting, rng)
	result["target"] = goal
	var far: Dictionary = far_safe
	var destination := position
	if reachable.has(goal):
		if not _shares_key(spots_of[goal], far_safe):
			far = far_any
		var lowest := FAR
		for spot: Vector3i in spots_of[goal]:
			if far.has(spot) and int(far[spot]["cost"]) < lowest:
				lowest = int(far[spot]["cost"])
				destination = spot
	else:
		# no way to an attack position (a closed gate...): as close to the hero as it can get
		var closest := _steps_to(distance_of[goal], position, size)
		var lowest := 0
		for spot: Vector3i in far_safe:
			var steps := _steps_to(distance_of[goal], spot, size)
			var cost: int = far_safe[spot]["cost"]
			if steps < closest or (steps == closest and cost < lowest):
				closest = steps
				lowest = cost
				destination = spot
		if destination == position:
			result["note"] = "cannot get any closer"
	if speed <= 0:
		result["note"] = "it has no speed"
		return result
	if destination == position:
		return result
	var route := _route(far, destination)
	var index := 0
	var moves := 0
	var spiked := false
	for action in 2:
		if index >= route.size() - 1:
			break
		var left := IMPEDED_POINTS if spiked else _action_points(ctx, route[index]["pos"], speed)
		var moved := false
		var impeded := false
		while index < route.size() - 1 and int(route[index + 1]["cost"]) <= left:
			index += 1
			left -= int(route[index]["cost"])
			moved = true
			if _hazard_at(ctx, route[index]["pos"]) == Hazard.SPIKES:
				spiked = true
				break
			if _impeded_at(ctx, route[index]["pos"]):
				impeded = true  # entering a square next to a hero ends the move
				break
		if not moved:
			break
		moves += 1
		if action == 0 and impeded and _can_stop(ctx, route[index]["pos"]):
			# impeded after the first move: the second action is an attack when a hero is in range now
			var here: Vector3i = route[index]["pos"]
			var in_range: Array[int] = []
			for slot: int in spots_of:
				if (spots_of[slot] as Dictionary).has(here):
					in_range.append(slot)
			if not in_range.is_empty():
				var target := MonsterTargeting.choose_target(monster, in_range, targeting, rng)
				result["target"] = target
				result["attack"] = true
				_fill(result, ctx, route, index, 1)
				var target_square: Array[Vector3i] = [heroes[target]]
				result["damage_bonus"] = damage_bonus(board, block(here, size), target_square)
				return result
	while index > 0 and not _can_stop(ctx, route[index]["pos"]):
		index -= 1  # it may not end on another monster: stop one earlier
	_fill(result, ctx, route, index, moves if index > 0 else 0)
	return result


## Writes the walked part of `route` (up to `last`) into `result`.
static func _fill(result: Dictionary, ctx: Dictionary, route: Array, last: int, moves: int) -> void:
	var path: Array[Vector3i] = []
	var events: Array = []
	for i in last + 1:
		var spot: Vector3i = route[i]["pos"]
		path.append(spot)
		if i > 0 and _is_bad(_hazard_at(ctx, spot)):
			events.append({"square": spot, "hazard": _hazard_at(ctx, spot)})
	result["path"] = path
	result["end"] = path[path.size() - 1]
	result["moves"] = moves
	result["events"] = events


static func _shares_key(a: Dictionary, b: Dictionary) -> bool:
	for key: Variant in a:
		if b.has(key):
			return true
	return false


## The fewest steps from a hero (whose routes() result is `distance`) to a figure on `anchor`.
static func _steps_to(distance: Dictionary, anchor: Vector3i, size: int) -> int:
	var fewest := FAR / 4
	for square in block(anchor, size):
		fewest = mini(fewest, int(distance.get(square, FAR / 4)))
	return fewest


## How far a figure on `anchor` is from the nearest hero.
static func _distance_to_heroes(distance_of: Dictionary, anchor: Vector3i, size: int) -> int:
	var nearest := FAR
	for slot: int in distance_of:
		nearest = mini(nearest, _steps_to(distance_of[slot], anchor, size))
	return nearest


## True when score `a` is better than `b` (both lists of numbers, the first difference decides, higher wins).
static func _beats(a: Array, b: Array) -> bool:
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return int(a[i]) > int(b[i])
	return false


static func _pick(options: Array[Vector3i], rng: RandomNumberGenerator) -> Vector3i:
	var index := rng.randi_range(0, options.size() - 1) if rng != null else randi() % options.size()
	return options[index]
