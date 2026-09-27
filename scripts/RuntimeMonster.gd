class_name RuntimeMonster
extends RefCounted

## One spawned monster, registered in MissionRuntime.monsters. Pure runtime
## state (never saved), initialised from the MonsterTemplate the spawn effect
## specified. Position is deliberately NOT tracked - the original game
## doesn't track monster movement either; can be added later.

var id: String = ""
var folder: String = ""  ## MonsterDisplay.REAL_MONSTERS `folder`, e.g. "wolf"
var chip: int = MonsterChip.Chip.YELLOW  ## which colour chip is on its base
var custom_name: String = ""  ## empty = generic type name
var hitpoints: int = 20
var level: int = 1
var weaknesses: Array[int] = []  ## Vulnerability.Kind values
var resistances: Array[int] = []
var immunities: Array[int] = []
## Discovered by hitting the monster with a matching damage type (see
## MissionRuntime.resolve_attack()); the combat screen shows "?" until then.
var known_weaknesses: Array[int] = []
var known_resistances: Array[int] = []
var known_immunities: Array[int] = []
var defense: int = 0  ## max of the random 0..defense roll subtracted from each hit


## The custom name if one was set, else the type's generic name ("Bandit").
func display_name() -> String:
	if custom_name != "":
		return custom_name
	return MonsterDisplay.find_monster(folder).get("name", folder)


## Plain-data round trip for SaveGame - this class is RefCounted, not a
## Resource, so it can't be embedded directly in a Resource's exported
## field; a save just carries a Dictionary of these fields instead.
func to_dict() -> Dictionary:
	return {
		"id": id, "folder": folder, "chip": chip, "custom_name": custom_name,
		"hitpoints": hitpoints, "level": level, "defense": defense,
		"weaknesses": weaknesses.duplicate(), "resistances": resistances.duplicate(), "immunities": immunities.duplicate(),
		"known_weaknesses": known_weaknesses.duplicate(), "known_resistances": known_resistances.duplicate(), "known_immunities": known_immunities.duplicate(),
	}


static func from_dict(d: Dictionary) -> RuntimeMonster:
	var m := RuntimeMonster.new()
	m.id = d.get("id", "")
	m.folder = d.get("folder", "")
	m.chip = d.get("chip", MonsterChip.Chip.YELLOW)
	m.custom_name = d.get("custom_name", "")
	m.hitpoints = d.get("hitpoints", 20)
	m.level = d.get("level", 1)
	m.defense = d.get("defense", 0)
	m.weaknesses = _int_array(d.get("weaknesses", []))
	m.resistances = _int_array(d.get("resistances", []))
	m.immunities = _int_array(d.get("immunities", []))
	m.known_weaknesses = _int_array(d.get("known_weaknesses", []))
	m.known_resistances = _int_array(d.get("known_resistances", []))
	m.known_immunities = _int_array(d.get("known_immunities", []))
	return m


## A save's Dictionary values come back from disk as plain untyped Arrays -
## copy element-by-element into a real Array[int] rather than relying on
## implicit conversion.
static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for v in values:
		result.append(int(v))
	return result
