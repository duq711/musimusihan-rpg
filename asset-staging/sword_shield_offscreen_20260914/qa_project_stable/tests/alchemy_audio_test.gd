extends SceneTree

const Audio := preload("res://scripts/alchemy_audio.gd")
var failures: Array[String] = []


func _initialize() -> void:
	# Inspect PCM data only. No AudioStreamPlayer, scene, window or playback.
	var fingerprints: Dictionary = {}
	for action in Audio.SUPPORTED_ACTIONS:
		var stream := Audio.stream_for(action)
		_check(stream != null, "%s must produce an audio stream" % action)
		if stream == null:
			continue
		_check(stream == Audio.stream_for(action), "%s must reuse its cached stream" % action)
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050 and not stream.stereo, "%s must expose consistent mono 16-bit PCM" % action)
		_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s must never loop indefinitely" % action)
		_check(stream.get_length() >= 0.2 and stream.get_length() <= 0.6, "%s must remain a short tactile cue" % action)
		_check(not stream.data.is_empty() and stream.data.size() % 2 == 0, "%s must contain complete PCM samples" % action)
		var peak := 0
		var energy := 0.0
		for frame in stream.data.size() / 2:
			var sample := stream.data.decode_s16(frame * 2)
			peak = maxi(peak, absi(sample))
			energy += pow(float(sample) / 32767.0, 2.0)
		_check(peak > 100 and peak < 28000, "%s must be audible data with safe headroom and no clipped peaks" % action)
		_check(energy / float(stream.data.size() / 2) > 0.00001, "%s must not silently produce an empty waveform" % action)
		_check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size() - 2) == 0, "%s must fade to zero at both boundaries" % action)
		var fingerprint := hash(stream.data)
		_check(not fingerprints.has(fingerprint), "%s must have a distinct tool sound" % action)
		fingerprints[fingerprint] = action
	_check(Audio.stream_for("unknown") == null and Audio.stream_for("select_recipe") == null, "unsupported and silent menu actions must not create arbitrary sounds")
	if failures.is_empty():
		print("ALCHEMY AUDIO TEST PASS: cached distinct PCM cues, short duration, safe peaks, smooth endpoints; no audio played")
		quit(0)
	else:
		for failure in failures:
			push_error("ALCHEMY AUDIO TEST FAIL: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
