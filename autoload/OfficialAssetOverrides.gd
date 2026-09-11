extends Node

## Swaps shipped placeholder textures for a user's OWN legally-obtained
## official game assets, if present locally - same pattern OpenMW uses for
## Morrowind: this project ships zero copyrighted art, only placeholders,
## and only the individual user (via tools/asset_import/, pointed at their
## own game install) ever puts the real files in place. Never redistributed.
##
## Override files are expected at user://official_assets/<OfficialName>.png
## (OfficialName from OfficialAssetMap). If a file isn't there, the
## shipped placeholder is left completely untouched.
const OVERRIDE_DIR := "user://official_assets/"


## Call once at startup with the shared MeshLibrary (all four GridMaps -
## floor/prop/underlay - use the same one, so this only needs to run
## once, not per-grid). Scans EVERY item's current texture (not just ones
## with some special name) since OfficialAssetMap matches by placeholder
## texture path - several floor tile faces share the exact same
## "flagstone"/"grass"/etc. texture, so this naturally swaps all of them
## without needing a map entry per tile face. Safe to call with no
## override files present; it's then just a no-op scan.
func apply_overrides(mesh_library: MeshLibrary) -> void:
	if mesh_library == null:
		return
	for item_id in mesh_library.get_item_list():
		_apply_to_item(mesh_library, item_id)


func _apply_to_item(mesh_library: MeshLibrary, item_id: int) -> void:
	var mesh := mesh_library.get_item_mesh(item_id)
	if mesh == null or mesh.get_surface_count() == 0:
		return

	# Only surface 0 - see the class-level note on multi-surface items
	# (the "medium"/"mini" pillars have several; nothing currently mapped
	# does).
	var material := mesh.surface_get_material(0)
	if not (material is StandardMaterial3D):
		return

	var current_texture: Texture2D = material.albedo_texture
	if current_texture == null or current_texture.resource_path == "":
		return

	var official_name := OfficialAssetMap.get_official_name(current_texture.resource_path)
	if official_name == "":
		return

	var override_texture := _load_override_texture(official_name)
	if override_texture == null:
		return

	# Duplicate before touching - never mutate a material in place, in
	# case two items ever end up sharing one material resource (they
	# already share the same TEXTURE by design for floor tiles, but each
	# item should still end up with its own independent material after
	# this, not a shared one two different swaps could stomp on).
	var new_material: StandardMaterial3D = material.duplicate()
	new_material.albedo_texture = override_texture
	mesh.surface_set_material(0, new_material)
	mesh_library.set_item_mesh(item_id, mesh)


func _load_override_texture(official_name: String) -> ImageTexture:
	var path := OVERRIDE_DIR + official_name + ".png"
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		push_warning("OfficialAssetOverrides: failed to load %s" % path)
		return null
	return ImageTexture.create_from_image(image)
