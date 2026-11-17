class_name BuildRules
extends RefCounted

## The HARD-CODED rules of how pieces fit together in three dimensions (given by the author 2026-10-21, checked against the mesh heights:
## one height unit is about 3.6 mesh units - stair 3.4, mini pillar 4.6, medium 8.0, tall 13.8, gate 9.95). Never instantiated.
## MapPlanValidator reads this table, and whatever generates map plans (later: an AI) is handed `describe()`, so the rules live in ONE place.
##
## HEIGHT UNITS. The map is a 3D grid: every game unit (tile square) has a column of height units. A floor tile has no thickness; a floor "at
## height h" is a walking surface h units above the ground (h = 0 is the ground). A piece standing on a floor at height b has its
## top at b + its own rise, so every number below is RELATIVE to the floor the supporting piece stands on.

## Figures (heroes and monsters) are 2 height units tall; the Centurion (the "centaur") is 6 and covers 2x2 squares.
const FIGURE_HEIGHT := 2
const CENTAUR_HEIGHT := 6
const CENTAUR_SQUARES := 2

## What a piece holds up: mesh -> the rises (height units above the floor it stands on) at which a floor tile can rest on it.
## A floor can only be at a height above the ground when something here carries it.
const SUPPORT_RISES := {
	"mini": [1],
	"medium": [1, 2],
	"tall": [1, 2, 3],
	"stair": [1],      # only its high 2x1 end (see support_offsets)
	"archway": [3],    # the top of an archway (the gate is NOT a supporting structure)
}

## The ARCHWAY is also a CEILING (the gate is not): its top is a solid 3 units above their floor, so a figure of 2 fits under one but a Centurion (6) does not.
const CEILING_RISES := {"archway": 3}


## Ladders let figures CLIMB (they hold nothing up): mesh -> the rises a figure standing on the ladder's floor can reach. The upper floor
## has to touch the ladder's square (its position is not tracked: any side counts). A small ladder goes up 1 unit, a big one 1 or 2.
const CLIMB_RISES := {
	"small-ladder": [1],
	"big-ladder": [1, 2],
}


## Passing through: MOST pieces are solid - nobody can walk through or over them. These are the exceptions: stairs (you walk on them) and
## the tokens (exploration / interact / umbra don't block). The ARCHWAY is a 1x4 line whose two END squares are solid posts and whose
## MIDDLE two squares are the passage (see solid_offsets).
const PASSABLE := ["stair", "bridge", "exploration", "interact", "umbra"]

## Gates and fences are SOLID (nobody stands in or walks through them) but remove themselves when interacted with, and barricades are
## typically destroyed. They only block placing a figure: no walking check takes solid pieces into account (a room closed off by them
## would be pointless, so it is not modelled). Listed so the pictures can mark them.
const REMOVABLE := ["gate", "fence", "barricade"]

## Pieces that may stand on bare ground at height 0 (no floor tile under them): the pillars, the stairs, and the archway and fence (NOT the gate).
## Above the ground they still need a floor at their own height.
## The BRIDGE (2 wide x 6 long, author 2026-10-25): xxyyxx - the two outer squares of each end (x) are ramps that must rest on floor at the
## bridge's own height (or on the bare ground at height 0); the two middle squares (y) are a walkable deck BRIDGE_RISE units higher, which may
## span hazards or open space. Walkable, never solid; under the deck there is only BRIDGE_RISE units of headroom, so no figure fits there.
## For walking, standing and sight it is two STAIRS placed against each other, high ends touching in the middle: all six squares count as
## walked at the bridge's own height (the height of its steps does not matter, like on a stair; MissionSight / MonsterMovement / SightLine).
const BRIDGE_RISE := 1
const BRIDGE_END_SQUARES := 2


static func is_bridge(mesh: String) -> bool:
	return mesh == "bridge"


## The ramp cells at both ends of a PLACED bridge (absolute fine cells).
static func bridge_end_cells(cells: Array) -> Array[Vector3i]:
	return _end_posts(cells, BRIDGE_END_SQUARES)


## The outermost square row at each end of a PLACED bridge: what has to rest on floor (the rest of a ramp may hang over the gap, like the
## low end of a stair is the only part that needs floor).
static func bridge_foot_cells(cells: Array) -> Array[Vector3i]:
	return _end_posts(cells, 1)


## Fine cells (x, height, z) a figure or a piece placed ON terrain may use: every square of a bridge at its own height and one unit up (the
## deck, where the editor puts a token or a spawn tile on it - a door on the middle of a bridge), the high end of a stair at its own height
## and one up (a door at the top of a stair), and the spaces of a statue at their walking height and one up. `pieces` = validator pieces
## (with "fine_origin").
static func standing_cells(pieces: Array) -> Dictionary:
	var cells: Dictionary = {}
	var cpt := FootprintRegistry.CELLS_PER_TILE
	for piece: Dictionary in pieces:
		if piece["layer"] != "prop":
			continue
		if is_bridge(piece["mesh"]):
			for cell: Vector3i in piece["cells"]:
				cells[Vector3i(cell.x, piece["height"], cell.z)] = true
				cells[Vector3i(cell.x, int(piece["height"]) + BRIDGE_RISE, cell.z)] = true
		var origin: Vector3i = piece.get("fine_origin", Vector3i.ZERO)
		if piece["mesh"] == "stair":
			# the whole squares of the high end (stair_high_end() gives only its outermost row of fine cells)
			for cell: Vector3i in stair_high_end(Vector3i(origin.x, piece["height"], origin.z), piece["cells"]):
				var square := Vector2i(floori(float(cell.x) / cpt), floori(float(cell.z) / cpt))
				for dx in cpt:
					for dz in cpt:
						cells[Vector3i(square.x * cpt + dx, piece["height"], square.y * cpt + dz)] = true
						cells[Vector3i(square.x * cpt + dx, int(piece["height"]) + 1, square.y * cpt + dz)] = true
		var raised := raised_squares(piece["mesh"], Vector3i(origin.x, piece["height"], origin.z), piece["cells"])
		for square: Vector3i in raised:
			for dx in cpt:
				for dz in cpt:
					cells[Vector3i(square.x * cpt + dx, square.y, square.z * cpt + dz)] = true
					cells[Vector3i(square.x * cpt + dx, square.y + 1, square.z * cpt + dz)] = true
	return cells


## The deck cells in the middle of a PLACED bridge.
static func bridge_middle_cells(cells: Array) -> Array[Vector3i]:
	var ends := _end_posts(cells, BRIDGE_END_SQUARES)
	var middle: Array[Vector3i] = []
	for cell: Vector3i in cells:
		if not ends.has(cell):
			middle.append(cell)
	return middle


## Long thin pieces with a PASSAGE: an archway has solid end posts and an open middle; the BELL (2026-10-25, from the game's props) is the
## other way round for sight - its two end squares block walking, its middle squares block line of sight.
const POSTED := ["archway", "bell"]

const STANDS_ON_GROUND := ["mini", "medium", "tall", "stair", "archway", "fence"]


## The fine-cell offsets (unrotated, same space as support_offsets) of the part of a piece that BLOCKS walking and standing: all of it for
## most pieces, none for the PASSABLE ones, and only the two end squares of an archway.
static func solid_offsets(mesh: String) -> Array[Vector3i]:
	var footprint := FootprintRegistry.get_footprint(mesh)
	if PASSABLE.has(mesh):
		var none: Array[Vector3i] = []
		return none
	if not POSTED.has(mesh):
		return footprint
	var low := footprint[0].z
	var high := footprint[0].z
	for offset in footprint:
		low = mini(low, offset.z)
		high = maxi(high, offset.z)
	var span := FootprintRegistry.CELLS_PER_TILE
	var posts: Array[Vector3i] = []
	for offset in footprint:
		if offset.z < low + span or offset.z > high - span:
			posts.append(offset)
	return posts


## Vision. How tall each piece is above the floor it stands on, in height units (measured from the meshes: mesh height / 3.6). A piece BLOCKS
## SIGHT when it is taller than a standing figure (FIGURE_HEIGHT, 2): tree 3.96, tall pillar 3.83, archway 3.83, gate 2.76 and medium
## pillar 2.22 block; the fence (1.96, see-through by design), well 1.83, mini pillar 1.28, stairs and everything furniture-sized do not.
## Ladders are open frames, so they never block even though a big one is 3.55 tall.
const PIECE_HEIGHTS := {
	"mini": 1.28, "medium": 2.22, "tall": 3.83, "stair": 0.94, "gate": 2.76, "archway": 3.83, "fence": 1.96,
	"barricade": 0.78, "table": 0.66, "small-table": 0.64, "tree": 3.96, "cart": 0.63, "chest": 0.62, "pot": 0.76, "well": 1.83,
	"big-ladder": 3.55, "small-ladder": 1.77, "exploration": 0.06, "interact": 0.06, "umbra": 0.06,
	# the props from the game's own models (OriginalPropsLibrary): measured model height / 3.6
	"altar": 0.83, "bell": 2.78, "bloodshrine": 2.1, "bookshelf": 1.6, "dragonarch": 5.17, "dragonhead": 2.4, "fire": 0.8, "statue": 3.58, "statue2": 3.6, "bridge": 1.0,
}
## What blocks line of sight follows the game's own rules (its glossary, "Terrain and Line of Sight"): doors (our gate), trees, shelves (our
## bookshelf), the two pillars of an archway and the dragon statue (our dragon arch and dragon head - which of the two the game means is not
## known, so both block). Pillars do NOT block when they stand on the lines between spaces, which ours always do. Everything else - barricades,
## cauldrons, chests, gates (our fence), lecterns, staircases, tables, wells, bells, shrines, statues, ladders, bridges, underlays - does not.
const SIGHT_BLOCKING := ["gate", "tree", "bookshelf", "archway", "dragonarch", "dragonhead"]

## STATUES (the user, 2026-11-17): a statue is 2x3 squares and about 3 levels tall, and some of its squares are spaces figures and tokens can
## stand on ("spaces on terrain" in the game's rules; its interaction "Climb the statue" puts a hero on one). Per statue: [column, row, level]
## in the statue's own frame (statue2 has two spaces at level 1; statue one at level 1, two at level 2 and one on top of the tall back at level 3) - row 0 is the tall back (the row farthest from the origin along the long side) .. row 2 the front, column 0 is
## the far side from the origin along the short side. A space of level L has its surface just under level L (RAISED_SURFACE levels above the
## statue's base), so like a stair step it is reached from less than a level below and leads to less than a level above.
const RAISED_SPACES := {"statue2": [[1, 1, 1], [1, 2, 1]], "statue": [[1, 1, 1], [0, 1, 2], [0, 2, 2], [0, 0, 3]]}
const RAISED_SURFACE := {1: 0.93, 2: 1.89, 3: 2.84}


static func piece_height(mesh: String) -> float:
	return float(PIECE_HEIGHTS.get(mesh, 0.0))


## Whether a piece blocks line of sight (the game's rules, see SIGHT_BLOCKING).
static func blocks_sight(mesh: String) -> bool:
	return SIGHT_BLOCKING.has(mesh)


## The spaces of a PLACED statue figures can stand on: Array of {"square": Vector2i (square x, z), "level": 1..3}; empty for other pieces.
## `origin` is the piece's origin cell and `cells` its absolute fine cells (any rotation).
static func raised_spaces(mesh: String, origin: Vector3i, cells: Array) -> Array[Dictionary]:
	var spaces: Array[Dictionary] = []
	if not RAISED_SPACES.has(mesh) or cells.is_empty():
		return spaces
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var xs: Dictionary = {}
	var zs: Dictionary = {}
	for cell: Vector3i in cells:
		xs[floori(float(cell.x) / cpt)] = true
		zs[floori(float(cell.z) / cpt)] = true
	# order the squares along each axis by their distance from the origin (nearest first): that is independent of the rotation
	var by_distance := func(values: Array, at: float) -> Array:
		values.sort_custom(func(a, b): return absf(float(a * cpt) + float(cpt) / 2.0 - at) < absf(float(b * cpt) + float(cpt) / 2.0 - at))
		return values
	var x_order: Array = by_distance.call(xs.keys(), float(origin.x) + 0.5)
	var z_order: Array = by_distance.call(zs.keys(), float(origin.z) + 0.5)
	var along_z := z_order.size() >= x_order.size()
	var long_order: Array = z_order if along_z else x_order
	var short_order: Array = x_order if along_z else z_order
	for space: Array in RAISED_SPACES[mesh]:
		var row := long_order.size() - 1 - int(space[1])
		var column := short_order.size() - 1 - int(space[0])
		if row < 0 or column < 0:
			continue
		var long_value: int = long_order[row]
		var short_value: int = short_order[column]
		var square := Vector2i(short_value, long_value) if along_z else Vector2i(long_value, short_value)
		spaces.append({"square": square, "level": int(space[2])})
	return spaces


## The squares (x, height, z) where a figure on the spaces of a placed statue stands for walking: level L is kept at base + L - 1 (its surface
## is just under base + L), like a stair square. -> {Vector3i: level}
static func raised_squares(mesh: String, origin: Vector3i, cells: Array) -> Dictionary:
	var squares: Dictionary = {}
	for space: Dictionary in raised_spaces(mesh, origin, cells):
		var square: Vector2i = space["square"]
		squares[Vector3i(square.x, origin.y + int(space["level"]) - 1, square.y)] = int(space["level"])
	return squares


## The fine-cell offsets (unrotated, same space as support_offsets) of the part of a piece that blocks sight: all of it for a blocking piece
## (an archway only its two end posts - the passage is open), none for the others.
static func sight_offsets(mesh: String) -> Array[Vector3i]:
	if not blocks_sight(mesh):
		var none: Array[Vector3i] = []
		return none
	if mesh == "archway":
		return solid_offsets(mesh)
	return FootprintRegistry.get_footprint(mesh)


## The same sight rule for a piece that is already PLACED: `cells` are its absolute fine cells (origin + rotated footprint). All of them for
## a blocking piece, only the two end posts for an archway (the squares at both ends of its long axis), none for the others.
static func sight_cells_from_footprint(mesh: String, cells: Array[Vector3i]) -> Array[Vector3i]:
	if not blocks_sight(mesh):
		var none: Array[Vector3i] = []
		return none
	if mesh != "archway" or cells.is_empty():
		return cells
	return _end_posts(cells)


## The solid part of a PLACED piece (absolute fine cells): all of it, none for the PASSABLE ones, the two end posts of an archway or bell.
static func solid_cells_from_footprint(mesh: String, cells: Array[Vector3i]) -> Array[Vector3i]:
	if PASSABLE.has(mesh):
		var none: Array[Vector3i] = []
		return none
	if not POSTED.has(mesh) or cells.is_empty():
		return cells
	return _end_posts(cells)


## The squares at both ends of a long thin footprint (an archway's two posts).
static func _end_posts(cells: Array, squares: int = 1) -> Array[Vector3i]:
	var low := Vector2i(cells[0].x, cells[0].z)
	var high := low
	for cell: Vector3i in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.z))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.z))
	var span := FootprintRegistry.CELLS_PER_TILE * squares
	var along_z := high.y - low.y >= high.x - low.x
	var posts: Array[Vector3i] = []
	for cell: Vector3i in cells:
		var value := cell.z if along_z else cell.x
		var first := low.y if along_z else low.x
		var last := high.y if along_z else high.x
		if value < first + span or value > last - span:
			posts.append(cell)
	return posts


## A placed stair's HIGH end (absolute fine cells): the origin is the low point, so it is the cells farthest from the origin along the
## stair's long axis (its 2x1 end, see support_offsets).
static func stair_high_end(origin: Vector3i, cells: Array[Vector3i]) -> Array[Vector3i]:
	var low := Vector2i(cells[0].x, cells[0].z)
	var high := low
	for cell in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.z))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.z))
	var along_z := high.y - low.y >= high.x - low.x
	var farthest := 0
	for cell in cells:
		farthest = maxi(farthest, absi((cell.z - origin.z) if along_z else (cell.x - origin.x)))
	var end: Array[Vector3i] = []
	for cell in cells:
		if absi((cell.z - origin.z) if along_z else (cell.x - origin.x)) == farthest:
			end.append(cell)
	return end


static func climb_rises(mesh: String) -> Array:
	return CLIMB_RISES.get(mesh, [])


static func support_rises(mesh: String) -> Array:
	return SUPPORT_RISES.get(mesh, [])


static func stands_on_ground(mesh: String) -> bool:
	return STANDS_ON_GROUND.has(mesh)


static func is_support(mesh: String) -> bool:
	return SUPPORT_RISES.has(mesh)


## The fine-cell offsets (unrotated, relative to the piece's origin, the same space as FootprintRegistry.get_footprint()) of the part of
## the piece a floor can rest on. A pillar or archway carries floor over its whole footprint; a stair only over its HIGH end - the
## 2x1 row farthest from its origin (the origin is the low point, see the stair's footprint comment in FootprintRegistry).
static func support_offsets(mesh: String) -> Array[Vector3i]:
	var footprint := FootprintRegistry.get_footprint(mesh)
	if mesh != "stair":
		return footprint
	var far_z := footprint[0].z
	for offset in footprint:
		far_z = mini(far_z, offset.z)
	var high: Array[Vector3i] = []
	for offset in footprint:
		if offset.z == far_z:
			high.append(offset)
	return high


## The rules as plain text, for a person or for an AI prompt.
static func describe() -> String:
	return "\n".join([
		"Height units: the map is a 3D grid; floor tiles are flat, a floor at height h has its walking surface h units above the ground (0 = ground).",
		"A floor above the ground must rest on something that is standing on a floor below it and reaches exactly that height:",
		"- mini pillar: floors 1 unit above the floor it stands on.",
		"- medium pillar: floors 1 or 2 units above.",
		"- tall pillar: floors 1, 2 or 3 units above.",
		"Pillars stand where four squares meet (their position always ends in .5). Floor tiles have cut-outs for them only along their edges, so a pillar should not touch an inner or outer corner of a floor tile, at any height it reaches (the floor it stands on up to the highest floor it can hold).",
		"- stair (2x3): the high 2x1 end holds a floor 1 unit above; the low end is where you climb on.",
		"- archway: the top holds a floor 3 units above (a gate holds nothing up).",
		"Bridges and overhangs are allowed: floors may lie over other floors if they are supported and have that much room.",
		"Figures are 2 units tall: a square where a hero or monster stands needs 2 free units above it. The Centurion is 6 tall and covers 2x2 squares and needs 6 free units over all four - never under a bridge, floor or archway.",
		"The heroes need start squares: at least one, and one for every hero that may play (the map's maximum number of players, 1 to 6).",
		"Pieces other than floors stand on a floor at their own height - except pillars, stairs, the archway and the fence, which may stand on the bare ground at height 0.",
		"Most pieces are solid: no figure can stand in them or walk through them (pillars, trees, tables, chests, carts, barricades, wells, pots, ladders...). Exceptions you can pass: stairs and the tokens (exploration, interact, umbra). Gates and fences are solid too, but they remove themselves when a figure interacts with them (so they act as doors) and barricades are typically destroyed, so nothing is ever walled off for good. The archway is 1x4: its two end squares are solid, the two middle squares are the passage.",
		"Sight (the game's rules): two squares see each other when a line can be drawn from ANY corner of one to ANY corner of the other without being stopped (a line grazing the edge of a piece passes, but not between two pieces that touch). Heights do not matter: look at the map as if every tile were on one level. A line is stopped by a square holding blocking terrain - trees, gates (doors), bookshelves, the dragon arch and dragon head, and an archway's two end posts (its two middle squares are open) - and by leaving the map (it may only run over spaces: floors, underlays and stairs at any height). Pillars never block (they stand on the lines between squares), nor do fences, statues, bells, shrines, furniture, stairs, ladders or bridges.",
		"The bridge (2 wide, 6 long: xxyyxx along its length) is walkable: its two outer squares at each end (x) are ramps whose outermost square must rest on floor at the bridge's own height (or on the bare ground at height 0), so it spans a gap of up to 4 squares, and its two middle squares (y) are a deck 1 unit higher that may span hazards or open space. For walking it is two stairs placed against each other (high ends touching in the middle): figures walk and stand on all six squares at the bridge's own height. It connects the floors at its two ends; nobody fits under it.",
		"Floors at different heights only connect through a stair (its high end touches the upper floor) or a ladder: a small ladder climbs 1 unit, a big ladder 1 or 2; the upper floor must touch the ladder's square.",
	])
