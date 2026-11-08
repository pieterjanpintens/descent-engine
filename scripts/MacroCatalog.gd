class_name MacroCatalog
extends RefCounted

## The macros the editor offers. Built-in macros are listed in builtin(); register() adds more at run time (tests, later user-defined macros).

static var _registered: Array[MissionMacro] = []


static func builtin() -> Array[MissionMacro]:
	var list: Array[MissionMacro] = [TreasureChestMacro.new(), LockedDoorMacro.new(), ReinforcementsMacro.new()]
	return list


static func register(macro: MissionMacro) -> void:
	for existing in _registered:
		if existing.id() == macro.id():
			_registered.erase(existing)
			break
	_registered.append(macro)


static func unregister(macro_id: String) -> void:
	for existing in _registered:
		if existing.id() == macro_id:
			_registered.erase(existing)
			return


static func all() -> Array[MissionMacro]:
	var list := builtin()
	list.append_array(_registered)
	return list


static func find(macro_id: String) -> MissionMacro:
	for macro in all():
		if macro.id() == macro_id:
			return macro
	return null


## The macro that fits a piece mesh and has the id (for the AI stage generator), or null.
static func for_plan(macro_id: String, mesh: String) -> MissionMacro:
	var macro := find(macro_id)
	if macro != null and macro.plan_hint() != "" and macro.fits_mesh(mesh):
		return macro
	return null


## The lines telling the AI which macros a planned piece may carry ("" when none is offered).
static func describe_for_ai() -> String:
	var lines: Array[String] = []
	for macro in all():
		if macro.plan_hint() != "":
			lines.append("- " + macro.plan_hint())
	return "
".join(lines)


## The macros that can be applied to `target`.
static func for_target(target: OutlineNode) -> Array[MissionMacro]:
	var list: Array[MissionMacro] = []
	for macro in all():
		if macro.fits(target):
			list.append(macro)
	return list
