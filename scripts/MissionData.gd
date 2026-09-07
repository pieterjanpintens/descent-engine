class_name MissionData
extends Resource

## Root resource describing a single mission: grid layout, static occupancy,
## monster spawns and trigger/event definitions. Both the Mission Creator and
## the Player load/save this same resource so there is one source of truth.

@export var mission_name: String = ""

## Logical per-cell data. Key = Vector3i cell coordinate. Y is the level -
## distinct floors AND localized elevation (a dais, a ledge) both just use
## different Y values; there's no separate "level" concept beyond the cell
## coordinate itself. Value = TileEntry.
@export var tiles: Dictionary = {}  # Dictionary[Vector3i, TileEntry]

## Raw paint records for the floor/wall layers - one entry per origin cell
## painted, regardless of how many cells its footprint covers. Needed to
## repaint FloorGridMap/WallGridMap when loading a mission; tiles alone
## isn't enough (see TilePlacement).
@export var floor_placements: Array[TilePlacement] = []

## Floor/wall equivalent of occupied_cells: every cell a floor/wall piece
## covers -> the origin cell GridMap actually has the item painted at.
## GridMap only stores data at the origin cell of a multi-cell item -
## everything else it covers is, as far as GridMap itself is concerned,
## empty. Needed to translate "which cell did a raycast hit" into "which
## cell does GridMap need to actually be told to erase."
@export var floor_occupied_cells: Dictionary = {}  # Dictionary[Vector3i, Vector3i]

## Multi-cell occupancy index. Key = any cell covered by a placed item,
## Value = the "owner" cell where that item's GridMap entry actually lives.
## Populated by FootprintRegistry.register_item(), consumed by movement/LOS.
@export var occupied_cells: Dictionary = {}  # Dictionary[Vector3i, Vector3i]

## Underlay layer (water/acid/lava/spikes physical paper pieces that sit
## beneath the floor tiles) - a separate painted layer, NOT folded into
## tiles/floor_placements. Unlike wall (which overrides floor's logical
## defaults on the same cell), underlay coexists with whatever floor tile
## sits above it, so it can't share TileEntry's single walkable/blocks_los
## slot per cell without one silently clobbering the other.
@export var underlay_placements: Array[TilePlacement] = []
@export var underlay_occupied_cells: Dictionary = {}  # Dictionary[Vector3i, Vector3i]

@export var interactables: Array[InteractableEntry] = []
@export var monster_spawns: Array[MonsterSpawn] = []
@export var triggers: Array[MissionTrigger] = []


## Returns { group_name: count } tallying every placed floor/wall/underlay/
## prop piece by its PHYSICAL component group (see ComponentInventory - both
## faces of a double-sided tile count as the same physical piece).
func get_component_usage() -> Dictionary:
	var usage: Dictionary = {}
	for placement in floor_placements:
		var group := ComponentInventory.get_group(placement.mesh_item_name)
		usage[group] = usage.get(group, 0) + 1
	for placement in underlay_placements:
		var group := ComponentInventory.get_group(placement.mesh_item_name)
		usage[group] = usage.get(group, 0) + 1
	for entry in interactables:
		var group := ComponentInventory.get_group(entry.mesh_item_name)
		usage[group] = usage.get(group, 0) + 1
	return usage


func get_tile(cell: Vector3i) -> TileEntry:
	return tiles.get(cell, null)


func is_walkable(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	if tile == null:
		return false
	if not tile.walkable:
		return false
	# A cell can be walkable floor but still blocked by something occupying
	# it (pillar, bookshelf, ...). Monsters are checked separately by the
	# runtime since they move during play and aren't part of mission data.
	return not occupied_cells.has(cell)


func blocks_los(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	if tile != null and tile.blocks_los:
		return true
	if occupied_cells.has(cell):
		var owner_cell: Vector3i = occupied_cells[cell]
		for entry in interactables:
			if entry.origin_cell == owner_cell:
				return entry.blocks_los
	return false


func get_interactable_at(cell: Vector3i) -> InteractableEntry:
	if not occupied_cells.has(cell):
		return null
	var owner_cell: Vector3i = occupied_cells[cell]
	for entry in interactables:
		if entry.origin_cell == owner_cell:
			return entry
	return null


## Returns every LEVEL_LINK interactable usable FROM the given cell (i.e.
## cell matches link_from_cell, or link_to_cell if the link is
## bidirectional). Movement logic should check this explicitly rather than
## assuming any adjacency between cells at different Y - stairs/ledges are
## deliberate connections, not automatic neighbors.
func get_level_links_from(cell: Vector3i) -> Array[InteractableEntry]:
	var links: Array[InteractableEntry] = []
	for entry in interactables:
		if entry.type != InteractableEntry.Type.LEVEL_LINK:
			continue
		if entry.link_from_cell == cell:
			links.append(entry)
		elif entry.link_bidirectional and entry.link_to_cell == cell:
			links.append(entry)
	return links
