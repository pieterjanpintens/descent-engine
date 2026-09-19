class_name MissionData
extends Resource

## Root resource describing a single mission: grid layout, static occupancy,
## monster spawns, and the story layer (triggers, win/loss objectives, custom
## variables). Both the Mission Creator and the Player load/save this same
## resource so there is one source of truth.
##
## The story layer's own runtime (variable values live during a playthrough,
## current round/checkpoint, win/loss state) is deliberately NOT part of
## this resource - MissionData is what got authored, not a live game. That
## runtime container doesn't exist yet.

@export var mission_name: String = ""

## How many players this mission supports - defaults to the full
## HeroCatalog.SLOT_COUNT (6) range so a mission with nothing authored here
## stays unrestricted. Enforced by EmbarkDialog (greys out remaining slots
## once max_players are selected, requires at least min_players to start).
@export var min_players: int = 1
@export var max_players: int = 6  ## keep in sync with HeroCatalog.SLOT_COUNT

## Logical per-cell data. Key = Vector3i cell coordinate. Y is the level -
## distinct floors AND localized elevation (a dais, a ledge) both just use
## different Y values; there's no separate "level" concept beyond the cell
## coordinate itself. Value = TileEntry.
@export var tiles: Dictionary = {}  # Dictionary[Vector3i, TileEntry]

## Raw paint records for the floor layer - one entry per origin cell
## painted, regardless of how many cells its footprint covers. Needed to
## repaint FloorGridMap when loading a mission; tiles alone isn't enough
## (see TilePlacement).
@export var floor_placements: Array[TilePlacement] = []

## Floor equivalent of occupied_cells: every cell a floor piece
## covers -> the origin cell GridMap actually has the item painted at.
## GridMap only stores data at the origin cell of a multi-cell item -
## everything else it covers is, as far as GridMap itself is concerned,
## empty. Needed to translate "which cell did a raycast hit" into "which
## cell does GridMap need to actually be told to erase."
@export var floor_occupied_cells: Dictionary = {}  # Dictionary[Vector3i, Vector3i]

## Multi-cell occupancy index. Key = any cell covered by a placed prop,
## Value = an Array of every prop's origin cell whose footprint covers it
## (usually one - multiple means an intentional overlap, e.g. a gate
## inside an archway, confirmed 2026-09-13 as a real authored case, see
## FootprintRegistry.mark_occupied()/clear_occupied()). Use
## prop_owners_at()/resolve_prop_priority() below to resolve back down to
## a single prop when exactly one is needed. Populated by
## FootprintRegistry.mark_occupied()/clear_occupied(), consumed by
## movement/LOS (is_walkable() below) and interaction
## (get_interactable_at() below).
@export var occupied_cells: Dictionary = {}  # Dictionary[Vector3i, Array] - Array[Vector3i]

## Underlay layer (water/acid/lava/spikes physical paper pieces that sit
## beneath the floor tiles) - a separate painted layer, NOT folded into
## tiles/floor_placements, since underlay coexists with whatever floor
## tile sits above it (it's meant to peek through, not replace it), so it
## can't share TileEntry's single walkable/blocks_los slot per cell
## without one silently clobbering the other.
@export var underlay_placements: Array[TilePlacement] = []
@export var underlay_occupied_cells: Dictionary = {}  # Dictionary[Vector3i, Vector3i]

@export var interactables: Array[InteractableEntry] = []
@export var monster_spawns: Array[MonsterSpawn] = []
@export var triggers: Array[MissionTrigger] = []

## Organizational nodes for the Creator's outline tree - see
## CreatorOutline.gd/MissionGroup.gd. Purely a layering/selection aid over
## `interactables`, not a spatial or gameplay concept of its own.
@export var groups: Array[MissionGroup] = []

## Backing counter for allocate_object_id() below - must be @export so it
## persists across save/load and never reissues an id already baked into
## a saved mission's own interactables/groups.
@export var _next_object_id: int = 1

## Where players may start round 1 - just cells, no per-spawn metadata
## (unlike MonsterSpawn, which needs type/facing/trigger per monster).
## TILE-SQUARE ("game unit", 3.2x3.2 world units) coordinates, NOT fine
## GridMap cells - a player figure occupies roughly one tile-square, not a
## quarter of one - see FootprintRegistry.fine_cell_to_tile_square(). Drawn
## in the Creator, shown as a yellow overlay in the Player before round 1 -
## see LayeredMap.set_spawn_overlay_cells(). Empty is valid (no overlay
## shown, round 1 just starts) - not every mission needs this authored yet.
@export var player_spawn_cells: Array[Vector3i] = []

## The ROOTS of a DAG of MissionObjective nodes - not necessarily WIN/LOSE
## leaves themselves, see MissionObjective's own doc for the full design
## (reworked 2026-09-12 from a flat list). Plural roots are fine - e.g. a
## main quest tree plus an independent "all players died" LOSE fail-safe
## that isn't nested under anything.
@export var objectives: Array[MissionObjective] = []

## Custom variable declarations Condition/Effect can reference by name, on
## top of the runtime's own built-ins (round_number, player_count, ...)
## which aren't declared here - see MissionVariable.
@export var custom_variables: Array[MissionVariable] = []


## Returns { group_name: count } tallying every placed floor/underlay/
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


## Mints a fresh, never-reused id - originally just for InteractableEntry/
## MissionGroup (see CreatorOutline.gd), but a plain generic counter, not
## type-restricted, so ObjectivesDialog.gd reuses it for new MissionObjective
## nodes too. The one shared allocator so no two ids in this mission can
## ever collide with each other, regardless of which kind of thing they
## identify.
func allocate_object_id() -> String:
	var result := "obj_%d" % _next_object_id
	_next_object_id += 1
	return result


## Finds a placed prop or floor/underlay tile by its OutlineNode id -
## resolves what Effect.Type.REMOVE_OBJECT targets (see
## MissionRuntime.apply_effect()/LayeredMap.remove_node()), and what the
## effect-authoring dropdown in ObjectivesDialog.gd/PropActionsDialog.gd
## lists. Groups aren't included - they have no GridMap presence to
## remove. ids are globally unique (allocate_object_id() is one shared
## counter across every OutlineNode subtype, not per-collection), so
## searching all three in sequence is unambiguous.
func find_node_by_id(id: String) -> OutlineNode:
	for entry in interactables:
		if entry.id == id:
			return entry
	for placement in floor_placements:
		if placement.id == id:
			return placement
	for placement in underlay_placements:
		if placement.id == id:
			return placement
	for spawn in monster_spawns:
		if spawn.id == id:
			return spawn
	return null


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


## InteractableEntry no longer carries its own blocks_los (removed
## 2026-09-10, unused - is_walkable() below never referenced the
## equivalent blocks_movement either, occupied_cells.has(cell) alone
## already blocks movement regardless of a specific flag's value). Prop-
## level LOS blocking can come back as a well-known InteractableEntry.props
## key if a real need for it ever shows up - this just reads the floor
## TileEntry's own blocks_los for now.
func blocks_los(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	return tile != null and tile.blocks_los


func get_interactable_at(cell: Vector3i) -> InteractableEntry:
	var owners := prop_owners_at(cell)
	if owners.is_empty():
		return null
	return _find_interactable_by_origin(resolve_prop_priority(owners))


## Every prop origin whose footprint currently covers `cell` - empty if
## nothing does. Order is placement order (see
## FootprintRegistry.mark_occupied()), not priority - see
## resolve_prop_priority() below for picking "the" one to act on.
##
## Also the ONE place that migrates a cell still in the OLD single-owner
## format (a bare Vector3i, from a mission saved before the 2026-09-14
## multi-owner occupancy rework) into the new Array format - confirmed as
## a real bug 2026-09-14: any pre-existing mission file has occupied_cells
## entries shaped the old way, so the very next edit that reached
## FootprintRegistry.mark_occupied()/clear_occupied() crashed with
## "Trying to assign value of type 'Vector3i' to a variable of type
## 'Array'" the moment it tried to treat one as an Array. Both of those
## functions route through this method now (rather than reading
## occupied_cells directly) specifically so this migration only has to
## live in one place.
func prop_owners_at(cell: Vector3i) -> Array:
	if not occupied_cells.has(cell):
		return []
	var value = occupied_cells[cell]
	if value is Array:
		return value
	var migrated: Array = [value]
	occupied_cells[cell] = migrated
	return migrated


## Picks the single "most specific" origin out of a non-empty list of
## overlapping prop owners (see prop_owners_at()) - for every caller that
## needs exactly one: get_interactable_at() above, Creator select/erase
## raycast resolution (CreatorController._find_prop_origin()), and the
## Player's own hover/drop hit-test (via get_interactable_at()).
## Smallest footprint wins - a generic "more specific object wins over a
## larger structural one" rule, not a gate/archway special case: this is
## what makes a gate correctly win over the archway it sits inside (the
## gate's footprint is a strict subset of the archway's), with zero
## authoring needed on either prop. Ties (equal footprint size) break
## toward whichever was placed most recently (last in `owners`) -
## arbitrary but deterministic. Callers must check
## prop_owners_at().is_empty() first; calling this with an empty array is
## a caller bug, not defended against.
func resolve_prop_priority(owners: Array) -> Vector3i:
	var best: Vector3i = owners[0]
	var best_size := _prop_footprint_size(best)
	for i in range(1, owners.size()):
		var candidate: Vector3i = owners[i]
		var size := _prop_footprint_size(candidate)
		if size <= best_size:
			best = candidate
			best_size = size
	return best


func _prop_footprint_size(origin: Vector3i) -> int:
	var entry := _find_interactable_by_origin(origin)
	return entry.footprint.size() if entry != null else 999999


func _find_interactable_by_origin(origin: Vector3i) -> InteractableEntry:
	for entry in interactables:
		if entry.origin_cell == origin:
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


## Whether `node` should actually be rendered right now - `node.visible`
## AND every ancestor MissionGroup's own `visible`, walking `parent_id`.
## Pure derived-view query, same category as get_interactable_at()/
## get_component_usage() above - no runtime state involved, just what the
## CURRENT data says. The one canonical implementation, reused by both
## LayeredMap's Player-only paint-skip (see that script's
## respect_visibility) and get_stage_requirements() below, so a "should
## this actually show up" question is only ever answered one way.
func is_effectively_visible(node: OutlineNode) -> bool:
	if not node.visible:
		return false
	var walk := node.parent_id
	var guard := groups.size() + 1  # defends against a corrupted/cyclic parent_id chain
	while walk != "" and guard > 0:
		var group := _find_group(walk)
		if group == null:
			break
		if not group.visible:
			return false
		walk = group.parent_id
		guard -= 1
	return true


## True if `node` sits under `group_id` anywhere in its parent_id ancestor
## chain (not just a direct child) - so a stage's requirements/reveal
## include nested subgroups' members too.
func _belongs_to_group_or_descendant(node: OutlineNode, group_id: String) -> bool:
	var walk := node.parent_id
	var guard := groups.size() + 1
	while walk != "" and guard > 0:
		if walk == group_id:
			return true
		var group := _find_group(walk)
		if group == null:
			break
		walk = group.parent_id
		guard -= 1
	return false


func _find_group(group_id: String) -> MissionGroup:
	for group in groups:
		if group.id == group_id:
			return group
	return null


## Everything a designer needs to physically place to build `group_id`
## (recursively, including nested subgroups), bucketed by
## floor/underlay/pillar/prop and counted by raw mesh_item_name - see
## MissionPlayer.show_stage(), the caller. Only counts entries that are
## currently is_effectively_visible() - a nested subgroup separately
## marked hidden isn't listed yet, its own future Show Stage reveals it.
## Pillars are split out of interactables via
## FootprintRegistry.allows_fine_placement() - the existing exact-name
## check for the pillar meshes (tall/mini/medium), reused rather than
## re-derived. Counts by raw mesh name rather than ComponentInventory's
## physical-group key - simpler, and every floor tile's placeholder
## MAX_COUNTS caps it at 1 physical copy today anyway, so grouping
## wouldn't currently change anything there; pillars (where counts > 1
## genuinely matter) are already summed correctly by raw mesh name alone.
func get_stage_requirements(group_id: String) -> Dictionary:
	var result := {"floor": {}, "underlay": {}, "pillar": {}, "prop": {}}
	for placement in floor_placements:
		if _belongs_to_group_or_descendant(placement, group_id) and is_effectively_visible(placement):
			var bucket: Dictionary = result["floor"]
			bucket[placement.mesh_item_name] = bucket.get(placement.mesh_item_name, 0) + 1
	for placement in underlay_placements:
		if _belongs_to_group_or_descendant(placement, group_id) and is_effectively_visible(placement):
			var bucket: Dictionary = result["underlay"]
			bucket[placement.mesh_item_name] = bucket.get(placement.mesh_item_name, 0) + 1
	for entry in interactables:
		if not _belongs_to_group_or_descendant(entry, group_id) or not is_effectively_visible(entry):
			continue
		var bucket_name := "pillar" if FootprintRegistry.allows_fine_placement(entry.mesh_item_name) else "prop"
		var bucket: Dictionary = result[bucket_name]
		bucket[entry.mesh_item_name] = bucket.get(entry.mesh_item_name, 0) + 1
	return result


## Finds the placed floor entry directly under a spawn tile-square, and
## returns the distinct MissionGroup ids covering `player_spawn_cells` -
## "the group containing the tile that has the start position", used to
## auto-reveal the starting room before round 1. Spawn cells are
## TILE-SQUARE coordinates (see player_spawn_cells' own doc); converted to
## their near-corner FINE cell with the exact same formula
## LayeredMap.get_tile_square_world_corners() uses, then looked up in
## floor_occupied_cells to find the covering placement. A spawn tile with
## no floor placed under it, or one that isn't in any group (parent_id ==
## ""), contributes nothing - "no stage to reveal" is a valid, silent
## no-op. Normally resolves to exactly one group (the intended starting
## room); more than one is returned as-is for the caller to loop over,
## not specially handled here.
func find_starting_group_ids() -> Array[String]:
	var ids: Array[String] = []
	var cpt := FootprintRegistry.CELLS_PER_TILE
	for spawn_cell in player_spawn_cells:
		var near_fine_cell := Vector3i(spawn_cell.x * cpt - cpt, spawn_cell.y, spawn_cell.z * cpt - cpt)
		if not floor_occupied_cells.has(near_fine_cell):
			continue
		var origin: Vector3i = floor_occupied_cells[near_fine_cell]
		var placement := _find_floor_placement_at(origin)
		if placement == null or placement.parent_id == "":
			continue
		if not ids.has(placement.parent_id):
			ids.append(placement.parent_id)
	return ids


func _find_floor_placement_at(origin_cell: Vector3i) -> TilePlacement:
	for placement in floor_placements:
		if placement.origin_cell == origin_cell:
			return placement
	return null
