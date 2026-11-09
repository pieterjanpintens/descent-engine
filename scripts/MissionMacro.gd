class_name MissionMacro
extends RefCounted

## A macro: a named recipe with a few inputs that, applied to something in a mission (first: a prop), GENERATES ordinary mission data -
## variables, prop actions, triggers - so simple things need no manual wiring. Nothing about a macro exists at play time: the runtime only
## ever sees the generated data, which the author can still edit by hand in the normal dialogs. See MacroEngine (apply / regenerate /
## remove, with the bookkeeping in AppliedMacro) and MacroDialog (the input form, generated from params()).
##
## To write a macro: extend this class, override id() / title() / description() / fits() / params() / build(), and list it in
## MacroCatalog. build() must create everything through the MacroContext (ctx.variable(), ctx.action(), ctx.trigger()), never by
## appending to the mission directly, so the engine knows what to replace or delete later.

## Stable id (saved in AppliedMacro.macro_id - never change it once released).
func id() -> String:
	return ""


## What the author sees in lists and as the dialog title.
func title() -> String:
	return id()


## One or two sentences: what the macro does, shown at the top of its dialog.
func description() -> String:
	return ""


## Whether the same macro may be applied to one node more than once (most make no sense twice: a chest opens once).
func repeatable() -> bool:
	return false


## Whether the macro can be applied to `target` (a prop, a tile, a group, a monster spawn...).
func fits(_target: OutlineNode) -> bool:
	return false


## Whether a prop made of this mesh (a piece name like "chest") could take the macro - what the AI stage generator asks before it applies one
## to a piece it planned. Macros for props override this and let fits() use it.
func fits_mesh(_mesh: String) -> bool:
	return false


## "" when the AI stage generator may not use this macro; else one line telling the AI how to ask for it on a piece:
## the "macro" object of the piece (its keys) and what it does. See values_from_plan().
func plan_hint() -> String:
	return ""


## The inputs from the "macro" object of a planned piece (the AI's answer, so nothing is trusted): every param whose id is a key is read and
## clamped / matched (a CHOICE by its label, case-insensitive, or its value); other keys are ignored; the rest stays at its default.
## A LOOT param is built from a "gold" number. Override for other shapes.
func values_from_plan(data: Dictionary) -> Dictionary:
	var values := default_values()
	for param in params():
		match param.kind:
			MacroParam.Kind.INT:
				if data.has(param.id) and (typeof(data[param.id]) == TYPE_INT or typeof(data[param.id]) == TYPE_FLOAT):
					values[param.id] = clampi(int(data[param.id]), param.min_value, param.max_value)
			MacroParam.Kind.BOOL:
				if data.has(param.id) and typeof(data[param.id]) == TYPE_BOOL:
					values[param.id] = data[param.id]
			MacroParam.Kind.TEXT:
				if data.has(param.id) and typeof(data[param.id]) == TYPE_STRING:
					values[param.id] = str(data[param.id]).substr(0, 200)
			MacroParam.Kind.CHOICE:
				if data.has(param.id):
					for choice in param.choices:
						if str(data[param.id]).to_lower() == str(choice[0]).to_lower() or (typeof(data[param.id]) == typeof(choice[1]) and data[param.id] == choice[1]):
							values[param.id] = choice[1]
			MacroParam.Kind.LOOT:
				var gold: Variant = data.get("gold", 0)
				if (typeof(gold) == TYPE_INT or typeof(gold) == TYPE_FLOAT) and int(gold) > 0:
					(values[param.id] as Effect).loot_materials = {LootMaterials.GOLD: clampi(int(gold), 1, 9999)}
	return values


## The inputs, in the order the dialog shows them.
func params() -> Array[MacroParam]:
	return []


## "" when `values` are usable, else what is wrong (shown in the dialog; Apply stays disabled). The base class checks nothing; override
## for rules between inputs.
func problem(_values: Dictionary) -> String:
	return ""


## Generates the data. `values` has one entry per param (MacroParam.id -> value, already complete: see completed()).
func build(_ctx: MacroContext, _values: Dictionary) -> void:
	pass


## One default value per param.
func default_values() -> Dictionary:
	var values := {}
	for param in params():
		values[param.id] = param.make_default()
	return values


## `values` completed with the defaults of any param it does not have (an older record, a macro that gained an input).
func completed(values: Dictionary) -> Dictionary:
	var result := default_values()
	for key in values:
		if result.has(key):
			result[key] = values[key]
	return result
