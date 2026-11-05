class_name EditorIcons
extends RefCounted

## Small pictures for the editors' buttons, drawn as SVG text (24x24) and rasterised when asked for - no image files needed. Used by the
## Creator toolbar (select / draw / move / rotate) and the Palette's Misc tab (player start / monster spawn / LOS blocker).

const ICONS := {
	"select": '<path d="M6 3 L6 19.5 L10.2 15.6 L13 21.5 L15.6 20.3 L12.8 14.5 L18.5 14.5 Z" fill="white" stroke="#202020" stroke-width="1" stroke-linejoin="round"/>',
	"draw": '<path d="M3.5 20.5 L4.8 15.6 L15.8 4.6 L19.4 8.2 L8.4 19.2 Z" fill="white" stroke="#202020" stroke-width="1" stroke-linejoin="round"/>'
		+ '<path d="M14.2 6.2 L17.8 9.8" stroke="#202020" stroke-width="1.2"/><path d="M4.8 15.6 L8.4 19.2" stroke="#202020" stroke-width="1.2"/>'
		+ '<path d="M3.5 20.5 L4.8 15.6 L8.4 19.2 Z" fill="#202020"/>',
	"move": '<path d="M12 4 L12 20 M4 12 L20 12" stroke="white" stroke-width="2" stroke-linecap="round"/>'
		+ '<path d="M12 1.8 L8.6 6 L15.4 6 Z M12 22.2 L8.6 18 L15.4 18 Z M1.8 12 L6 8.6 L6 15.4 Z M22.2 12 L18 8.6 L18 15.4 Z" fill="white"/>',
	"rotate": '<path d="M18.06 15.5 A7 7 0 1 1 16.5 6.6" fill="none" stroke="white" stroke-width="2.2" stroke-linecap="round"/>'
		+ '<path d="M19.4 9.2 L14.2 9.3 L18.6 4 Z" fill="white"/>',
	"table": '<rect x="2.5" y="6" width="19" height="12" rx="2" fill="#b07a3c" stroke="#202020" stroke-width="1"/><rect x="5" y="8.5" width="14" height="7" rx="1" fill="#c99556"/>',
	"player_start": '<path d="M6 21.5 L6 3" stroke="white" stroke-width="2" stroke-linecap="round"/>'
		+ '<path d="M6 4 L19.5 4 L15.5 8.8 L19.5 13.6 L6 13.6 Z" fill="#ffd24a" stroke="#202020" stroke-width="1" stroke-linejoin="round"/>',
	"monster_spawn": '<path d="M12 2.5 C6.8 2.5 4 6.2 4 10.4 C4 13.4 5.6 15.2 7.8 16.2 L7.8 20 L16.2 20 L16.2 16.2 C18.4 15.2 20 13.4 20 10.4 C20 6.2 17.2 2.5 12 2.5 Z" fill="#e8e4d8" stroke="#202020" stroke-width="1" stroke-linejoin="round"/>'
		+ '<circle cx="8.8" cy="10.6" r="2.3" fill="#202020"/><circle cx="15.2" cy="10.6" r="2.3" fill="#202020"/>'
		+ '<path d="M12 13 L10.8 15.4 L13.2 15.4 Z" fill="#202020"/><path d="M10.2 17 V20 M12 17 V20 M13.8 17 V20" stroke="#202020" stroke-width="1"/>',
	"los_blocker": '<path d="M1.8 12 C5.8 5 18.2 5 22.2 12 C18.2 19 5.8 19 1.8 12 Z" fill="none" stroke="white" stroke-width="1.8" stroke-linejoin="round"/>'
		+ '<circle cx="12" cy="12" r="3.2" fill="white"/><path d="M4 20.5 L20 3.5" stroke="#ff6a55" stroke-width="2.4" stroke-linecap="round"/>',
}


static var _cache := {}


## The picture `icon_name` (a key of ICONS) at `scale` x 24 px; null if the SVG can't be rasterised.
static func icon(icon_name: String, scale := 1.0) -> Texture2D:
	var key := "%s@%s" % [icon_name, scale]
	if _cache.has(key):
		return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">%s</svg>' % ICONS[icon_name]
	var image := Image.new()
	var texture: Texture2D = null
	if image.load_svg_from_string(svg, scale) == OK:
		texture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
