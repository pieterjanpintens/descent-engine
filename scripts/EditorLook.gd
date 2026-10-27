class_name EditorLook
extends Node

## Put as a child of an editor's top control: gives that control (and everything under it, windows included) Godot's normal look instead of the
## app theme, which the play parts and the menus use.


func _ready() -> void:
	var parent := get_parent() as Control
	if parent != null:
		AppTheme.apply_classic(parent)
