extends RefCounted

# Small, deterministic tool sounds. The caller owns playback, bus selection,
# volume and muting; constructing or testing these streams never plays audio.
const SAMPLE_RATE := 22050
const SUPPORTED_ACTIONS := [
	"pour_base", "add_herb", "add_whole", "add_to_mortar", "grind", "pour_mortar",
	"pump_bellows", "lower_cauldron", "raise_cauldron", "turn_hourglass", "stir",
	"start_distillation", "bottle", "discard",
]
const DURATIONS := {
	"pour_base": 0.56, "add_herb": 0.23, "add_whole": 0.26, "add_to_mortar": 0.24,
	"grind": 0.38, "pour_mortar": 0.41, "pump_bellows": 0.52,
	"lower_cauldron": 0.32, "raise_cauldron": 0.35, "turn_hourglass": 0.34,
	"stir": 0.44, "start_distillation": 0.42, "bottle": 0.36, "discard": 0.50,
}
static var _cache: Dictionary = {}


static func stream_for(action: String) -> AudioStreamWAV:
	if not DURATIONS.has(action):
		return null
	if _cache.has(action):
		return _cache[action] as AudioStreamWAV
	var duration := float(DURATIONS[action])
	var frame_count := roundi(duration * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 711 + absi(action.hash())
	var low_noise := 0.0
	var pitch_offset := float(absi(action.hash()) % 43)
	for frame in frame_count:
		var time := float(frame) / SAMPLE_RATE
		var progress := time / duration
		var noise := random.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.18)
		var high_noise := noise - low_noise
		var signal_value := 0.0
		match action:
			"pour_base", "discard":
				# A broad liquid rustle punctuated by rounded, rising bubbles.
				var bubble_phase := fmod(time * 10.0, 1.0)
				var bubble := sin(TAU * (280.0 + pitch_offset) * time + 24.0 * time * time) * exp(-bubble_phase * 7.0)
				signal_value = low_noise * 0.72 + high_noise * 0.08 + bubble * 0.19
			"grind":
				# Grit travels over stone; the slow envelope reads as one stroke.
				var scrape := 0.55 + 0.25 * sin(TAU * 39.0 * time) + 0.14 * sin(TAU * 87.0 * time)
				signal_value = high_noise * scrape * 0.48 + low_noise * 0.22
			"pump_bellows":
				# Soft air through a wooden nozzle, without a sharp click.
				var breath := pow(sin(PI * progress), 0.7)
				signal_value = (low_noise * 0.85 + noise * 0.08) * breath
			"stir":
				var water := low_noise * (0.42 + 0.12 * sin(TAU * 6.0 * time))
				var wood := _ring(time, 0.025, 183.0, 24.0) + _ring(time, 0.23, 207.0, 30.0) * 0.6
				signal_value = water + wood * 0.22
			"bottle", "turn_hourglass":
				# Two muted glass resonances, damped quickly to stay unobtrusive.
				var second_hit := 0.14 if action == "turn_hourglass" else 0.105
				var glass := _ring(time, 0.008, 1370.0 + pitch_offset, 24.0) * 0.34
				glass += _ring(time, 0.008, 2180.0 + pitch_offset, 34.0) * 0.15
				glass += _ring(time, second_hit, 1610.0 + pitch_offset, 30.0) * 0.17
				signal_value = glass + low_noise * 0.025
			"start_distillation":
				var fitting := _ring(time, 0.018, 720.0, 22.0) * 0.28 + _ring(time, 0.15, 1180.0, 28.0) * 0.16
				var seating := low_noise * 0.3 * exp(-absf(time - 0.16) * 13.0)
				signal_value = fitting + seating
			"lower_cauldron", "raise_cauldron":
				var chain := high_noise * 0.18 * (0.55 + 0.45 * sin(TAU * 19.0 * time))
				var knock := _ring(time, 0.025, 320.0 + pitch_offset, 22.0) * 0.23
				signal_value = chain + knock
			"add_to_mortar":
				signal_value = high_noise * 0.18 + _ring(time, 0.025, 460.0, 38.0) * 0.25
			"pour_mortar":
				signal_value = high_noise * 0.19 + low_noise * 0.26 + _ring(time, 0.02, 570.0, 32.0) * 0.15
			_: # Whole or newly picked herbs: a short dry leaf rustle.
				signal_value = high_noise * 0.26 * (0.65 + 0.35 * sin(TAU * (22.0 + pitch_offset) * time)) + low_noise * 0.18
		# Smooth endpoints prevent PCM discontinuities, and conservative gain
		# leaves ample headroom before the UI's separate volume adjustment.
		var attack := smoothstep(0.0, 0.012, time)
		var release := smoothstep(0.0, 0.07, duration - time - 1.0 / SAMPLE_RATE)
		var sample := clampf(signal_value * attack * release * 0.58, -0.82, 0.82)
		pcm.encode_s16(frame * 2, roundi(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	_cache[action] = stream
	return stream


static func _ring(time: float, onset: float, frequency: float, decay: float) -> float:
	var local_time := time - onset
	if local_time < 0.0:
		return 0.0
	return sin(TAU * frequency * local_time) * exp(-local_time * decay)
