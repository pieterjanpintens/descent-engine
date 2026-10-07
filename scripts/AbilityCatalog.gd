class_name AbilityCatalog
extends RefCounted

## The premade hero abilities (HeroAbility). Never instantiated. INVENTED placeholders for
## testing - replace with the real list; generic ones (any hero) plus two per hero, bound to
## that hero's HeroCatalog slot.


static func all() -> Array[HeroAbility]:
	var list: Array[HeroAbility] = [
		HeroAbility.new("second_wind", "Second Wind", "Once per mission, recover from a hard hit.", 1),
		HeroAbility.new("battle_cry", "Battle Cry", "Shout to give a nearby ally a boost.", 1),
		HeroAbility.new("keen_eye", "Keen Eye", "You notice what others miss.", 2),
		HeroAbility.new("shield_bash", "Shield Bash", "Shove an adjacent monster back.", 3),
		HeroAbility.new("rally", "Rally", "Steady an ally who is close to falling.", 4),
		HeroAbility.new("last_stand", "Last Stand", "Fight on when all seems lost.", 5),
		# Chance
		HeroAbility.new("shadow_step", "Shadow Step", "Slip away from an adjacent monster.", 2, 0),
		HeroAbility.new("backstab", "Backstab", "Strike hard from behind.", 4, 0),
		# Galaden
		HeroAbility.new("hunters_mark", "Hunter's Mark", "Mark a monster for your arrows.", 2, 1),
		HeroAbility.new("quick_shot", "Quick Shot", "Loose an extra arrow.", 4, 1),
		# Brynn
		HeroAbility.new("shield_wall", "Shield Wall", "Guard the allies beside you.", 2, 2),
		HeroAbility.new("rending_strike", "Rending Strike", "A blow that tears armour apart.", 4, 2),
		# Vaerix
		HeroAbility.new("resonance", "Resonance", "Your bell rings out and shakes the foe.", 2, 3),
		HeroAbility.new("toll_of_doom", "Toll of Doom", "A deep note that marks a monster for death.", 4, 3),
		# Kehli
		HeroAbility.new("forge_fire", "Forge Fire", "Heat your hammer until it glows.", 2, 4),
		HeroAbility.new("steady_aim", "Steady Aim", "Take your time and do not miss.", 4, 4),
		# Syrus
		HeroAbility.new("spark", "Spark", "A flicker of fire leaps to a second target.", 2, 5),
		HeroAbility.new("embers", "Embers", "Leave a burning mark behind.", 4, 5),
	]
	return list


static func find(ability_id: String) -> HeroAbility:
	for ability in all():
		if ability.id == ability_id:
			return ability
	return null


## Every ability hero `slot` could equip at `level`.
static func available_for(slot: int, level: int) -> Array[HeroAbility]:
	var fitting: Array[HeroAbility] = []
	for ability in all():
		if ability.fits(slot, level):
			fitting.append(ability)
	return fitting
