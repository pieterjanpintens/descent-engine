class_name MacroTemplateLibrary
extends RefCounted

## The author's own macro templates: one .tres per macro in user://macros/ (the user folder, like the monster templates). MacroCatalog loads
## them when it first needs the list; save_template() / delete_template() refresh it.

const FOLDER := "user://macros"


static func file_for(macro_id: String) -> String:
	var safe := ""
	for index in macro_id.length():
		var ch := macro_id[index].to_lower()
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-" or ch == "."
		safe += ch if ok else "_"
	return "%s/%s.tres" % [FOLDER, safe]


## Every template that loads and passes its own checks, by id; the others are skipped with a warning.
static func load_all() -> Array[MacroTemplate]:
	var found: Array[MacroTemplate] = []
	for file in DirAccess.get_files_at(FOLDER):
		if not file.ends_with(".tres"):
			continue
		var loaded := load_file("%s/%s" % [FOLDER, file])
		if loaded == null:
			push_warning("Macro template %s could not be read" % file)
			continue
		var broken := loaded.problems()
		if not broken.is_empty():
			push_warning("Macro template %s is not usable: %s" % [file, broken[0]])
			continue
		found.append(loaded)
	return found


static func load_file(path: String) -> MacroTemplate:
	if not FileAccess.file_exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MacroTemplate


## Saves `template` (refused with an error text when it has problems); "" when saved.
static func save_template(template: MacroTemplate) -> String:
	var broken := template.problems()
	if not broken.is_empty():
		return broken[0]
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var result := ResourceSaver.save(template.duplicate(true), file_for(template.macro_id))
	if result != OK:
		return "Could not save the macro (error %d)." % result
	MacroCatalog.reload_user_macros()
	return ""


static func delete_template(macro_id: String) -> void:
	var path := file_for(macro_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	MacroCatalog.reload_user_macros()
