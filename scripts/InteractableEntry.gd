class_name InteractableEntry
extends Resource

enum Type {
	PROP,       ## purely decorative or minor interaction (bookshelf, well, table)
	DOOR,
	OBJECTIVE,
	HAZARD,
	LEVEL_LINK, ## stairs, ramps, ledges - anything connecting cells at different Y
}

@export var type: Type = Type.PROP

## Stable identity for the Creator's outline tree (see CreatorOutline.gd) -
## assigned once via MissionData.allocate_object_id() when the object is
## first placed, never regenerated. Distinct from reference_name below:
## this is an internal bookkeeping id nobody types by hand and nothing in
## the Story layer reads, reference_name is the human-facing, optional,
## Story-layer-facing one. LayeredMap.sync_prop_cell() must carry this
## field over when an already-placed cell gets repainted (it otherwise
## erases and recreates the entry from scratch) - see that function's own
## comment.
@export var id: String = ""

## Empty = this object sits directly under the mission root in the
## outline tree. Otherwise a MissionGroup's id. See CreatorOutline.gd.
@export var parent_id: String = ""

## Optional, empty by default - lets the map designer give a specific
## instance a human-chosen identifier (e.g. "front_door") so OTHER
## props/triggers can reference its state in a Condition/Effect, e.g. a
## trap's trigger might read variable_name "front_door.open" to check it,
## while the door's own "open" PropAction writes that same variable_name in
## its effects. This needs no special resolution mechanism - variable names
## are already free-form strings in the runtime's flat registry (see
## MissionVariable/Condition/Effect in claude.md's Story layer section), so
## reference_name is purely an authoring convention for constructing
## readable, collision-avoiding variable names, not something the engine
## looks up by itself. Should be unique per mission when set - not yet
## validated in-editor.
@export var reference_name: String = ""
@export var mesh_item_name: String = ""   ## matches the GridMap MeshLibrary item
@export var origin_cell: Vector3i = Vector3i.ZERO
@export var footprint: Array[Vector3i] = [Vector3i.ZERO]  ## cell offsets from origin_cell, already rotation-adjusted, see FootprintRegistry
@export var orientation: int = 0                ## GridMap cell orientation index (0-23)
@export var blocks_movement: bool = true
@export var blocks_los: bool = false
## Free-form: linked_region, locked, loot_table, etc. Two keys are
## well-known and read by the runtime directly: "visible" (bool - hidden
## props don't render/aren't interactable until some effect flips it, e.g.
## a secret passage revealed by searching a bookshelf) and "interactible"
## (bool - toggles whether this prop's actions[] can currently be used).
## Both default to true when absent.
@export var props: Dictionary = {}
## What a player can report doing to this prop (push a lever, search a
## bookshelf) - see PropAction. Empty means purely decorative, nothing to
## report.
@export var actions: Array[PropAction] = []

## Only meaningful when type == LEVEL_LINK. Two cells this connector joins -
## covers both "real" floor-to-floor stairs (large Y difference) and a
## localized dais/ledge step within one room (often just Y+1). Movement/LOS
## logic should treat these as an explicit traversable link rather than
## assuming any adjacency between cells at different Y.
@export var link_from_cell: Vector3i = Vector3i.ZERO
@export var link_to_cell: Vector3i = Vector3i.ZERO
@export var link_bidirectional: bool = true
