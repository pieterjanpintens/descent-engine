class_name OutlineNode
extends Resource

## Shared base for everything that can appear as its own node in the
## Creator's outline tree (see CreatorOutline.gd): InteractableEntry
## (props/doors/hazards/level-links), TilePlacement (floor/underlay
## tiles), and MissionGroup. Pulled out 2026-09-10 once all three ended up
## needing the exact same four fields - one definition instead of three
## copies to keep in sync.

## Stable identity for the outline tree - assigned once via
## MissionData.allocate_object_id() when the node is first created, never
## regenerated. Distinct from reference_name below: this is an internal
## bookkeeping id nobody types by hand and nothing in the Story layer
## reads; reference_name is the human-facing, optional, Story-layer-facing
## one. A caller that reconstructs one of these from scratch (e.g.
## LayeredMap.sync_prop_cell()/rebuild_floor_tiles()'s erase-then-recreate
## pattern) must carry this field over from whatever was there before, or
## it silently orphans the node's outline-tree identity and group
## membership - see those functions' own comments.
@export var id: String = ""

## Empty = this node sits directly under the mission root in the outline
## tree. Otherwise a MissionGroup's id. See CreatorOutline.gd.
@export var parent_id: String = ""

## Optional, empty by default - a human-chosen identifier (e.g.
## "front_door") so OTHER props/triggers can reference this node's state
## in a Condition/Effect, e.g. a trap's trigger might read variable_name
## "front_door.open" to check it, while the door's own "open" PropAction
## writes that same variable_name in its effects. This needs no special
## resolution mechanism - variable names are already free-form strings in
## the runtime's flat registry (see MissionVariable/Condition/Effect in
## claude.md's Story layer section), so reference_name is purely an
## authoring convention for constructing readable, collision-avoiding
## variable names, not something the engine looks up by itself. Should be
## unique per mission when set - not yet validated in-editor. Also doubles
## as the outline tree's display label when set (falls back to the node's
## mesh name, or a generic placeholder for an unnamed MissionGroup).
@export var reference_name: String = ""

## Whether this node is currently visible/active - e.g. a secret passage
## prop hidden until some effect flips it. Deliberately a plain top-level
## bool rather than a free-form dict key: it's common enough to every
## OutlineNode to earn a real field. InteractableEntry.props is where
## anything ELSE free-form still lives (see that script's own comment) -
## keeping this one out of that dict was a deliberate simplification
## (2026-09-10), moved from what used to be InteractableEntry's own
## props["visible"] convention. Not yet consumed by any evaluator/renderer
## - the Story layer has no runtime trigger/effect evaluator at all yet
## (see claude.md's Story layer section), so wiring this into an actual
## Effect, or a MissionGroup's own visible cascading to its members, is
## future work, not this pass.
@export var visible: bool = true
