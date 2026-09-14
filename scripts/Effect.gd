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
## asynchronous - see that class's own doc). All four live in one Type
## rather than separate effect classes so every existing effects list
## (PropAction/MissionTrigger/MissionObjective) gains Show Stage/Remove
## Object/Run Test for free, no second/third/fourth list to add anywhere.

enum Type {
	SET_VARIABLE,
	SHOW_STAGE,
	REMOVE_OBJECT,
	RUN_TEST,
}

@export var type: Type = Type.SET_VARIABLE

## SET_VARIABLE only.
@export var variable_name: String = ""
## SET_VARIABLE only. Checked against the target variable's declared
## MissionVariable.type at evaluation time, not in the Inspector - see
## Condition's own doc for why.
@export var value: Variant = null

## SHOW_STAGE only - the MissionGroup.id to reveal.
@export var target_group_id: String = ""

## REMOVE_OBJECT only - the OutlineNode.id (an InteractableEntry or
## TilePlacement - not a MissionGroup, which has no GridMap presence to
## remove) to erase from the board.
@export var target_object_id: String = ""

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
