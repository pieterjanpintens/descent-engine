class_name TrinketBenefits
extends RefCounted

## The "benefits" that Wanderer's Stone, Fae Crystal and Horn of Courage hand out. They are resolved at the table (the app only picks one and
## reports it in a popup). Never instantiated.

const BASIC: Array[String] = [
	"Heal 2",
	"Prepare a card",
	"Focus 2 cards",
	"Remove a single condition",
	"Shift 1",
]
const ADVANCED: Array[String] = [
	"Heal 4",
	"Prepare 2 cards",
	"Remove all conditions of a given type",
	"Remove all fatigue from a single card",
	"Flip your hero card",
]
## Wanderer's Stone and Fae Crystal draw from the basic list 75% of the time and from the advanced list 25%.
const BASIC_CHANCE := 0.75


## A random benefit: `advanced_only` (Horn of Courage) always comes from the advanced list, otherwise 75% basic / 25% advanced.
static func pick(advanced_only: bool = false) -> String:
	var pool: Array[String] = ADVANCED if advanced_only or randf() >= BASIC_CHANCE else BASIC
	return pool.pick_random()
