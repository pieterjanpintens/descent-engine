class_name TableCameraPanel
extends VBoxContainer

## Options > Table camera: where the Ascent Camera phone app is (address + pairing code, saved in PlayerSettings at once),
## a connection check and a test photo with a small preview, so the framing can be checked from the PC. "Open the full
## photo" saves the last photo to LAST_PHOTO and opens it in the system's picture viewer. See TableCamera.

const LAST_PHOTO := "user://camera/last_photo.jpg"
const TEXT_WIDTH := 640.0
const PREVIEW_HEIGHT := 190.0

var _camera := TableCamera.new()
var _address: LineEdit
var _code: LineEdit
var _check_button: Button
var _photo_button: Button
var _open_button: Button
var _status: Label
var _preview: TextureRect
var _last_image: Image


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_camera)

	var intro := Label.new()
	intro.text = "An Android phone with the Ascent Camera app can photograph the table. Start the camera in the app and type in the address and pairing code it shows (same network as this computer)."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = TEXT_WIDTH
	add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	add_child(grid)
	var address_label := Label.new()
	address_label.text = "Address"
	grid.add_child(address_label)
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.0.19:8765"
	_address.custom_minimum_size.x = 260
	_address.text = PlayerSettings.table_camera_address
	_address.text_changed.connect(func(text: String):
		PlayerSettings.table_camera_address = text.strip_edges()
		PlayerSettings.save_settings())
	grid.add_child(_address)
	var code_label := Label.new()
	code_label.text = "Pairing code"
	grid.add_child(code_label)
	_code = LineEdit.new()
	_code.placeholder_text = "123456"
	_code.max_length = 12
	_code.custom_minimum_size.x = 140
	_code.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_code.text = PlayerSettings.table_camera_code
	_code.text_changed.connect(func(text: String):
		PlayerSettings.table_camera_code = text.strip_edges()
		PlayerSettings.save_settings())
	grid.add_child(_code)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	_check_button = Button.new()
	_check_button.text = "Test the connection"
	_check_button.pressed.connect(_on_check_pressed)
	buttons.add_child(_check_button)
	_photo_button = Button.new()
	_photo_button.text = "Take a test photo"
	_photo_button.pressed.connect(_on_photo_pressed)
	buttons.add_child(_photo_button)
	_open_button = Button.new()
	_open_button.text = "Open the full photo"
	_open_button.disabled = true
	_open_button.pressed.connect(_on_open_pressed)
	buttons.add_child(_open_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = TEXT_WIDTH
	add_child(_status)

	# A fixed-size box, so a photo never changes the page's height.
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_preview)


func _set_busy(busy: bool) -> void:
	_check_button.disabled = busy
	_photo_button.disabled = busy
	_open_button.disabled = busy or _last_image == null


func _on_check_pressed() -> void:
	_set_busy(true)
	_status.text = tr("Connecting to the camera...")
	var answer := await _camera.check()
	_set_busy(false)
	if answer["ok"]:
		_status.text = tr("Connected to %s (Ascent Camera %s).") % [answer["device"], answer["version"]]
	else:
		_status.text = answer["error"]


func _on_photo_pressed() -> void:
	_set_busy(true)
	_status.text = tr("Taking a photo...")
	var answer := await _camera.take_photo()
	if answer["ok"]:
		_last_image = answer["image"]
		var small := (_last_image as Image).duplicate() as Image
		var width := 640
		small.resize(width, maxi(1, roundi(width * float(small.get_height()) / small.get_width())), Image.INTERPOLATE_BILINEAR)
		_preview.texture = ImageTexture.create_from_image(small)
		_status.text = tr("Photo of %d x %d pixels, taken in %.1f seconds.") % [_last_image.get_width(), _last_image.get_height(), answer["seconds"]]
	else:
		_status.text = answer["error"]
	_set_busy(false)


func _on_open_pressed() -> void:
	if _last_image == null:
		return
	DirAccess.make_dir_recursive_absolute(LAST_PHOTO.get_base_dir())
	if _last_image.save_jpg(LAST_PHOTO, 0.9) != OK:
		_status.text = tr("Could not save the photo.")
		return
	OS.shell_open(ProjectSettings.globalize_path(LAST_PHOTO))
