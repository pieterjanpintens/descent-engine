class_name SkillTreePreview
extends Control

## A drawing of a SkillTree: the starting points in the top row, every other skill below all of its parents, a line from each parent to its
## skill. Each box shows the skill number and cost (and a name when `names` has one: number -> text). Starting points are green, skills with
## conditions are tinted and marked "if", skills that can never be bought are red. Only drawn, never edited.

const BOX := Vector2(124, 46)
const ROW_GAP := 26.0
const MARGIN := 10.0

var tree: SkillTree:
	set(value):
		tree = value
		queue_redraw()
		update_minimum_size()
var names: Dictionary = {}:
	set(value):
		names = value
		queue_redraw()


func _get_minimum_size() -> Vector2:
	if tree == null:
		return Vector2(300, 120)
	var rows := tree.layers()
	var widest := 1
	for row in rows:
		widest = maxi(widest, row.size())
	return Vector2(MARGIN * 2 + widest * (BOX.x + 12) - 12, MARGIN * 2 + rows.size() * BOX.y + maxi(rows.size() - 1, 0) * ROW_GAP)


func _draw() -> void:
	if tree == null:
		return
	var rows := tree.layers()
	var positions: Dictionary = {}  # number -> top-left corner
	for r in rows.size():
		var row: Array = rows[r]
		var row_width: float = row.size() * (BOX.x + 12) - 12
		var x := (size.x - row_width) / 2.0
		for number: int in row:
			positions[number] = Vector2(x, MARGIN + r * (BOX.y + ROW_GAP))
			x += BOX.x + 12
	var line_color := Color(0.6, 0.65, 0.75)
	for entry in tree.nodes:
		if not positions.has(entry.number):
			continue
		for parent in entry.parents:
			if positions.has(parent):
				draw_line(positions[parent] + Vector2(BOX.x / 2.0, BOX.y), positions[entry.number] + Vector2(BOX.x / 2.0, 0), line_color, 1.5, true)
	var reached := tree.reachable()
	var font := ThemeDB.fallback_font
	for entry in tree.nodes:
		if not positions.has(entry.number):
			continue
		var top_left: Vector2 = positions[entry.number]
		var fill := Color(0.18, 0.2, 0.28)
		if not reached.has(entry.number):
			fill = Color(0.45, 0.15, 0.15)
		elif entry.parents.is_empty():
			fill = Color(0.16, 0.34, 0.22)
		elif not entry.conditions.is_empty():
			fill = Color(0.3, 0.24, 0.4)
		draw_rect(Rect2(top_left, BOX), fill)
		draw_rect(Rect2(top_left, BOX), Color(0.75, 0.8, 0.9), false, 1.0)
		var act_text := " · if" if not entry.conditions.is_empty() else ""
		draw_string(font, top_left + Vector2(6, 17), "%d · cost %d%s" % [entry.number, entry.cost, act_text], HORIZONTAL_ALIGNMENT_LEFT, BOX.x - 8, 12)
		var shown := str(names.get(entry.number, ""))
		if shown != "":
			draw_string(font, top_left + Vector2(6, 35), shown, HORIZONTAL_ALIGNMENT_LEFT, BOX.x - 8, 10, Color(0.8, 0.85, 0.9))
