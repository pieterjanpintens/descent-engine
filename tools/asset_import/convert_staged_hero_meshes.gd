extends SceneTree

## Hero-side twin of convert_staged_meshes.gd (this same folder) - see that
## script's own doc for the full mechanism (Godot has no runtime .obj
## importer, so this bridges through the editor's own res:// import
## pipeline). Kept as its own separate copy rather than a shared/
## parameterized script - same "each tool owns its own near-identical
## logic" convention this project already uses for its dialog row-builders.
##
## Run via `godot --headless --path <project> -s
## res://tools/asset_import/convert_staged_hero_meshes.gd` (import_hero_meshes.py
## invokes this itself).
##
## Scans res://models/original/hero_staging/<hero>/ for staged *.obj files
## (import_hero_meshes.py controls which heroes get staged) and converts
## each to its own "<basename>.tres" under
## user://hero_assets/<hero>/.

const STAGING_DIR := "res://models/original/hero_staging"


func _init() -> void:
	var dir := DirAccess.open(STAGING_DIR)
	if dir == null:
		print("No staging folder found at ", STAGING_DIR, " - nothing to convert.")
		quit()
		return

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			_convert_one(folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()
	quit()


func _convert_one(folder_name: String) -> void:
	var folder_path := "%s/%s" % [STAGING_DIR, folder_name]
	var dir := DirAccess.open(folder_path)
	if dir == null:
		print("Couldn't open ", folder_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "obj":
			_convert_file(folder_name, file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _convert_file(folder_name: String, file_name: String) -> void:
	var res_path := "%s/%s/%s" % [STAGING_DIR, folder_name, file_name]
	var mesh: Mesh = load(res_path)
	if mesh == null:
		print("FAILED to load ", res_path)
		return

	var out_dir := "user://hero_assets/%s" % folder_name
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out_path := "%s/%s.tres" % [out_dir, file_name.get_basename()]
	var err := ResourceSaver.save(mesh, out_path)
	if err == OK:
		print("Saved ", out_path)
	else:
		print("FAILED to save ", out_path, " err=", err)
