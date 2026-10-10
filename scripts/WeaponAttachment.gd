class_name WeaponAttachment
extends Resource

## A premade attachment ("secondary ability") a hero can equip on a weapon at embark
## (EmbarkDialog.ask_loadouts()); a weapon has at most MAX_PER_WEAPON of them and by
## default none. Each time the hero attacks with the weapon, every attachment gets a roll:
## with `chance_percent` it TRIGGERS and applies its `condition` to the monster hit
## (PlayerInteractionController.attack() - a monster immune to the condition resists it, as
## for a condition chosen by the table). The premade list is AttachmentCatalog.
##
## Where it can be attached is limited by `hero_slot` (HeroCatalog slot, -1 = any hero),
## `weapon_index` (0 = Weapon 1, 1 = Weapon 2, -1 = either) and `weapon_type`
## (WeaponCatalog type name such as "Sword", "" = any type): "Weapon 1 (sword) of Brynn".

const MAX_PER_WEAPON := 2

@export var attachment_name: String = ""
@export var hero_slot: int = -1
@export var weapon_index: int = -1
@export var weapon_type: String = ""
## The ability that can trigger: a MonsterCondition.Kind applied to the monster.
@export var condition: MonsterCondition.Kind = MonsterCondition.Kind.DAZED
@export_range(0, 100) var chance_percent: int = 25
## A real weapon part (WeaponData): "B" (guard / haft) or "C" (hilt / pommel) - a weapon has one slot of each. "" = any
## (the invented premade attachments). A real part has `ability_name`/`ability_text` from the game's data, which is
## information for the table only: it never triggers by itself (chance 0), the table applies it.
@export var part_slot: String = ""
## The game's id of the part ("WEAPON_PART_B_SWORD_1") - what campaign offers and the owned list refer to.
@export var part_id: String = ""
@export var ability_name: String = ""
@export_multiline var ability_text: String = ""


func _init(p_name: String = "", p_condition: int = MonsterCondition.Kind.DAZED, p_chance: int = 25, p_weapon_type: String = "", p_hero_slot: int = -1, p_weapon_index: int = -1) -> void:
	attachment_name = p_name
	condition = p_condition as MonsterCondition.Kind
	chance_percent = p_chance
	weapon_type = p_weapon_type
	hero_slot = p_hero_slot
	weapon_index = p_weapon_index


## Can it be equipped on weapon slot `p_weapon_index` of hero `p_hero_slot`, whose type is `p_type`?
func fits(p_hero_slot: int, p_weapon_index: int, p_type: String) -> bool:
	return (hero_slot < 0 or hero_slot == p_hero_slot) \
		and (weapon_index < 0 or weapon_index == p_weapon_index) \
		and (weapon_type == "" or weapon_type == p_type)


## "Stunning Blow - Dazed 30%".
func summary() -> String:
	if ability_text != "":
		return "%s - %s" % [attachment_name, ability_name]
	return "%s - %s %d%%" % [attachment_name, MonsterCondition.display_name(condition), chance_percent]


## summary() plus, for a real part, what its ability does.
func detail() -> String:
	if ability_text != "":
		return "%s: %s" % [summary(), ability_text]
	return summary()


## The chance against a target that is (not) Dazed: a Dazed monster adds
## MonsterCondition.DAZED_ATTACHMENT_BONUS_PERCENT points (capped at 100).
func effective_chance(target_dazed: bool) -> int:
	return mini(chance_percent + (MonsterCondition.DAZED_ATTACHMENT_BONUS_PERCENT if target_dazed else 0), 100)


## Rolls the chance: true if the ability triggers this attack.
func roll(target_dazed: bool = false) -> bool:
	return randf() * 100.0 < float(effective_chance(target_dazed))
