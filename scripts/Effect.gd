class_name Effect
extends Resource

## Two kinds of thing an effect can do when it fires - the one write
## primitive behind PropAction/MissionTrigger/MissionObjective's own
## effects lists. SET_VARIABLE (default) writes a single named variable
## in the mission's runtime variable registry - deliberately just a SET
## for now (no increment/expression support), matching Condition's "basic
## power first" scope, see that class for the read-side equivalent and why
## value is a loosely-typed Variant. SHOW_STAGE (new 2026-09-14) reveals a
## MissionGroup - see MissionRuntime.apply_effect()/MissionPlayer.
## show_stage() for what "reveal" actually does (a setup dialog listing
## the group's required physical pieces, then making it visible/paintable).
## Both live in one Type rather than a separate effect class so every
## existing effects list (PropAction/MissionTrigger/MissionObjective) gains
## Show Stage for free, no second list to add anywhere.

enum Type {
	SET_VARIABLE,
	SHOW_STAGE,
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
