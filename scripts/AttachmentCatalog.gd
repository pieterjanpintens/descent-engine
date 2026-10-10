class_name AttachmentCatalog
extends RefCounted

## The weapon attachments (WeaponAttachment) heroes can equip at embark: the game's real B and C weapon parts, read by
## WeaponData from the user's own export (tools/asset_import/import_weapon_data.py). Never instantiated. Without the
## export there are none. An attachment is identified by its game part id (WeaponAttachment.part_id, e.g.
## "WEAPON_PART_B_SWORD_1") - campaign offers and the party's owned list store that id, because display names are
## not unique ("Spiked Grip").


## Every attachment of every weapon type - fresh instances each call (a hero's weapon owns its attachments).
static func all() -> Array[WeaponAttachment]:
	var list: Array[WeaponAttachment] = []
	for type_name: String in WeaponData.TYPE_TO_GAME_WEAPON:
		list.append_array(WeaponData.attachments_for_type(type_name))
	return list


## The attachments that fit a weapon of type `weapon_type` (the parts of that weapon).
static func for_weapon(_slot: int, _weapon_index: int, weapon_type: String, include_upgrades: bool = false) -> Array[WeaponAttachment]:
	return WeaponData.attachments_for_type(weapon_type, include_upgrades)


## The attachment with this part id, null if unknown.
static func find(part_id: String) -> WeaponAttachment:
	for attachment in all():
		if attachment.part_id == part_id:
			return attachment
	return null


## "Northrider Guard (Sword, part B)" for pickers and shop texts; the id itself when it is unknown.
static func label(part_id: String) -> String:
	var attachment := find(part_id)
	if attachment == null:
		return part_id
	return "%s (%s, part %s)" % [attachment.attachment_name, attachment.weapon_type, attachment.part_slot]
