class_name MonsterArchetypeLibrary
extends RefCounted

## The shared on-disk library of monster templates (MonsterArchetype), one `.tres`
## per template in user data - NOT inside a mission, so templates are reusable
## across missions. Never instantiated; static helpers only. A template's key is
## its file name (its template_name, sanitised).

const DIRECTORY := "user://monster_templates"


## Every template's key, sorted.
static func names() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.get_extension() == "tres":
			result.append(file.get_basename())
	result.sort()
	return result


## Keys of the templates of one kind (MonsterArchetype.Kind), sorted - loads each
## file, fine at library size.
static func names_of_kind(kind: int) -> Array[String]:
	var result: Array[String] = []
	for key in names():
		var archetype := load_template(key)
		if archetype != null and archetype.kind == kind:
			result.append(key)
	return result


## A template's key from its display name: characters that aren't valid in a
## file name become "_".
static func key_for(template_name: String) -> String:
	var key := ""
	for c in template_name.strip_edges():
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == " " or c == "-" or c == "_"
		key += c if ok else "_"
	return key


static func path_for(key: String) -> String:
	return "%s/%s.tres" % [DIRECTORY, key]


## A fresh, independent copy of the template stored under `key`, or null.
static func load_template(key: String) -> MonsterArchetype:
	var path := path_for(key)
	if not FileAccess.file_exists(path):
		return null
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MonsterArchetype
	return loaded.deep_copy() if loaded != null else null


## Saves `archetype` under key_for(archetype.template_name) (a blank name is
## refused). Returns that key, or "" on failure.
static func save_template(archetype: MonsterArchetype) -> String:
	var key := key_for(archetype.template_name)
	if key == "":
		return ""
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if ResourceSaver.save(archetype.deep_copy(), path_for(key)) != OK:
		return ""
	return key


## Brings the templates ATTACHED to `templates` (MonsterTemplate.archetypes - the
## embedded copies) up to date with the library: every copy whose library entry
## (matched by name) has different content is replaced by a fresh copy of it. A
## copy whose library entry no longer exists is left alone (the mission stays
## self-contained). `apply = false` only counts. Returns how many copies are
## (or would be) replaced.
static func sync_templates(templates: Array[MonsterTemplate], apply: bool = true) -> int:
	var cache := {}  # key -> MonsterArchetype (or null)
	var changed := 0
	for template in templates:
		if template.base_archetype != null:
			var fresh := _fresh_copy_if_stale(template.base_archetype, cache)
			if fresh != null:
				changed += 1
				if apply:
					template.base_archetype = fresh
		for i in template.archetypes.size():
			var fresh_additive := _fresh_copy_if_stale(template.archetypes[i], cache)
			if fresh_additive != null:
				changed += 1
				if apply:
					template.archetypes[i] = fresh_additive
	return changed


## A fresh library copy of `current` if the library has a template of that name
## whose content differs, else null (up to date, or gone from the library).
static func _fresh_copy_if_stale(current: MonsterArchetype, cache: Dictionary) -> MonsterArchetype:
	var key := key_for(current.template_name)
	if not cache.has(key):
		cache[key] = load_template(key)
	var fresh: MonsterArchetype = cache[key]
	if fresh == null or fresh.signature() == current.signature():
		return null
	return fresh.deep_copy()


static func sync_mission(mission: MissionData, apply: bool = true) -> int:
	return sync_templates(mission.collect_monster_templates(), apply)


## Batch update: loads every mission file directly inside `directory` (not
## sub-folders, so the autosave backups are left alone), syncs its monster
## templates from the library and saves it back if anything changed. Returns
## {"missions": files changed, "monsters": copies replaced}.
static func update_missions_in(directory: String) -> Dictionary:
	var missions_changed := 0
	var monsters_changed := 0
	var dir := DirAccess.open(directory)
	if dir == null:
		return {"missions": 0, "monsters": 0}
	for file in dir.get_files():
		if file.get_extension() != "tres":
			continue
		var path := "%s/%s" % [directory, file]
		var mission := MissionIO.load_mission(path)
		if mission == null:
			continue
		var count := sync_mission(mission)
		if count > 0 and MissionIO.save_mission(mission, path):
			missions_changed += 1
			monsters_changed += count
	return {"missions": missions_changed, "monsters": monsters_changed}


static func delete_template(key: String) -> void:
	var path := path_for(key)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
