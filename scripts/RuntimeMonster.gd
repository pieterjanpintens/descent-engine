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
var defense: int = 0  ## max of the random 0..defense roll subtracted from each hit


## The custom name if one was set, else the type's generic name ("Bandit").
func display_name() -> String:
	if custom_name != "":
		return custom_name
	return MonsterDisplay.find_monster(folder).get("name", folder)
