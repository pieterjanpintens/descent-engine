extends SceneTree

## Companion to import_monster_meshes.py (this same folder) - run via
## `godot --headless --path <project> -s res://tools/asset_import/convert_staged_meshes.gd`
## (the Python script invokes this itself; there's normally no need to run
## it by hand).
##
## Godot has no built-in RUNTIME .obj importer (confirmed via research -
## ResourceImporterOBJ only ever runs through the editor's res:// import
## pipeline), but imports .obj correctly THROUGH that pipeline - see
## claude.md's "Mesh conversion: Godot's own native importer, not a
## hand-rolled parser" section for the full story of why a hand-rolled
## runtime parser was abandoned in favor of leaning on this importer
## directly. This script bridges the gap: import_monster_meshes.py stages
## each monster's raw .obj under
## res://models/original/monster_staging/<folder>/mesh.obj (already
## processed through Godot's own --import pass by the time this runs -
## see that script's own docstring for the full pipeline), loads each one
## here (now resolving through the import pipeline rather than being read
## as raw text), and re-saves it as a portable .tres under
## user://monster_assets/<folder>/mesh.tres - MonsterDisplay.gd just
## ResourceLoader.load()s that directly at runtime, no custom OBJ parsing
## left anywhere in the shipped app.
##
## Scans the staging folder rather than taking a hardcoded monster list -
## import_monster_meshes.py controls which monsters actually get staged
## (read from MonsterDisplay.REAL_MONSTERS), so this just converts
## whatever it finds.

const STAGING_DIR := "res://models/original/monster_staging"


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
	var res_path := "%s/%s/mesh.obj" % [STAGING_DIR, folder_name]
	var mesh: Mesh = load(res_path)
	if mesh == null:
		print("FAILED to load ", res_path)
		return

	var out_dir := "user://monster_assets/%s" % folder_name
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out_path := "%s/mesh.tres" % out_dir
	var err := ResourceSaver.save(mesh, out_path)
	if err == OK:
		print("Saved ", out_path)
	else:
		print("FAILED to save ", out_path, " err=", err)
