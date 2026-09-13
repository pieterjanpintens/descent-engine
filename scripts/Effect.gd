class_name Effect
extends Resource

## Three kinds of thing an effect can do when it fires - the one write
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
## for how removal actually happens. All three live in one Type rather than
## separate effect classes so every existing effects list
## (PropAction/MissionTrigger/MissionObjective) gains Show Stage/Remove
## Object for free, no second/third list to add anywhere.

enum Type {
	SET_VARIABLE,
	SHOW_STAGE,
	REMOVE_OBJECT,
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
