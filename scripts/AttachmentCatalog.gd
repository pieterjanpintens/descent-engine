class_name AttachmentCatalog
extends RefCounted

## The premade weapon attachments (WeaponAttachment) heroes can equip at embark. Never
## instantiated. INVENTED placeholders for testing - replace/extend with the real list;
## each entry says where it can be attached (weapon type, and optionally a hero/weapon
## slot) and which condition it applies with what chance.


## Fresh instances every call (a hero's weapon owns its attachments).
static func all() -> Array[WeaponAttachment]:
	var list: Array[WeaponAttachment] = [
		WeaponAttachment.new("Rattling Charm", MonsterCondition.Kind.DAZED, 10),
		WeaponAttachment.new("Stunning Blow", MonsterCondition.Kind.DAZED, 30, "Warhammer"),
		WeaponAttachment.new("Thunder Strike", MonsterCondition.Kind.DAZED, 25, "Hammer"),
		WeaponAttachment.new("Resonant Toll", MonsterCondition.Kind.DAZED, 40, "War Bell"),
		WeaponAttachment.new("Venomed Edge", MonsterCondition.Kind.AFFLICTED, 25, "Sword"),
		WeaponAttachment.new("Burning Bolts", MonsterCondition.Kind.AFFLICTED, 20, "Crossbow"),
		WeaponAttachment.new("Hamstring", MonsterCondition.Kind.SLOWED, 30, "Throwing Knives"),
		WeaponAttachment.new("Sapping Strike", MonsterCondition.Kind.ENFEEBLED, 30, "Gloves"),
		WeaponAttachment.new("Piercing Shot", MonsterCondition.Kind.EXPOSED, 25, "Bow"),
		WeaponAttachment.new("Mind Fog", MonsterCondition.Kind.CONFUSED, 20, "Wand"),
		WeaponAttachment.new("Doom Mark", MonsterCondition.Kind.DOOMED, 15, "Staff"),
		# Bound to ONE hero's weapon: Weapon 1 (a sword) of Brynn.
		WeaponAttachment.new("Oathkeeper's Mark", MonsterCondition.Kind.EXPOSED, 35, "Sword", 2, 0),
	]
	return list


## The attachments that fit weapon slot `weapon_index` of hero `slot` (type `weapon_type`).
static func for_weapon(slot: int, weapon_index: int, weapon_type: String) -> Array[WeaponAttachment]:
	var real := WeaponData.attachments_for_type(weapon_type)  # the real B and C parts, from the user's own export
	if not real.is_empty():
		return real
	var fitting: Array[WeaponAttachment] = []
	for attachment in all():
		if attachment.fits(slot, weapon_index, weapon_type):
			fitting.append(attachment)
	return fitting
