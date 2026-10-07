class_name HeroState
extends Resource

## One hero's progress in a campaign - what carries over from mission to mission: experience
## (which gives the level) and the abilities equipped. Everything else about a hero (wounds,
## weapons picked at embark) is per mission. The rules come from the campaign's
## HeroProgression; abilities from AbilityCatalog.

@export var hero_slot: int = 0  ## HeroCatalog slot
@export var experience: int = 0
@export var equipped_abilities: Array[String] = []  ## HeroAbility ids


func level(progression: HeroProgression) -> int:
	return progression.level_for(experience)


func slots(progression: HeroProgression) -> int:
	return progression.slots_for(level(progression))


## The abilities this hero could equip at their current level (equipped ones included).
func available_abilities(progression: HeroProgression) -> Array[HeroAbility]:
	return AbilityCatalog.available_for(hero_slot, level(progression))


## Whether `ability_id` can be equipped now: a known ability that fits this hero and level,
## not already equipped, with a free slot.
func can_equip(ability_id: String, progression: HeroProgression) -> bool:
	var ability := AbilityCatalog.find(ability_id)
	return ability != null \
		and ability.fits(hero_slot, level(progression)) \
		and not equipped_abilities.has(ability_id) \
		and equipped_abilities.size() < slots(progression)


func equip(ability_id: String, progression: HeroProgression) -> bool:
	if not can_equip(ability_id, progression):
		return false
	equipped_abilities.append(ability_id)
	return true


func unequip(ability_id: String) -> void:
	equipped_abilities.erase(ability_id)


## Adds experience; returns the levels newly reached (e.g. [2, 3]), empty if none.
func add_experience(amount: int, progression: HeroProgression) -> Array[int]:
	var before := level(progression)
	experience = maxi(experience + amount, 0)
	var gained: Array[int] = []
	for reached in range(before + 1, level(progression) + 1):
		gained.append(reached)
	return gained
