extends Node

## Checks every .descentpkg below a folder with the app's own package check (SharePackage.read - the same one that runs
## before a player installs anything). Run by the community repository on every submission:
##
##     godot --headless --path <this project> --import
##     godot --headless --path <this project> res://tools/community/validate_packages.tscn -- <folder>
##
## Prints one line per package and exits with 1 when any is refused (or none is found). A scene rather than a `-s` script,
## because the app's data classes need the project's autoloads, which a `-s` script doesn't get.


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		print("usage: res://tools/community/validate_packages.tscn -- <folder with packages>")
		get_tree().quit(2)
		return
	var packages := _find(arguments[0])
	var refused := 0
	for path in packages:
		var result: Dictionary = SharePackage.read(path)
		var manifest: Dictionary = result.get("manifest", {})
		var expected := "%s-%s.%s" % [str(manifest.get("id", "")), str(manifest.get("version", "")), SharePackage.EXTENSION]
		var errors: Array = result.get("errors", [])
		if result.get("ok", false) and path.get_file() != expected:
			errors = ["the file must be called %s (its id and version)" % expected]
		if errors.is_empty():
			print("ok       %s" % path)
		else:
			refused += 1
			print("REFUSED  %s" % path)
			for error: Variant in errors:
				print("           - %s" % str(error))
	print("%d package(s), %d refused" % [packages.size(), refused])
	get_tree().quit(1 if refused > 0 or packages.is_empty() else 0)


func _find(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file_name in DirAccess.get_files_at(folder):
		if file_name.get_extension().to_lower() == SharePackage.EXTENSION:
			found.append(folder.path_join(file_name))
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_find(folder.path_join(sub)))
	found.sort()
	return found
