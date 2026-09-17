extends RefCounted
class_name StressAudio

const SAMPLE_RATE := 22050
const PEAK_LIMIT := 0.32
static var _cache: Dictionary = {}


static func get_stream(kind: String) -> AudioStreamWAV:
	if kind not in ["whisper", "footsteps"]:
		return null
	if _cache.has(kind):
		return _cache[kind] as AudioStreamWAV
	var duration := 1.8 if kind == "whisper" else 1.45
	var sample_count := roundi(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 318117 if kind == "whisper" else 914531
	var fast_lowpass := 0.0
	var slow_lowpass := 0.0
	var peak := 0.000001
	for index in range(sample_count):
		var time := float(index) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		fast_lowpass += 0.40 * (noise - fast_lowpass)
		slow_lowpass += 0.035 * (noise - slow_lowpass)
		var value := 0.0
		if kind == "whisper":
			# Difference of low-pass filters bounds the airy noise band. Slow
			# breath/syllable envelopes imply distant speech without using a voice,
			# copyrighted recording, sharp transient, scream or intelligible words.
			var envelope := pow(sin(PI * time / duration), 1.5)
			var syllables := 0.25 + 0.75 * pow(0.5 + 0.5 * sin(time * TAU * 2.4 + sin(time * 3.0)), 2.0)
			value = (fast_lowpass - slow_lowpass) * envelope * syllables
		else:
			for onset: float in [0.12, 0.58, 1.02]:
				var local_time := time - onset
				if local_time >= 0.0 and local_time < 0.34:
					var envelope := minf(local_time / 0.018, 1.0) * exp(-local_time * 19.0)
					value += (slow_lowpass * 1.8 + sin(TAU * (82.0 * local_time - 35.0 * local_time * local_time)) * 0.18) * envelope
		var edge_fade := minf(1.0, minf(time, duration - time) / 0.025)
		samples[index] = value * maxf(edge_fade, 0.0)
		peak = maxf(peak, absf(samples[index]))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for index in range(sample_count):
		pcm.encode_s16(index * 2, roundi(clampf(samples[index] / peak * PEAK_LIMIT, -PEAK_LIMIT, PEAK_LIMIT) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	_cache[kind] = stream
	return stream
