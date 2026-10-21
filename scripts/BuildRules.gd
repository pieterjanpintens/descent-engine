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
	"gate": [3],       # "gateways": the top of a gate ...
	"archway": [3],    # ... or an archway
}

## Gateways are also CEILINGS: their top is a solid 3 units above their floor, so a figure of 2 fits under one but a Centurion (6) does not.
const CEILING_RISES := {"gate": 3, "archway": 3}


## Ladders let figures CLIMB (they hold nothing up): mesh -> the rises a figure standing on the ladder's floor can reach. The upper floor
## has to touch the ladder's square (its position is not tracked: any side counts). A small ladder goes up 1 unit, a big one 1 or 2.
const CLIMB_RISES := {
	"small-ladder": [1],
	"big-ladder": [1, 2],
}


## Passing through: MOST pieces are solid - nobody can walk through or over them. These are the exceptions: stairs (you walk on them) and
## the tokens (exploration / interact / umbra don't block). The ARCHWAY is a 1x4 line whose two END squares are solid posts and whose
## MIDDLE two squares are the passage (see solid_offsets).
const PASSABLE := ["stair", "exploration", "interact", "umbra"]

## Gates and fences are SOLID (nobody stands in or walks through them) but remove themselves when interacted with, and barricades are
## typically destroyed. They only block placing a figure: no walking check takes solid pieces into account (a room closed off by them
## would be pointless, so it is not modelled). Listed so the pictures can mark them.
const REMOVABLE := ["gate", "fence", "barricade"]


## The fine-cell offsets (unrotated, same space as support_offsets) of the part of a piece that BLOCKS walking and standing: all of it for
## most pieces, none for the PASSABLE ones, and only the two end squares of an archway.
static func solid_offsets(mesh: String) -> Array[Vector3i]:
	var footprint := FootprintRegistry.get_footprint(mesh)
	if PASSABLE.has(mesh):
		var none: Array[Vector3i] = []
		return none
	if mesh != "archway":
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
}
const SEE_THROUGH := ["big-ladder", "small-ladder"]


static func piece_height(mesh: String) -> float:
	return float(PIECE_HEIGHTS.get(mesh, 0.0))


## Whether a piece blocks the line of sight of a standing figure (see PIECE_HEIGHTS).
static func blocks_sight(mesh: String) -> bool:
	return piece_height(mesh) > FIGURE_HEIGHT and not SEE_THROUGH.has(mesh)


## The fine-cell offsets (unrotated, same space as support_offsets) of the part of a piece that blocks sight: all of it for a blocking piece
## (an archway only its two end posts - the passage is open), none for the others.
static func sight_offsets(mesh: String) -> Array[Vector3i]:
	if not blocks_sight(mesh):
		var none: Array[Vector3i] = []
		return none
	if mesh == "archway":
		return solid_offsets(mesh)
	return FootprintRegistry.get_footprint(mesh)


static func climb_rises(mesh: String) -> Array:
	return CLIMB_RISES.get(mesh, [])


static func support_rises(mesh: String) -> Array:
	return SUPPORT_RISES.get(mesh, [])


static func is_support(mesh: String) -> bool:
	return SUPPORT_RISES.has(mesh)


## The fine-cell offsets (unrotated, relative to the piece's origin, the same space as FootprintRegistry.get_footprint()) of the part of
## the piece a floor can rest on. A pillar, gate or archway carries floor over its whole footprint; a stair only over its HIGH end - the
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
		"- stair (2x3): the high 2x1 end holds a floor 1 unit above; the low end is where you climb on.",
		"- gate or archway: the top holds a floor 3 units above.",
		"Bridges and overhangs are allowed: floors may lie over other floors if they are supported and have that much room.",
		"Figures are 2 units tall: a square where a hero or monster stands needs 2 free units above it. The Centurion is 6 tall and covers 2x2 squares and needs 6 free units over all four - never under a bridge, floor or gateway.",
		"Pieces other than floors stand on a floor at their own height.",
		"Most pieces are solid: no figure can stand in them or walk through them (pillars, trees, tables, chests, carts, barricades, wells, pots, ladders...). Exceptions you can pass: stairs and the tokens (exploration, interact, umbra). Gates and fences are solid too, but they remove themselves when a figure interacts with them (so they act as doors) and barricades are typically destroyed, so nothing is ever walled off for good. The archway is 1x4: its two end squares are solid, the two middle squares are the passage.",
		"Sight: two squares see each other when a line can be drawn from ANY corner of one to ANY corner of the other without being stopped (a line grazing the edge of a piece passes, but not between two pieces that touch). The line runs at figure height (2 units) above each figure's own floor, so a piece blocks only if its top is above that line: trees, tall and medium pillars, gates and an archway's two end posts block (the archway's two middle squares are open); fences (see-through), wells, mini pillars, stairs, furniture and ladders do not.",
		"A medium pillar (2.2) therefore blocks figures standing on its floor but not someone standing 1 unit up; a tall pillar (3.8) still blocks from 1 up but not from a floor at height 2 (what is left above it is less than a figure). You can look up or down at any distance, but never through a floor: a figure directly under or over a floor tile is not visible, and you can't look down through the floor you stand on.",
		"Floors at different heights only connect through a stair (its high end touches the upper floor) or a ladder: a small ladder climbs 1 unit, a big ladder 1 or 2; the upper floor must touch the ladder's square.",
	])
