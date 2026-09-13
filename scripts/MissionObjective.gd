class_name MissionObjective
extends Resource

## One node in a DAG of objectives (reworked 2026-09-12 from a flat,
## checkpoint-keyed list - see claude.md's Story layer section for the
## full design discussion). MissionData.objectives holds the DAG's ROOTS
## (plural roots are fine - e.g. a main quest tree plus an independent
## "all players died" LOSE fail-safe that isn't nested under anything).
##
## "Final objective" is no longer a separate concept or flag - it's simply
## a node with an empty `children` array. Reaching a leaf for real (its own
## `conditions` resolving) actually ends the game with its `outcome` - not
## cosmetic, since a paired LOSE-outcome sibling (or a round-limit baked
## directly into a leaf's own conditions) is how a branch can be lost, not
## just won. A non-leaf node's `conditions` resolving instead advances
## traversal into its `children` - see MissionRuntime's evaluator for the
## exclusive-branch-groups mechanics (children become watched candidates,
## the first whose OWN conditions later hold wins, its siblings are
## dropped - "do A, then based on B do C or D" needs no more than this).
##
## Some conditions can't be computed automatically - the app never sees
## real player positions on the physical board, so e.g. "is a player on
## tile 2a" has to be posed to the table as a yes/no question instead. That
## doesn't need a different Condition shape: the answer just gets written
## into a MissionVariable the normal way (by whatever UI poses the
## question), and the objective's condition reads it like any other
## variable - "asked" is a source a variable's value can come from, not a
## separate kind of condition.

enum Outcome {
	WIN,
	LOSE,
}

@export var id: String = ""
@export var description: String = ""
@export var outcome: Outcome = Outcome.WIN  ## meaningful only when children.is_empty() - i.e. this is a leaf
@export var conditions: Array[Condition] = []  ## implicit AND across all entries - this node's own "achieved" check
@export var effects: Array[Effect] = []  ## applied once when this node's conditions become true

## Tie-break among SIBLINGS - nodes that appear together in the same
## `children` array, or together in MissionData.objectives' own root list.
## Lower is evaluated first, same convention as MissionTrigger.priority.
@export var priority: int = 0

## DAG edges - NOT necessarily a tree. A child instance may be referenced
## from more than one parent's `children` (Resources are reference types,
## so this is just the same instance appearing twice) to let separate
## branches converge back onto a shared node. MissionRuntime warns (does
## not hard-block) if an author accidentally creates a cycle - see that
## script's own doc comment for why a cycle can't actually infinite-loop
## at runtime even if one slips through.
@export var children: Array[MissionObjective] = []

## Side objectives valid ONLY while this node is the currently-active one
## (see MissionRuntime) - they never gate traversal themselves, just fire
## their own `effects` once if their `conditions` become true before this
## node's main conditions do. `children`/`outcome` on an entry here are
## meaningless and left unused by convention (enforced by the authoring
## dialog, not the type system) - an optional objective is never itself a
## DAG node, just a flat side-check attached to one.
@export var optional_objectives: Array[MissionObjective] = []

## Runtime bookkeeping - mirrors MissionTrigger.already_fired. Sits on the
## resource itself (mutated in place by MissionRuntime) rather than a
## separate shadow-state structure, same reasoning as MissionTrigger's own
## field: the Player's loaded MissionData is a fresh instance
## (MissionIO.load_mission()'s CACHE_MODE_IGNORE) never saved back.
@export var already_achieved: bool = false

## The Creator's DAG-editor canvas layout position for this node -
## authoring convenience only, never read by MissionRuntime.
@export var editor_position: Vector2 = Vector2.ZERO
