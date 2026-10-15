class_name ChangelogDialog
extends AcceptDialog

## "What's new": the list of changes per version, read from data/changelog.md - sections start with "## <version> - <date>",
## the lines under it are "- " bullets. Newest first. The file is part of the export (the presets include data/*).

const FILE := "res://data/changelog.md"


## [{title, items: [String]}] in the order of the file.
static func entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not FileAccess.file_exists(FILE):
		return found
	for line in FileAccess.get_file_as_string(FILE).split("\n"):
		var text := line.strip_edges()
		if text.begins_with("## "):
			found.append({"title": text.substr(3).strip_edges(), "items": []})
		elif text.begins_with("- ") and not found.is_empty():
			found[-1]["items"].append(text.substr(2).strip_edges())
	return found


func _ready() -> void:
	title = "What's new"
	ok_button_text = "Close"
	min_size = Vector2i(640, 460)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 400)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var all := entries()
	if all.is_empty():
		var none := Label.new()
		none.text = "No change list is available."
		box.add_child(none)
	for entry in all:
		var heading := Label.new()
		heading.text = str(entry["title"])
		heading.add_theme_font_size_override("font_size", 20)
		box.add_child(heading)
		for item: String in entry["items"]:
			var line := Label.new()
			line.text = "•  " + item
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size = Vector2(570, 0)
			box.add_child(line)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		box.add_child(gap)


func open() -> void:
	popup_centered()
