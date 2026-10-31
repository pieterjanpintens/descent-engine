class_name Difficulty
extends RefCounted

## The difficulty of a game: a number from 1 to 4 with a name. Chosen when a campaign is started (CampaignSetupPage, kept in
## CampaignState.difficulty) and changeable at embark time, before each mission (EmbarkDialog), never during one; a single mission outside a
## campaign remembers its last choice in PlayerSettings.mission_difficulty.
## Never instantiated, an enum namespace like Vulnerability. Two things use it:
## - monsters: every monster spawns `level_offset()` levels above/below the level its author gave it, so the level scaling
##   tables of its templates (MonsterTemplate.resolve()) give it weaker or stronger numbers;
## - missions: the built-in INT variable `difficulty` (1-4) can be used in any condition, e.g. a spawn condition
##   `difficulty >= 3` for an extra monster, or a Test that needs fewer successes.

const MIN := 1
const MAX := 4
const DEFAULT := 2  ## Adventurer: the game as the author designed it


static func all() -> Array[int]:
	return [1, 2, 3, 4]


static func clamped(value: int) -> int:
	return clampi(value, MIN, MAX)


## How many levels a monster is moved: 1 = -1, 2 = 0 (as designed), 3 = +1, 4 = +2.
static func level_offset(value: int) -> int:
	return clamped(value) - DEFAULT


static func display_name(value: int) -> String:
	match clamped(value):
		1:
			return TranslationServer.translate("Apprentice")
		3:
			return TranslationServer.translate("Veteran")
		4:
			return TranslationServer.translate("Nightmare")
	return TranslationServer.translate("Adventurer")


## "2 - Adventurer", the way the pickers show it.
static func label(value: int) -> String:
	return "%d - %s" % [clamped(value), display_name(value)]


static func description(value: int) -> String:
	match clamped(value):
		1:
			return TranslationServer.translate("Monsters are one level weaker than the author set them, and the mission may go easier on you.")
		3:
			return TranslationServer.translate("Monsters are one level stronger than the author set them, and the mission may be harder on you.")
		4:
			return TranslationServer.translate("Monsters are two levels stronger than the author set them, and the mission may show no mercy.")
	return TranslationServer.translate("The game as the author designed it.")
