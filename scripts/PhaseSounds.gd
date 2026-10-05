class_name PhaseSounds
extends RefCounted

## The sounds of the phase banners (PhaseBanner): generated in code, so the project
## ships no copyrighted audio - a bright chime for the player phase and a low,
## inharmonic gong for the monster phase. Each is built once and cached. Never
## instantiated.

const MIX_RATE := 22050

static var _player_phase: AudioStreamWAV
static var _monster_phase: AudioStreamWAV


static func player_phase() -> AudioStreamWAV:
	if _player_phase == null:
		# A clean bell: harmonic partials, medium decay.
		_player_phase = _bell(523.25, [[1.0, 1.0], [2.0, 0.5], [3.0, 0.25], [4.2, 0.12]], 1.6, 3.2, 0.0)
	return _player_phase


static func monster_phase() -> AudioStreamWAV:
	if _monster_phase == null:
		# A low gong: inharmonic partials, slow decay, a slow wobble.
		_monster_phase = _bell(98.0, [[1.0, 1.0], [1.5, 0.55], [2.76, 0.5], [5.4, 0.28], [8.9, 0.14]], 2.4, 1.5, 5.0)
	return _monster_phase


## `partials`: [[frequency ratio, amplitude], ...] on `fundamental`; `decay` is the
## exponential decay rate per second; `wobble_hz` > 0 adds a slow tremolo.
static func _bell(fundamental: float, partials: Array, duration: float, decay: float, wobble_hz: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var total_amplitude := 0.0
	for partial in partials:
		total_amplitude += float(partial[1])
	for i in count:
		var t := float(i) / MIX_RATE
		var sample := 0.0
		for partial in partials:
			var ratio: float = partial[0]
			sample += float(partial[1]) * sin(TAU * fundamental * ratio * t) * exp(-t * decay * sqrt(ratio))
		sample /= total_amplitude
		sample *= minf(t / 0.005, 1.0)  # a short attack so it does not click
		if wobble_hz > 0.0:
			sample *= 0.85 + 0.15 * sin(TAU * wobble_hz * t)
		data.encode_s16(i * 2, int(clampf(sample * 0.8, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
