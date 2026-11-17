class_name WaveGen
extends RefCounted
## 程序化音频生成：不依赖任何音频素材文件，启动时合成短音效与氛围循环。
## 输出 16bit 单声道 AudioStreamWAV；音乐用较低采样率（氛围铺底不需要高频）。

const SAMPLE_RATE := 22050
const MUSIC_RATE := 11025


static func _to_stream(samples: PackedFloat32Array, loop: bool, rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


## 单音滑音：带二次衰减包络，用于点击/送达/警告音。
static func blip(freq_start: float, freq_end: float, duration: float,
		volume: float = 0.3, rate: int = SAMPLE_RATE) -> AudioStreamWAV:
	var count := maxi(1, int(duration * float(rate)))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var freq := lerpf(freq_start, freq_end, t)
		var env := (1.0 - t) * (1.0 - t)
		samples[i] = sin(phase) * env * volume
		phase += TAU * freq / float(rate)
	return _to_stream(samples, false, rate)


## 和弦钟声：几个正弦 + 轻微失谐叠加，用于站点出现/升级/结束。
static func chime(freqs: Array[float], duration: float, volume: float = 0.3,
		rate: int = SAMPLE_RATE) -> AudioStreamWAV:
	var count := maxi(1, int(duration * float(rate)))
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(count)
		var env := (1.0 - t) * (1.0 - t)
		var value := 0.0
		for f in freqs:
			value += sin(TAU * f * float(i) / float(rate))
			value += sin(TAU * f * 1.003 * float(i) / float(rate)) * 0.3
		samples[i] = value / float(maxi(1, freqs.size())) * env * volume
	return _to_stream(samples, false, rate)


## 氛围铺底循环：几组和弦依次交叉淡入淡出，首尾再做一次交叉淡化保证无缝循环。
static func chord_loop(chords: Array, seconds_per_chord: float, volume: float = 0.2,
		rate: int = MUSIC_RATE) -> AudioStreamWAV:
	var total := maxi(1, int(chords.size() * seconds_per_chord * float(rate)))
	var samples := PackedFloat32Array()
	samples.resize(total)
	for c in chords.size():
		var chord: Array = chords[c]
		var start := int(float(c) * seconds_per_chord * float(rate))
		var end := mini(total, start + int(seconds_per_chord * float(rate)))
		if end <= start:
			continue
		for i in range(start, end):
			var t := float(i - start) / float(end - start)
			var env := minf(1.0, minf(t / 0.22, (1.0 - t) / 0.22))
			env = clampf(env, 0.0, 1.0)
			var value := 0.0
			for f in chord:
				value += sin(TAU * float(f) * float(i) / float(rate))
				value += sin(TAU * float(f) * 2.0 * float(i) / float(rate)) * 0.12
			samples[i] += value / float(maxi(1, chord.size())) * env * volume
	var fade := mini(int(0.5 * float(rate)), total / 4)
	for i in fade:
		var a := float(i) / float(fade)
		samples[i] *= a
		samples[total - 1 - i] *= a
	return _to_stream(samples, true, rate)
