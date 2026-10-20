class_name TextBoxCorner
extends RefCounted

## The small row of helper buttons in the top-right corner of a story text box (the AI menu, the dictation button).
## Whoever needs the row asks for it here, so every helper of one box shares ONE row instead of piling up on each other.

const META := "corner_row"


## The corner row of `edit`, made on the first call. Anchors are set by hand (the box has no size yet when helpers are attached) and the
## row is added deferred: the box may itself still be setting up its children (helpers are attached before it enters the tree), and a parent
## that is busy refuses add_child(). Helpers hide their own button, not the row.
static func row(edit: TextEdit) -> HBoxContainer:
	if edit.has_meta(META):
		var existing: Variant = edit.get_meta(META)
		if is_instance_valid(existing):
			return existing as HBoxContainer
	var corner := HBoxContainer.new()
	corner.anchor_left = 1.0
	corner.anchor_right = 1.0
	corner.anchor_top = 0.0
	corner.anchor_bottom = 0.0
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_left = -4.0
	corner.offset_right = -4.0
	corner.offset_top = 2.0
	edit.add_child.call_deferred(corner)
	edit.set_meta(META, corner)
	return corner
