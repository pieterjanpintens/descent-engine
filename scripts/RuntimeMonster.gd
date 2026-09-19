class_name RuntimeMonster
extends RefCounted

## One spawned monster, registered in MissionRuntime.monsters. Pure runtime
## state (never saved). Position is deliberately NOT tracked - the original
## game doesn't track monster movement either; can be added later.

var id: String = ""
var folder: String = ""  ## MonsterDisplay.REAL_MONSTERS `folder`, e.g. "wolf"
var chip: int = MonsterChip.Chip.YELLOW  ## which colour chip is on its base
