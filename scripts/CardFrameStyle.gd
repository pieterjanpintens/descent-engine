class_name CardFrameStyle
extends StyleBox

## The story card frame (StoryCard) - and its orange buttons - as a StyleBox: draws the full-resolution, mipmapped frame art as a 9-slice whose corners are drawn at
## `frame_scale` of their size - shrinking happens on the GPU (mipmapped), so the ring corners stay smooth whatever the window's stretch.
## (A NinePatchRect / StyleBoxTexture draws its corners at their pixel size, so a smaller corner needed a smaller - pre-shrunk - picture,
## which the window's canvas stretch then blew up again: jagged.)

var texture: Texture2D
var source_margin_side := 100.0  ## the corner pieces in the art's own pixels
var source_margin_top := 46.0
var frame_scale := 0.62
var modulate_color := Color.WHITE  ## tints the art (the orange buttons use the white button art)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	RenderingServer.canvas_item_set_default_texture_filter(to_canvas_item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	var art := texture.get_size()
	var side := source_margin_side * frame_scale
	var top := source_margin_top * frame_scale
	# don't let the corners overlap on a very small card
	side = minf(side, rect.size.x / 2.0)
	top = minf(top, rect.size.y / 2.0)
	var src_x := [0.0, source_margin_side, art.x - source_margin_side, art.x]
	var src_y := [0.0, source_margin_top, art.y - source_margin_top, art.y]
	var dst_x := [rect.position.x, rect.position.x + side, rect.end.x - side, rect.end.x]
	var dst_y := [rect.position.y, rect.position.y + top, rect.end.y - top, rect.end.y]
	var rid := texture.get_rid()
	for row in 3:
		for column in 3:
			var destination := Rect2(dst_x[column], dst_y[row], dst_x[column + 1] - dst_x[column], dst_y[row + 1] - dst_y[row])
			var source := Rect2(src_x[column], src_y[row], src_x[column + 1] - src_x[column], src_y[row + 1] - src_y[row])
			if destination.size.x > 0.0 and destination.size.y > 0.0:
				RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, destination, rid, source, modulate_color)
