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


## Whether the macro can be applied to `target` (a prop, a tile, a group, a monster spawn...).
func fits(_target: OutlineNode) -> bool:
	return false


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
