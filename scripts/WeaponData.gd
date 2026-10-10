class_name WeaponData
extends RefCounted

## The game's real weapon data, read from the user's own export (tools/asset_import/import_weapon_data.py writes
## user://weapon_data/weapons.json + localization_en.json; nothing of it ships with the project). Never instantiated.
## WeaponCatalog.weapons_of_type() uses it when it is there and falls back to its invented placeholders otherwise.
##
## One real weapon = the A part of a weapon card (the blade / head: the damage, the damage types and the secondary
## ability); parts B and C add nothing to the numbers. Every A part has an upgraded "+" twin (more damage, often an
## extra damage type). Both are offered, the upgraded one named "<name>+".

const DIRECTORY := "user://weapon_data/"

## Our weapon TYPE names (WeaponCatalog.HERO_WEAPON_TYPES) -> the game's WeaponModel id.
const TYPE_TO_GAME_WEAPON := {
	"Gloves": "WEAPON_KUKRI",
	"Throwing Knives": "WEAPON_THROWING_KNIVES",
	"Bow": "WEAPON_BOW",
	"Sword": "WEAPON_SWORD",
	"Staff": "WEAPON_STAFF",
	"War Bell": "WEAPON_WARBELL",
	"Hammer": "WEAPON_HAMMER",
	"Crossbow": "WEAPON_CROSSBOW",
	"Wand": "WEAPON_WAND_OF_WINDS",
	"Warhammer": "WEAPON_WAR_HAMMER",
	"Spear": "WEAPON_SPEAR",
	"Dual Blades": "WEAPON_DUAL_BLADES",
}

## The game's damage `Traits` numbers -> Vulnerability.Kind. 0-2 are certain (hammers / swords / bows and knives);
## confirmed by the user: 4 (Wing Blade+ = Anemos), 6 (Rebound Hammer+ = Terros), 7 (Ancestral Blade = Lumos), 8
## (Relentless Gauntlet+ = Umbros), 9 (Dragonsbane+ = Vigos), 10 (Life-Drinking Gauntlet+ = Mortos) and 3 (Sunburst+ =
## Lumos and Ignos). Only 5 (water: Ice Storm) is still a guess from the part name. 11 (Warping Wand+) is unknown - the
## game also has Fortunos and Toxos damage icons, not in our kinds yet - and is skipped.
const TRAIT_TO_KIND := {
	0: Vulnerability.Kind.CRUSH,
	1: Vulnerability.Kind.SLASH,
	2: Vulnerability.Kind.PIERCE,
	3: Vulnerability.Kind.IGNOS,
	4: Vulnerability.Kind.ANEMOS,
	5: Vulnerability.Kind.AQUOS,
	6: Vulnerability.Kind.TERROS,
	7: Vulnerability.Kind.LUMOS,
	8: Vulnerability.Kind.UMBROS,
	9: Vulnerability.Kind.VIGOS,
	10: Vulnerability.Kind.MORTOS,
}

## The game data only says 0 melee / 1 reach / 2 ranged (`RangeApproximation`, per weapon type) - the real distance is
## not in the files we can read (no range field on parts or abilities, no range in any text; the part pictures don't
## show it either, so it is probably game code). Ranged weapons therefore get this range (squares), known from play...
const RANGED_RANGE := 4
## ...except these parts, whose range is known to differ (part id -> range): the Oakroot Wand (and its upgrade) has 5.
const RANGE_BY_PART := {
	"WEAPON_PART_A_WAND_2": 5,
	"WEAPON_PART_A_WAND_2_UPGRADED": 5,
	"WEAPON_PART_A_CROSSBOW_1": 3,  # True Aim Crossbow (the upgraded one has the normal 4)
	"WEAPON_PART_A_CROSSBOW_2": 3,  # Dualpower Crossbow (the upgraded one has the normal 4)
	"WEAPON_PART_A_CROSSBOW_3": 3,  # Elfweave Crossbow, both versions
	"WEAPON_PART_A_CROSSBOW_3_UPGRADED": 3,
	"WEAPON_PART_A_CROSSBOW_4": 3,  # Kickback Crossbow, both versions
	"WEAPON_PART_A_CROSSBOW_4_UPGRADED": 3,
	"WEAPON_PART_A_CROSSBOW_5_UPGRADED": 5,  # Longsight Crossbow+
	"WEAPON_PART_A_SUNBURST": 3,  # Sunburst (the upgraded one has the normal 4)
	"WEAPON_PART_A_RUNE_OF_BLADES": 3,
	"WEAPON_PART_A_RUNE_OF_BLADES_UPGRADED": 3,
}

static var _loaded := false
static var _weapons: Dictionary = {}    # game weapon id -> entry
static var _parts: Array = []
static var _parts_by_id: Dictionary = {}
static var _abilities: Dictionary = {}  # ability id -> entry
static var _texts: Dictionary = {}
static var _cache: Dictionary = {}      # type name -> Array[Weapon]
static var _icons: Dictionary = {}  # icon path -> Texture2D (or null: not exported)
static var _attachment_cache: Dictionary = {}  # type name -> Array[WeaponAttachment]


## The icon picture of a part (its `icon_path`) from the user's own export (import_weapon_data.py writes the pictures to
## user://weapon_data/images/ under the game's path, lower case, without the leading "d3/"); null when it isn't there.
static func icon_for(icon_path: String) -> Texture2D:
	if icon_path == "":
		return null
	if _icons.has(icon_path):
		return _icons[icon_path]
	var relative := icon_path.to_lower()
	if relative.begins_with("d3/"):
		relative = relative.substr(3)
	var file := DIRECTORY + "images/" + relative
	var texture: Texture2D = null
	if FileAccess.file_exists(file):
		var image := Image.load_from_file(file)
		if image != null:
			texture = ImageTexture.create_from_image(image)
	_icons[icon_path] = texture
	return texture


static func available() -> bool:
	_load()
	return not _weapons.is_empty()


## Forget what was read (a fresh export, or a test).
static func reload() -> void:
	_loaded = false
	_cache.clear()
	_attachment_cache.clear()
	_weapons.clear()
	_parts.clear()
	_parts_by_id.clear()
	_abilities.clear()
	_texts.clear()


## Fresh Weapon instances for every A part of the game weapon behind `type_name`, base versions first then the
## upgraded ones; empty when there is no export or the type is unknown.
static func weapons_for_type(type_name: String, include_upgrades: bool = false) -> Array[Weapon]:
	_load()
	var result: Array[Weapon] = []
	var game_id: String = TYPE_TO_GAME_WEAPON.get(type_name, "")
	if game_id == "" or not _weapons.has(game_id):
		return result
	var cache_key := type_name + ("+" if include_upgrades else "")
	if not _cache.has(cache_key):
		_cache[cache_key] = _build(_weapons[game_id], include_upgrades)
	for template: Weapon in _cache[cache_key]:
		result.append(template.duplicate(true))
	return result


## Fresh WeaponAttachment instances for every B and C part of the weapon behind `type_name` that has an ability (the
## starter guard / hilt do nothing and count as "none"), base versions first then the upgraded ones.
static func attachments_for_type(type_name: String, include_upgrades: bool = false) -> Array[WeaponAttachment]:
	_load()
	var result: Array[WeaponAttachment] = []
	var game_id: String = TYPE_TO_GAME_WEAPON.get(type_name, "")
	if game_id == "" or not _weapons.has(game_id):
		return result
	var cache_key := type_name + ("+" if include_upgrades else "")
	if _attachment_cache.has(cache_key):
		for cached: WeaponAttachment in _attachment_cache[cache_key]:
			result.append(cached.duplicate(true))
		return result
	var parts: Array = []
	for part: Dictionary in _parts:
		if part["Class"] == _weapons[game_id]["Class"] and (part["Slot"] == 1 or part["Slot"] == 2) and _abilities.has(part["Ability"]) and (include_upgrades or part["IsUpgrade"] == 0):
			parts.append(part)
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["Slot"] != b["Slot"]:
			return a["Slot"] < b["Slot"]
		if a["IsUpgrade"] != b["IsUpgrade"]:
			return a["IsUpgrade"] < b["IsUpgrade"]
		return str(a["_id"]) < str(b["_id"]))
	for part: Dictionary in parts:
		result.append(_attachment_from_part(part, type_name))
	_attachment_cache[cache_key] = result.duplicate()
	return result


## The rune weapons (and Dragonsbane): global weapons that belong to no hero. Unlike a normal weapon a rune has its B
## and C part FIXED - they can't be chosen - so they come attached already. Base versions first, then the upgraded A
## versions (which keep the same B and C). Fresh instances each call.
static func runes(include_upgrades: bool = false) -> Array[Weapon]:
	_load()
	var result: Array[Weapon] = []
	var upgraded: Array[Weapon] = []
	var ids: Array = _weapons.keys()
	ids.sort()
	for game_id: String in ids:
		var game_weapon: Dictionary = _weapons[game_id]
		if game_weapon["IsGlobal"] != 1:
			continue
		var part_a := {}
		var fixed_parts: Array[Dictionary] = []
		for part_id: String in game_weapon["StartingWeaponParts"]:
			var part: Dictionary = _parts_by_id.get(part_id, {})
			if part.is_empty():
				continue
			if part["Slot"] == 0:
				part_a = part
			elif _abilities.has(part["Ability"]):
				fixed_parts.append(part)
		if part_a.is_empty():
			continue
		var variants: Array[Dictionary] = [part_a]
		if include_upgrades:
			for part: Dictionary in _parts:
				if part["IsUpgrade"] == 1 and part["BaseItemId"] == part_a["_id"]:
					variants.append(part)
		for variant in variants:
			var weapon := _weapon_from_part(variant, game_weapon)
			weapon.is_rune = true
			for fixed in fixed_parts:
				weapon.attachments.append(_attachment_from_part(fixed, "Rune"))
			(upgraded if variant["IsUpgrade"] == 1 else result).append(weapon)
	result.append_array(upgraded)
	return result


## The rune with this A part id (null if unknown), and its name for pickers.
static func find_rune(part_id: String) -> Weapon:
	for rune in runes():
		if rune.part_id == part_id:
			return rune
	return null


static func rune_label(part_id: String) -> String:
	var rune := find_rune(part_id)
	return part_id if rune == null else rune.weapon_name


## The upgraded ("+") side of `weapon`'s card - a weapon and its + are ONE physical card (the campaign flips it, see
## EmbarkDialog). Returns `weapon` itself when it has no upgrade. A rune keeps its fixed parts.
static func upgraded_weapon(weapon: Weapon) -> Weapon:
	_load()
	var upgrade := _upgrade_of(weapon.part_id)
	if upgrade.is_empty():
		return weapon
	var upgraded := _weapon_from_part(upgrade, _game_weapon_for_part(weapon.part_id))
	upgraded.is_rune = weapon.is_rune
	upgraded.attachments = weapon.attachments.duplicate()
	return upgraded


## The upgraded ("+") side of a B or C part, `attachment` itself when it has none.
static func upgraded_attachment(attachment: WeaponAttachment) -> WeaponAttachment:
	_load()
	var upgrade := _upgrade_of(attachment.part_id)
	if upgrade.is_empty() or not _abilities.has(upgrade["Ability"]):
		return attachment
	return _attachment_from_part(upgrade, attachment.weapon_type)


static func _upgrade_of(part_id: String) -> Dictionary:
	for part: Dictionary in _parts:
		if part["IsUpgrade"] == 1 and part["BaseItemId"] == part_id:
			return part
	return {}


## The game weapon model an A part belongs to: a rune/global weapon lists its parts, a normal weapon is found by class.
static func _game_weapon_for_part(part_id: String) -> Dictionary:
	for game_weapon: Dictionary in _weapons.values():
		if game_weapon["StartingWeaponParts"].has(part_id):
			return game_weapon
	var part: Dictionary = _parts_by_id.get(part_id, {})
	for game_weapon: Dictionary in _weapons.values():
		if game_weapon["IsGlobal"] != 1 and not part.is_empty() and game_weapon["Class"] == part["Class"]:
			return game_weapon
	return {}


## The weapon TYPE name ("Sword") of an A/B/C part id, "" if unknown.
static func weapon_type_of_part(part_id: String) -> String:
	_load()
	var part: Dictionary = _parts_by_id.get(part_id, {})
	if part.is_empty():
		return ""
	for type_name: String in TYPE_TO_GAME_WEAPON:
		var game_id: String = TYPE_TO_GAME_WEAPON[type_name]
		if _weapons.has(game_id) and _weapons[game_id]["Class"] == part["Class"]:
			return type_name
	return ""


## "Warden's Blade (Sword)" for shop pickers and texts; the id itself when unknown.
static func weapon_label(part_id: String) -> String:
	_load()
	var part: Dictionary = _parts_by_id.get(part_id, {})
	if part.is_empty():
		return part_id
	return "%s (%s)" % [_text(part["KeyName"], part["m_Name"]), weapon_type_of_part(part_id)]


## Every base weapon card of the types heroes use, as part ids, in type order - the basic set: the FIRST card of each
## hero weapon type.
static func basic_set() -> Array[String]:
	_load()
	var ids: Array[String] = []
	for type_name: String in hero_types():
		var weapons := weapons_for_type(type_name)
		if not weapons.is_empty():
			ids.append(weapons[0].part_id)
	return ids


## The distinct weapon types the six heroes use (WeaponCatalog.HERO_WEAPON_TYPES).
static func hero_types() -> Array[String]:
	var types: Array[String] = []
	for pair: Array in WeaponCatalog.HERO_WEAPON_TYPES:
		for type_name: String in pair:
			if not types.has(type_name):
				types.append(type_name)
	return types


static func _attachment_from_part(part: Dictionary, type_name: String) -> WeaponAttachment:
	var ability: Dictionary = _abilities[part["Ability"]]
	var attachment := WeaponAttachment.new(_text(part["KeyName"], part["m_Name"]) + ("+" if part["IsUpgrade"] == 1 else ""), MonsterCondition.Kind.DAZED, 0, type_name)
	attachment.part_id = part["_id"]
	attachment.icon_path = part["TextureAssetPath"]
	attachment.part_slot = "B" if part["Slot"] == 1 else "C"
	attachment.ability_name = _text(ability["KeyName"], "")
	attachment.ability_text = _clean(_text(ability["KeyDesc"], ""))
	return attachment


static func _build(game_weapon: Dictionary, include_upgrades: bool) -> Array[Weapon]:
	var built: Array[Weapon] = []
	var parts: Array = []
	for part: Dictionary in _parts:
		if part["Class"] == game_weapon["Class"] and part["Slot"] == 0 and (include_upgrades or part["IsUpgrade"] == 0):
			parts.append(part)
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["IsUpgrade"] != b["IsUpgrade"]:
			return a["IsUpgrade"] < b["IsUpgrade"]
		return str(a["_id"]) < str(b["_id"]))
	for part: Dictionary in parts:
		built.append(_weapon_from_part(part, game_weapon))
	return built



## One Weapon from an A part: its name, damage, damage types, reach / range (from the weapon model) and ability.
static func _weapon_from_part(part: Dictionary, game_weapon: Dictionary) -> Weapon:
	var weapon := Weapon.new()
	weapon.weapon_name = _text(part["KeyName"], part["m_Name"]) + ("+" if part["IsUpgrade"] == 1 else "")
	weapon.part_id = part["_id"]
	weapon.icon_path = part["TextureAssetPath"]
	weapon.base_part_id = part["BaseItemId"] if part["IsUpgrade"] == 1 else part["_id"]
	weapon.damage = int(part["Damage"])
	var kinds: Array[int] = []
	for trait_number in part["Traits"]:
		if TRAIT_TO_KIND.has(int(trait_number)):
			kinds.append(TRAIT_TO_KIND[int(trait_number)])
	weapon.damage_types = kinds
	var range_class := int(game_weapon["RangeApproximation"])
	weapon.reach = range_class == 1
	weapon.weapon_range = RANGE_BY_PART.get(part["_id"], RANGED_RANGE) if range_class == 2 else 0
	var ability: Dictionary = _abilities.get(part["Ability"], {})
	if not ability.is_empty():
		weapon.ability_name = _text(ability["KeyName"], "")
		weapon.ability_text = _clean(_text(ability["KeyDesc"], ""))
	return weapon


static func _text(key: String, fallback: String) -> String:
	return _without_glyphs(str(_texts.get(key, fallback))).strip_edges()


## The game's private-use icon glyphs (an upgrade marker, a term icon) show as boxes in a normal font.
static func _without_glyphs(text: String) -> String:
	return RegEx.create_from_string("[\\x{E000}-\\x{F8FF}]").sub(text, "", true)


## The game's texts carry rich-text markup: `<style=Term><link=TERM_FATIGUE></link></style>` is an icon (shown as the
## word), `<b>..</b>` is bold. Plain text is what our labels show.
static func _clean(text: String) -> String:
	var icon := RegEx.create_from_string("<link=TERM_([A-Z_]+)>[^<]*</link>")
	var result := icon.sub(text, "[$1]", true)
	text = _without_glyphs(text)
	var tags := RegEx.create_from_string("<[^>]*>")
	result = tags.sub(result, "", true)
	for match in RegEx.create_from_string("\\[([A-Z_]+)\\]").search_all(result):
		result = result.replace(match.get_string(), "[%s]" % match.get_string(1).to_lower().replace("_", " "))
	return result.strip_edges()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data = _read_json(DIRECTORY + "weapons.json")
	if not data is Dictionary:
		return
	for weapon: Dictionary in data.get("weapons", []):
		_weapons[weapon["_id"]] = weapon
	_parts = data.get("parts", [])
	for part: Dictionary in _parts:
		_parts_by_id[part["_id"]] = part
	for ability: Dictionary in data.get("abilities", []):
		_abilities[ability["_id"]] = ability
	var texts = _read_json(DIRECTORY + "localization_en.json")
	if texts is Dictionary:
		_texts = texts


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
