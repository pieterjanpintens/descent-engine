class_name CampaignIO
extends RefCounted

## Files of campaigns: one folder per campaign under user://campaigns/ holding
## campaign.tres, the mission files the chapters use and the acts' map images. Never
## instantiated.

const ROOT := "user://campaigns"
const FILE_NAME := "campaign.tres"
const SAVES_ROOT := "user://campaign_saves"
## A book cover is trimmed to this 2:3 portrait ratio (and scaled to this size) when imported.
const COVER_SIZE := Vector2i(400, 600)


## A folder-safe key for a campaign name ("My Campaign!" -> "my_campaign").
static func key_for(campaign_name: String) -> String:
	var key := ""
	for character in campaign_name.strip_edges().to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			key += character
		elif key != "" and not key.ends_with("_"):
			key += "_"
	return key.trim_suffix("_")


static func folder_path(folder: String) -> String:
	return "%s/%s" % [ROOT, folder]


## Every campaign folder that contains a campaign file, sorted.
static func folder_names() -> Array[String]:
	var names: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ROOT)
	for folder in DirAccess.get_directories_at(ROOT):
		if FileAccess.file_exists("%s/%s" % [folder_path(folder), FILE_NAME]):
			names.append(folder)
	names.sort()
	return names


static func save_campaign(campaign: Campaign, folder: String) -> bool:
	DirAccess.make_dir_recursive_absolute(folder_path(folder))
	var err := ResourceSaver.save(campaign, "%s/%s" % [folder_path(folder), FILE_NAME])
	if err != OK:
		push_error("Failed to save campaign %s: %s" % [folder, error_string(err)])
	return err == OK


static func load_campaign(folder: String) -> Campaign:
	var path := "%s/%s" % [folder_path(folder), FILE_NAME]
	if not FileAccess.file_exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path, "Campaign", ResourceLoader.CACHE_MODE_IGNORE)
	return loaded as Campaign


## The file name (without extension) of a save game called `save_name`.
static func save_key(save_name: String) -> String:
	var key := key_for(save_name)
	return key if key != "" else "save"


static func saves_path(folder: String) -> String:
	return "%s/%s" % [SAVES_ROOT, folder]


## A campaign save game (progress): user://campaign_saves/<campaign folder>/<save key>.tres - a
## campaign can have several, one per playthrough.
static func save_state(state: CampaignState) -> bool:
	DirAccess.make_dir_recursive_absolute(saves_path(state.campaign_folder))
	var err := ResourceSaver.save(state, "%s/%s.tres" % [saves_path(state.campaign_folder), save_key(state.save_name)])
	if err != OK:
		push_error("Failed to save campaign progress %s: %s" % [state.campaign_folder, error_string(err)])
	return err == OK


## The save game with file name `key` of campaign `folder`, or null if there is none.
static func load_state(folder: String, key: String) -> CampaignState:
	var path := "%s/%s.tres" % [saves_path(folder), key]
	if not FileAccess.file_exists(path):
		return null
	return ResourceLoader.load(path, "CampaignState", ResourceLoader.CACHE_MODE_IGNORE) as CampaignState


## The file names (keys) of every save game of campaign `folder`, sorted.
static func save_keys(folder: String) -> Array[String]:
	var keys: Array[String] = []
	if not DirAccess.dir_exists_absolute(saves_path(folder)):
		return keys
	for file in DirAccess.get_files_at(saves_path(folder)):
		if file.ends_with(".tres"):
			keys.append(file.trim_suffix(".tres"))
	keys.sort()
	return keys


## The most recently written save game over all campaigns, as {folder, key} ({} if there is none).
static func latest_save() -> Dictionary:
	var best := {}
	var best_time := 0
	for folder in folder_names():
		for key in save_keys(folder):
			var modified := FileAccess.get_modified_time("%s/%s.tres" % [saves_path(folder), key])
			if modified >= best_time:
				best_time = modified
				best = {"folder": folder, "key": key}
	return best


static func delete_state(folder: String, key: String) -> void:
	DirAccess.remove_absolute("%s/%s.tres" % [saves_path(folder), key])


## File names of the missions inside the campaign folder (every .tres except the campaign).
static func mission_files(folder: String) -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at(folder_path(folder)):
		if file.ends_with(".tres") and file != FILE_NAME:
			files.append(file)
	files.sort()
	return files


## Copies a mission file into the campaign folder (so the campaign stays self-contained);
## returns the file name it got there, "" on failure. An existing file of that name is replaced.
static func import_mission(folder: String, source_path: String) -> String:
	DirAccess.make_dir_recursive_absolute(folder_path(folder))
	var file_name := source_path.get_file()
	var err := DirAccess.copy_absolute(source_path, "%s/%s" % [folder_path(folder), file_name])
	if err != OK:
		push_error("Failed to copy mission %s: %s" % [source_path, error_string(err)])
		return ""
	return file_name


## Copies an image into the campaign folder as the map of an act; returns its file name.
static func import_map_image(folder: String, source_path: String, act_number: int) -> String:
	DirAccess.make_dir_recursive_absolute(folder_path(folder))
	var file_name := "map_%d.%s" % [act_number, source_path.get_extension().to_lower()]
	var err := DirAccess.copy_absolute(source_path, "%s/%s" % [folder_path(folder), file_name])
	if err != OK:
		push_error("Failed to copy map image %s: %s" % [source_path, error_string(err)])
		return ""
	return file_name


## Imports `source_path` as the book cover of campaign `folder`: trimmed (centred) to the 2:3 cover ratio
## and scaled to COVER_SIZE, saved as cover.png. Returns the file name, "" on failure.
static func import_cover_image(folder: String, source_path: String) -> String:
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		return ""
	var target_ratio := float(COVER_SIZE.x) / float(COVER_SIZE.y)
	var crop := Vector2i(image.get_width(), image.get_height())
	if float(crop.x) / float(crop.y) > target_ratio:
		crop.x = int(round(crop.y * target_ratio))
	else:
		crop.y = int(round(crop.x / target_ratio))
	var origin := Vector2i((image.get_width() - crop.x) / 2, (image.get_height() - crop.y) / 2)
	var cover := image.get_region(Rect2i(origin, crop))
	cover.resize(COVER_SIZE.x, COVER_SIZE.y, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(folder_path(folder))
	if cover.save_png("%s/cover.png" % folder_path(folder)) != OK:
		return ""
	return "cover.png"


## An image file inside the campaign folder (a map, a cover) as a texture, or null when there is none /
## it can't be read.
static func image_texture(folder: String, file_name: String) -> Texture2D:
	if file_name == "":
		return null
	var image := Image.load_from_file("%s/%s" % [folder_path(folder), file_name])
	return ImageTexture.create_from_image(image) if image != null else null
