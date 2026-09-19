class_name Effect
extends Resource

## Four kinds of thing an effect can do when it fires - the one write
## primitive behind PropAction/MissionTrigger/MissionObjective's own
## effects lists. SET_VARIABLE (default) writes a single named variable
## in the mission's runtime variable registry - deliberately just a SET
## for now (no increment/expression support), matching Condition's "basic
## power first" scope, see that class for the read-side equivalent and why
## value is a loosely-typed Variant. SHOW_STAGE (new 2026-09-14) reveals a
## MissionGroup - see MissionRuntime.apply_effect()/MissionPlayer.
## show_stage() for what "reveal" actually does (a setup dialog listing
## the group's required physical pieces, then making it visible/paintable).
## REMOVE_OBJECT (new 2026-09-14) erases a placed prop or floor/underlay
## tile from the board entirely - e.g. an opened door coming off the
## board, matching the physical game's own rule, rather than just being
## marked "open" - see MissionRuntime.apply_effect()/LayeredMap.remove_node()
## for how removal actually happens. RUN_TEST (new 2026-09-14) is a
## PlayerAttribute roll - see that field group's own doc below and
## MissionRuntime._run_test() for the full mechanism (this is the one Type
## that made MissionRuntime's effect-application chain genuinely
## asynchronous - see that class's own doc). SHOW_MESSAGE (new 2026-09-17)
## just shows the table a plain narrative popup (OK button, no branching) -
## requested for the exact gap it closes: a prop action can already SET a
## variable silently (e.g. "talk to Donal" setting has_key = true), but
## nothing ever told the PLAYERS that happened - "the players are not
## notified of this... we should add an effect that just pops up a dialog
## telling what happened." Reuses the exact same `dialog: PlayerDialog`
## reference RUN_TEST already established as a deliberate, narrow exception
## to "MissionRuntime has no scene/UI access" - see
## MissionRuntime.apply_effect()'s own entry for the one line this adds.
## MOVE_OBJECT (new 2026-09-18) relocates a placed prop or floor/underlay
## tile to a new coordinate - the Story-layer/runtime counterpart to
## CreatorController's own interactive Move mode (see that script's own
## doc), just authored ahead of time instead of dragged live in the
## Creator. Reuses target_object_id (the SAME field REMOVE_OBJECT already
## has - "which placed thing" is identical for both), plus a new
## target_cell for the destination. See MissionRuntime.apply_effect()/
## LayeredMap.move_node() for how the move actually happens, and
## target_cell's own doc below for the coordinate system it's authored in.
## MATH (new 2026-09-18) does basic arithmetic - operand_a OP operand_b,
## written to variable_name (the SAME field SET_VARIABLE already uses for
## its own target). Requested directly as a generalization of
## SET_VARIABLE's plain assignment ("we can already assign a value to a
## property... make effects to do basic math"): +, −, ×, ÷, mod (see
## MathOperator below), where either operand can be a plain authored int
## constant or another declared INT variable's live value - see
## math_operand_a_is_variable's own doc and MissionRuntime._apply_math()
## for the full mechanism.
## All seven live in one Type rather than separate effect classes so every
## existing effects list (PropAction/MissionTrigger/MissionObjective) gains
## all of them for free, no extra list to add anywhere.

enum Type {
	SET_VARIABLE,
	SHOW_STAGE,
	REMOVE_OBJECT,
	RUN_TEST,
	SHOW_MESSAGE,
	MOVE_OBJECT,
	MATH,
	SPAWN_MONSTERS,
}

## SPAWN_MONSTERS (new 2026-09-19) tells the table which monsters to take
## from the box and where on the map to put them - target_object_id is the
## MonsterSpawn's id, spawn_monsters the ordered monster list (see that
## field's own doc). See MissionRuntime.apply_effect()/MissionPlayer.
## _run_monster_spawn().

## MATH only - see Type's own doc above.
enum MathOperator {
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,
	MODULO,
}

@export var type: Type = Type.SET_VARIABLE

## Implicit AND (empty = always fires), same convention as every other
## conditions list in this project (Condition's own doc, PropAction.
## conditions) - gates whether this Effect actually executes at all when
## its list is applied. Requested 2026-09-18 as a genuinely general
## mechanism ("can we make effects also conditional... only execute the
## effect if its condition holds"), checked ONCE in
## MissionRuntime.apply_effect() before it branches on `type` - so it
## applies uniformly to all six Effect.Type kinds for free (a SHOW_MESSAGE
## that only narrates once has_key is true, a MOVE_OBJECT that only
## relocates a prop once a puzzle's own variable is set, ...), not just
## SET_VARIABLE. Same "basic power first, no nesting" scope as Condition
## itself - just an implicit-AND array, nothing fancier.
@export var conditions: Array[Condition] = []

## SET_VARIABLE/MATH - which variable this effect writes ("which variable"
## is identical for both, same reuse convention as target_object_id
## covering REMOVE_OBJECT/MOVE_OBJECT).
@export var variable_name: String = ""
## SET_VARIABLE only. Checked against the target variable's declared
## MissionVariable.type at evaluation time, not in the Inspector - see
## Condition's own doc for why.
@export var value: Variant = null

## SHOW_STAGE only - the MissionGroup.id to reveal.
@export var target_group_id: String = ""

## REMOVE_OBJECT/MOVE_OBJECT - the OutlineNode.id (an InteractableEntry or
## TilePlacement - not a MissionGroup, which has no GridMap presence to
## remove/relocate) to erase from the board, or move.
@export var target_object_id: String = ""

## MOVE_OBJECT only - the destination, authored in TILE-SQUARE ("game
## unit") coordinates, the same human-facing unit CreatorStatusBar shows
## while hovering in the Creator (NOT the finer GridMap cell
## InteractableEntry.origin_cell/TilePlacement.origin_cell actually store -
## converted via FootprintRegistry.tile_square_to_fine_far_corner()
## wherever the move actually happens, see MissionRuntime.apply_effect()/
## MissionPlayer's drain of drain_pending_object_moves()). Y is the
## painting LEVEL, unscaled - matches CreatorController.current_level's
## own convention, only X/Z are tile-square-sized. Targeting a pillar
## (tall/mini/medium) lands it at this tile square's far corner
## specifically, not any other sub-tile-resolution position a pillar could
## otherwise occupy - see tile_square_to_fine_far_corner()'s own doc for
## why that's a real, accepted limitation rather than a bug.
@export var target_cell: Vector3i = Vector3i.ZERO

## RUN_TEST only - which attribute the player rolls.
@export var test_attribute: PlayerAttribute.Attribute = PlayerAttribute.Attribute.WILL
## RUN_TEST only - successes needed to pass. NEVER shown to the player -
## MissionRuntime._run_test() only ever asks "how many successes", never
## states the target, so the table can't game a retry with foreknowledge.
## Only consulted if pass_effects or fail_effects below is non-empty.
@export var required_successes: int = 0
## RUN_TEST only - fires (recursively, via apply_effects()) if the roll met
## required_successes AND at least one of pass_effects/fail_effects is
## non-empty; a Test with both empty skips the comparison entirely (it's
## accumulate-only - see accumulate_variable_name). Either branch can
## itself contain another RUN_TEST effect - Effect containing Array[Effect]
## is genuinely recursive, same self-referential shape as
## MissionObjective.children.
@export var pass_effects: Array[Effect] = []
@export var fail_effects: Array[Effect] = []
## RUN_TEST only, optional - if set, the RAW rolled successes count is
## ADDED (not set) to this declared INT variable, regardless of pass/fail -
## for a test that's repeated toward a larger cumulative total (e.g. "put
## out the fire" needing 20 successes across several attempts) rather than
## a single pass/fail. Independent of pass_effects/fail_effects - a Test
## can accumulate, branch, both, or (pointlessly) neither.
@export var accumulate_variable_name: String = ""

## SHOW_MESSAGE only - the text shown to the table, e.g. "Donal gave you
## the key to the front door." A plain OK-button popup
## (`PlayerDialog.ask_ok()`, already existed for other purposes) - no
## branching, no variable write of its own, purely narrative. Can
## reference message_variables via $1/$2/... placeholders (new
## 2026-09-19, see that field's own doc) - substituted at evaluation time
## by MissionRuntime._format_message(), e.g. "$1 gave you the key" with
## message_variables[0] == "npc_name".
@export var message: String = ""

## SHOW_MESSAGE only, optional - an ORDERED list of declared variable
## names `message` can reference by position: the first entry is $1, the
## second is $2, and so on. Requested directly: "in our shown message
## dialog text we might want to reference variables... the text can
## contain $1, $2 etc that represent entries in the list... at runtime
## these must be replaced with the actual value of that variable." Any
## declared variable (built-in or custom, any type) is valid here - a
## message is narrative text, not a comparison, so there's no reason to
## restrict this the way MATH's operand pickers restrict to INT. A $N
## with no corresponding entry (out of range, or the list is shorter than
## the text expects) substitutes as nothing at runtime, not literal "$N" -
## see MissionRuntime._format_message()'s own doc.
@export var message_variables: Array[String] = []

## MATH only - the arithmetic operator applied to operand_a/operand_b (see
## MathOperator's own doc above), result written to variable_name.
@export var math_operator: MathOperator = MathOperator.ADD

## MATH only - the first operand. `false` (default) reads
## `math_operand_a_literal`, a plain authored int constant; `true` reads
## `math_operand_a_variable`, a declared INT variable's CURRENT value at
## evaluation time - the Creator's own operand picker only ever offers
## INT-typed variables here ("filtered to the ones of type int"), since a
## math result and both its operands are always plain ints, not the
## general Variant Condition/Effect.value otherwise has to support.
@export var math_operand_a_is_variable: bool = false
@export var math_operand_a_literal: int = 0
@export var math_operand_a_variable: String = ""

## MATH only - the second operand, same shape as operand_a above.
@export var math_operand_b_is_variable: bool = false
@export var math_operand_b_literal: int = 0
@export var math_operand_b_variable: String = ""

## SPAWN_MONSTERS only - ORDERED list of monster type folders (the
## lowercase `folder` key of MonsterDisplay.REAL_MONSTERS, e.g. "wolf",
## "blood sister"; repeats allowed). The first monster goes on tile 1 of the
## target MonsterSpawn (target_object_id), the second on tile 2, and so on.
## Extras beyond the spawn's tile count are reported to the table as having
## no free spawn tile. A 2x2 monster (Centurion) uses its tile as its far
## corner and covers the three tiles toward -X/-Z, same convention as
## FootprintRegistry's footprints.
@export var spawn_monsters: Array[String] = []
