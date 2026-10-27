extends Node

## Puts the app-wide look (AppTheme) into the project theme (res://theme/app_theme.tres, an empty stub named in the project settings), so every scene,
## dialog and editor window inherits it - including controls under a CanvasLayer, which a theme set on the root window does not reach.


func _ready() -> void:
	var project_theme := ThemeDB.get_project_theme()
	if project_theme != null:
		AppTheme.populate(project_theme)
	else:
		get_tree().root.theme = AppTheme.build()
