class_name CampaignIO
extends RefCounted

## Files of campaigns: one folder per campaign under user://campaigns/ holding
## campaign.tres, the mission files the chapters use and the acts' map images. Never
## instantiated.

const ROOT := "user://campaigns"
const FILE_NAME := "campaign.tres"


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


## The map image of an act as a texture, or null when there is none / it can't be read.
static func map_texture(folder: String, file_name: String) -> Texture2D:
	if file_name == "":
		return null
	var image := Image.load_from_file("%s/%s" % [folder_path(folder), file_name])
	return ImageTexture.create_from_image(image) if image != null else null
