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
## 3-8 were read from the part names that carry them (Ashen, Sunburst = fire, Wing Blade, Howling = wind, Ice Storm =
## water, Quaking = earth, Crystal, Sunburst = light, Shrieking, Fear = dead) and are an educated guess. 9, 10 and 11
## (Hungry, Dragonsbane, Life Drinking, Warping...) have no kind of ours yet and are skipped.
const TRAIT_TO_KIND := {
	0: Vulnerability.Kind.CRUSH,
	1: Vulnerability.Kind.SLASH,
	2: Vulnerability.Kind.PIERCE,
	3: Vulnerability.Kind.IGNOS,
	4: Vulnerability.Kind.ANEMOS,
	5: Vulnerability.Kind.AQUOS,
	6: Vulnerability.Kind.TERROS,
	7: Vulnerability.Kind.LUMOS,
	8: Vulnerability.Kind.MORTOS,
}

## The game data only says 0 melee / 1 reach / 2 ranged (`RangeApproximation`, per weapon type) - the real distance is
## not in the files we can read (no range field on parts or abilities, no range in any text; the part pictures don't
## show it either, so it is probably game code). Ranged weapons therefore get this range (squares), known from play...
const RANGED_RANGE := 4
## ...except these parts, whose range is known to differ (part id -> range): the Oakroot Wand (and its upgrade) has 5.
const RANGE_BY_PART := {
	"WEAPON_PART_A_WAND_2": 5,
	"WEAPON_PART_A_WAND_2_UPGRADED": 5,
}

static var _loaded := false
static var _weapons: Dictionary = {}    # game weapon id -> entry
static var _parts: Array = []
static var _abilities: Dictionary = {}  # ability id -> entry
static var _texts: Dictionary = {}
static var _cache: Dictionary = {}      # type name -> Array[Weapon]
static var _attachment_cache: Dictionary = {}  # type name -> Array[WeaponAttachment]


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
	_abilities.clear()
	_texts.clear()


## Fresh Weapon instances for every A part of the game weapon behind `type_name`, base versions first then the
## upgraded ones; empty when there is no export or the type is unknown.
static func weapons_for_type(type_name: String) -> Array[Weapon]:
	_load()
	var result: Array[Weapon] = []
	var game_id: String = TYPE_TO_GAME_WEAPON.get(type_name, "")
	if game_id == "" or not _weapons.has(game_id):
		return result
	if not _cache.has(type_name):
		_cache[type_name] = _build(_weapons[game_id])
	for template: Weapon in _cache[type_name]:
		result.append(template.duplicate(true))
	return result


## Fresh WeaponAttachment instances for every B and C part of the weapon behind `type_name` that has an ability (the
## starter guard / hilt do nothing and count as "none"), base versions first then the upgraded ones.
static func attachments_for_type(type_name: String) -> Array[WeaponAttachment]:
	_load()
	var result: Array[WeaponAttachment] = []
	var game_id: String = TYPE_TO_GAME_WEAPON.get(type_name, "")
	if game_id == "" or not _weapons.has(game_id):
		return result
	if _attachment_cache.has(type_name):
		for cached: WeaponAttachment in _attachment_cache[type_name]:
			result.append(cached.duplicate(true))
		return result
	var parts: Array = []
	for part: Dictionary in _parts:
		if part["Class"] == _weapons[game_id]["Class"] and (part["Slot"] == 1 or part["Slot"] == 2) and _abilities.has(part["Ability"]):
			parts.append(part)
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["Slot"] != b["Slot"]:
			return a["Slot"] < b["Slot"]
		if a["IsUpgrade"] != b["IsUpgrade"]:
			return a["IsUpgrade"] < b["IsUpgrade"]
		return str(a["_id"]) < str(b["_id"]))
	for part: Dictionary in parts:
		var ability: Dictionary = _abilities[part["Ability"]]
		var attachment := WeaponAttachment.new(_text(part["KeyName"], part["m_Name"]) + ("+" if part["IsUpgrade"] == 1 else ""), MonsterCondition.Kind.DAZED, 0, type_name)
		attachment.part_id = part["_id"]
		attachment.part_slot = "B" if part["Slot"] == 1 else "C"
		attachment.ability_name = _text(ability["KeyName"], "")
		attachment.ability_text = _clean(_text(ability["KeyDesc"], ""))
		result.append(attachment)
	_attachment_cache[type_name] = result.duplicate()
	return result


static func _build(game_weapon: Dictionary) -> Array[Weapon]:
	var built: Array[Weapon] = []
	var parts: Array = []
	for part: Dictionary in _parts:
		if part["Class"] == game_weapon["Class"] and part["Slot"] == 0:
			parts.append(part)
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["IsUpgrade"] != b["IsUpgrade"]:
			return a["IsUpgrade"] < b["IsUpgrade"]
		return str(a["_id"]) < str(b["_id"]))
	for part: Dictionary in parts:
		var weapon := Weapon.new()
		weapon.weapon_name = _text(part["KeyName"], part["m_Name"]) + ("+" if part["IsUpgrade"] == 1 else "")
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
		built.append(weapon)
	return built


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
	for ability: Dictionary in data.get("abilities", []):
		_abilities[ability["_id"]] = ability
	var texts = _read_json(DIRECTORY + "localization_en.json")
	if texts is Dictionary:
		_texts = texts


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
