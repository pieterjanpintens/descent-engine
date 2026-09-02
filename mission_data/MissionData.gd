class_name MissionData
extends Resource

## Root resource describing a single mission: grid layout, static occupancy,
## monster spawns and trigger/event definitions. Both the Mission Creator and
## the Player load/save this same resource so there is one source of truth.

@export var mission_name: String = ""
@export var grid_size: Vector3i = Vector3i(20, 1, 20)
@export var cell_size: float = 1.0

## Logical per-cell data. Key = Vector3i cell coordinate. Y is the level -
## distinct floors AND localized elevation (a dais, a ledge) both just use
## different Y values; there's no separate "level" concept beyond the cell
## coordinate itself. Value = TileEntry.
@export var tiles: Dictionary = {}  # Dictionary[Vector3i, TileEntry]

## Multi-cell occupancy index. Key = any cell covered by a placed item,
## Value = the "owner" cell where that item's GridMap entry actually lives.
## Populated by FootprintRegistry.register_item(), consumed by movement/LOS.
@export var occupied_cells: Dictionary = {}  # Dictionary[Vector3i, Vector3i]

@export var interactables: Array[InteractableEntry] = []
@export var monster_spawns: Array[MonsterSpawn] = []
@export var triggers: Array[MissionTrigger] = []


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
