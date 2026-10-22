class_name MapPieceCatalog
extends RefCounted

## The pieces a map can be made of, described as text for an AI that writes a map plan (StageGenerator): every floor tile face drawn as a
## little picture of the squares it covers, how many copies of each physical tile are still free, and a line per prop and hazard. The pictures
## are produced by MapPlanValidator itself (one piece placed at 0, 0, rotation 0), so they show exactly what a plan would place. Never instantiated.
## Experimental (branch experiment/stage-generation).

## What each non-floor piece is for. The size is added from the real footprint.
const PROP_NOTES: Dictionary = {
	"gate": "a door. Solid, but it disappears when a figure interacts with it, so it never walls anything off for good. Put it in a gap of a wall of pieces or in a corridor/doorway.",
	"fence": "like a gate (an opening that removes itself when interacted with) but see-through.",
	"archway": "a gateway, 1 square wide and 4 long: its two END squares are solid posts, the two middle squares are the passage. It can hold a floor 3 units above.",
	"barricade": "a barrier that gets destroyed; solid.",
	"tree": "solid, blocks sight.",
	"tall": "a tall pillar: solid, blocks sight, can hold a floor 1, 2 or 3 units above. Stands where squares meet (half-unit positions allowed).",
	"medium": "a medium pillar: solid, blocks sight at its own floor, can hold a floor 1 or 2 units above. Half-unit positions allowed.",
	"mini": "a small pillar: solid, does not block sight, holds a floor 1 unit above. Half-unit positions allowed.",
	"stair": "a staircase. Walkable. Its HIGH end (the 2x1 row farthest from the origin at rotation 0) holds a floor 1 unit above; the low end is where figures climb on. May stand on the ground.",
	"small-ladder": "a ladder that climbs 1 unit (solid; the upper floor must touch it).",
	"big-ladder": "a ladder that climbs 1 or 2 units (solid; the upper floor must touch it).",
	"exploration": "a token square (walkable).",
	"interact": "a token square (walkable).",
	"umbra": "a token square (walkable).",
	"cart": "furniture, solid.",
	"chest": "furniture, solid.",
	"pot": "furniture, solid.",
	"table": "furniture, solid.",
	"small-table": "furniture, solid.",
	"well": "furniture, solid.",
	"water": "a hazard card laid on the ground (underlay): figures can't stand on it unless a floor lies over it.",
	"acid": "a hazard card (underlay).",
	"lava": "a hazard card (underlay).",
	"spikes": "a hazard card (underlay).",
}

static var _shapes: Dictionary = {}


## The whole catalog as text. `used` = physical group -> copies the rest of the mission already uses (so only the free ones are offered).
static func describe(used: Dictionary = {}) -> String:
	var lines: Array[String] = []
	lines.append("FLOOR TILES. Each tile is one physical piece with two faces (a and b, the b face is the mirror image of the a face); a tile may be used ONCE (the count says how many copies are free). Every tile is listed as a picture of the squares it covers at rotation 0 ('.' = a square of the tile), x to the right, z downward. A piece's position x, z is the top-left corner of the area it covers - also after it is rotated. Rotation is in quarter turns (0-3); an odd rotation swaps width and depth, so picture the piece turned that way (the checker's picture of your plan shows what you actually got).")
	var numbers: Array[int] = []
	var faces: Dictionary = {}
	for mesh: String in MapPlanValidator.known_meshes():
		if FootprintRegistry.get_layer(mesh) == "floor":
			var number := int(mesh.substr(0, mesh.length() - 1))
			if not numbers.has(number):
				numbers.append(number)
			faces[mesh] = true
	numbers.sort()
	for number in numbers:
		var group := "tile_%d" % number
		var maximum := ComponentInventory.get_max_count(group)
		var free := 99 if maximum < 0 else maxi(maximum - int(used.get(group, 0)), 0)
		if free <= 0:
			continue
		lines.append("")
		lines.append("Tile %d (faces %da / %db), %s:" % [number, number, number, "any number free" if maximum < 0 else "%d free" % free])
		for face in ["a", "b"]:
			var mesh := "%d%s" % [number, face]
			if faces.has(mesh):
				lines.append("%s:" % mesh)
				lines.append(shape_of(mesh))
	lines.append("")
	lines.append("OTHER PIECES (size at rotation 0, in squares: width along x by depth along z):")
	for mesh: String in PROP_NOTES:
		if not MapPlanValidator.known_meshes().has(mesh):
			continue
		var group := ComponentInventory.get_group(mesh)
		var maximum := ComponentInventory.get_max_count(group)
		var free := 99 if maximum < 0 else maxi(maximum - int(used.get(group, 0)), 0)
		if free <= 0:
			continue
		var size := size_of(mesh)
		lines.append("- %s (%dx%d%s): %s" % [mesh, size.x, size.y, "" if maximum < 0 else ", %d free" % free, PROP_NOTES[mesh]])
	if MapPlanValidator.known_meshes().has("stair"):
		lines.append("")
		lines.append("Which way the stair climbs (its high end holds the floor above): " + stair_directions())
	return "\n".join(lines)


## "rotation 0: rises towards the right (+x); ..." for the four rotations of the stair.
static func stair_directions() -> String:
	var parts: Array[String] = []
	for turns in 4:
		var result := MapPlanValidator.validate({"pieces": [{"mesh": "stair", "x": 0, "z": 0, "rotation": turns}]}, {"require_start": false})
		var pieces: Array = result["pieces"]
		if pieces.is_empty():
			continue
		var piece: Dictionary = pieces[0]
		var cells: Array[Vector3i] = []
		cells.assign(piece["cells"])
		var high := BuildRules.stair_high_end(piece["fine_origin"], cells)
		if high.is_empty():
			continue
		var centre := Vector2.ZERO
		for cell in cells:
			centre += Vector2(cell.x, cell.z)
		centre /= cells.size()
		var top := Vector2.ZERO
		for cell in high:
			top += Vector2(cell.x, cell.z)
		top /= high.size()
		var delta := top - centre
		var direction := ""
		if absf(delta.x) > absf(delta.y):
			direction = "right (+x)" if delta.x > 0 else "left (-x)"
		else:
			direction = "down (+z)" if delta.y > 0 else "up (-z)"
		parts.append("rotation %d: rises towards %s" % [turns, direction])
	return "; ".join(parts)


## A text picture of one piece at 0, 0 rotation 0.
static func shape_of(mesh: String) -> String:
	_load_shape(mesh)
	return str(_shapes[mesh]["picture"])


## The squares a piece covers at rotation 0 as (width along x, depth along z).
static func size_of(mesh: String) -> Vector2i:
	_load_shape(mesh)
	return _shapes[mesh]["size"]


static func _load_shape(mesh: String) -> void:
	if _shapes.has(mesh):
		return
	var result := MapPlanValidator.validate({"pieces": [{"mesh": mesh, "x": 0, "z": 0}]}, {"require_start": false})
	var bounds: Rect2i = result["bounds"]
	var picture := ""
	if mesh in ["water", "acid", "lava", "spikes"]:
		var rows: Array[String] = []
		for z in bounds.size.y:
			rows.append("~".repeat(bounds.size.x))
		picture = "\n".join(rows)
	else:
		picture = MapPlanValidator.render_ascii(result, 0)
	_shapes[mesh] = {"picture": picture, "size": bounds.size}
