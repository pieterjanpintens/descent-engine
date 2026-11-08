class_name AppliedMacro
extends Resource

## The record a macro leaves on the node it was applied to (OutlineNode.macros): which macro, with which inputs, and what it generated -
## so the author can open "Edit macro" (regenerate with other inputs) or remove it again, and the editor can show which props use a
## macro. Everything the macro generated is ORDINARY mission data (variables, prop actions, triggers) that the runtime treats like
## hand-made data; this record is authoring-side bookkeeping only and the Player ignores it.

## MissionMacro.id() of the macro.
@export var macro_id: String = ""
## The inputs as the author filled them in (MacroParam.id -> value; a LOOT input is an Effect).
@export var values: Dictionary = {}
## What the macro generated, by identity: variable names (MissionData.custom_variables), prop action ids (on the target) and
## trigger ids (MissionData.triggers). Used to find and replace / delete exactly those again.
@export var variable_names: Array[String] = []
@export var action_ids: Array[String] = []
@export var trigger_ids: Array[String] = []
## A text fingerprint of the generated pieces right after they were built: when it no longer matches, the author edited them by
## hand, and regenerating (which replaces them) warns first.
@export var fingerprint: String = ""
