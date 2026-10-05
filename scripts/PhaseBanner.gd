class_name PhaseBanner
extends Control

## The big phase announcement ("PLAYER PHASE" / "MONSTER PHASE"): the name fades in
## in large letters across the middle of the screen on a dark band, holds a moment and
## fades out again while a sound plays (PhaseSounds), as in the real game - so it is
## unmistakable when the game changes hands. Built in code and added by MissionPlayer as
## the last child of its CanvasLayer; ignores the mouse, so it never blocks anything.
##
## show_phase() returns at once (fire and forget); `finished` fires when the banner has
## faded out - `await banner.finished` where the game should wait for it (the monster
## phase does, so the first monster dialog doesn't land on top of the banner).

signal finished

const FADE_IN_SEC := 0.3
const HOLD_SEC := 1.1
const FADE_OUT_SEC := 0.9
const FONT_SIZE := 96

var _label: Label
var _sound_player: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false

	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.6)
	band.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.offset_top = -80
	band.offset_bottom = 80
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 14)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_sound_player = AudioStreamPlayer.new()
	add_child(_sound_player)


## Shows `text` in `color` and plays `sound`; restarts cleanly if a banner is still up.
func show_phase(text: String, color: Color, sound: AudioStream) -> void:
	if _tween != null:
		_tween.kill()
	_label.text = text.to_upper()
	_label.add_theme_color_override("font_color", color)
	_sound_player.stream = sound
	_sound_player.play()
	modulate.a = 0.0
	visible = true
	get_parent().move_child(self, -1)  # on top of whatever was added to the layer since
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_SEC)
	_tween.tween_interval(HOLD_SEC)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC)
	_tween.tween_callback(func():
		visible = false
		finished.emit()
	)
