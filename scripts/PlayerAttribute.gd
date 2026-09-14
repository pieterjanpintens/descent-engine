class_name PlayerAttribute
extends RefCounted

## Never instantiated - just a shared namespace for the Attribute enum, same
## pattern as RoundCheckpoint/HeroCatalog. The four attributes a "Test"
## (see Effect.Type.RUN_TEST / MissionRuntime._run_test()) can be rolled
## against - the engine never computes a hero's actual dice pool or bonuses,
## it only asks for the already-calculated number of successes and compares
## it, so this enum exists purely to label which attribute a Test is about.

enum Attribute {
	INTELLIGENCE,
	WILL,
	AGILITY,
	STRENGTH,
}


static func attribute_name(attribute: Attribute) -> String:
	match attribute:
		Attribute.INTELLIGENCE:
			return "Intelligence"
		Attribute.WILL:
			return "Will"
		Attribute.AGILITY:
			return "Agility"
		Attribute.STRENGTH:
			return "Strength"
	return "?"
