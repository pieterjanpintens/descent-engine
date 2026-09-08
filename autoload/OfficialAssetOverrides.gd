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
## floor/wall/prop/underlay - use the same one, so this only needs to run
## once, not per-grid). Safe to call with no override files present; it's
## then just a no-op scan.
func apply_overrides(mesh_library: MeshLibrary) -> void:
	if mesh_library == null:
		return
	for item_id in mesh_library.get_item_list():
		var mesh_name := mesh_library.get_item_name(item_id)
		var official_name := OfficialAssetMap.get_official_name(mesh_name)
		if official_name == "":
			continue
		var texture := _load_override_texture(official_name)
		if texture == null:
			continue
		_apply_texture(mesh_library, item_id, texture)


func _load_override_texture(official_name: String) -> ImageTexture:
	var path := OVERRIDE_DIR + official_name + ".png"
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		push_warning("OfficialAssetOverrides: failed to load %s" % path)
		return null
	return ImageTexture.create_from_image(image)


## Duplicates the material before touching it - each MeshLibrary item here
## already owns its own distinct mesh resource (verified against
## descent-meshes.tres), but materials could still be accidentally shared
## between them (e.g. two objects left on Blender's default material), and
## mutating a shared material in place would silently reskin the wrong
## items too.
##
## Only handles a single surface (surface 0). Confirmed all items current
## OfficialAssetMap entries (the underlay hazards) are single-surface -
## some OTHER items (the "medium"/"mini" pillars) do have multiple
## surfaces/materials, so if this ever needs to cover a multi-surface
## item, this function needs to loop surfaces and either take a surface
## index or a per-surface texture list, not just one texture.
func _apply_texture(mesh_library: MeshLibrary, item_id: int, texture: ImageTexture) -> void:
	var mesh := mesh_library.get_item_mesh(item_id)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var material := mesh.surface_get_material(0)
	if not (material is StandardMaterial3D):
		push_warning("OfficialAssetOverrides: item '%s' has no StandardMaterial3D on surface 0, skipping" % mesh_library.get_item_name(item_id))
		return
	var new_material: StandardMaterial3D = material.duplicate()
	new_material.albedo_texture = texture
	mesh.surface_set_material(0, new_material)
	mesh_library.set_item_mesh(item_id, mesh)
