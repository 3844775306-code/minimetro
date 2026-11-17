extends RefCounted
## M5：程序化音频（headless 下验证格式/长度/循环点，不依赖音频设备）。

static func run(h: TestHarness) -> void:
	_test_blip(h)
	_test_chime(h)
	_test_loop(h)


static func _test_blip(h: TestHarness) -> void:
	h.section("audio/blip")
	var stream := WaveGen.blip(880.0, 1320.0, 0.1, 0.3)
	h.check(stream != null, "生成非空音频流")
	h.eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "16bit 格式")
	h.eq(stream.mix_rate, WaveGen.SAMPLE_RATE, "使用音效采样率")
	h.check(not stream.stereo, "单声道")
	h.eq(stream.data.size(), int(0.1 * WaveGen.SAMPLE_RATE) * 2, "数据长度 = 时长 × 采样率 × 2")
	h.eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "短音效不循环")
	h.check(absi(stream.data.decode_s16(0)) < 400, "起始接近静音")
	h.check(absi(stream.data.decode_s16(stream.data.size() - 2)) < 400, "结尾接近静音")


static func _test_chime(h: TestHarness) -> void:
	h.section("audio/chime")
	var stream := WaveGen.chime([523.25, 659.25, 783.99], 0.3, 0.3)
	h.check(stream.data.size() > 0, "和弦钟声有数据")
	h.eq(stream.data.size(), int(0.3 * WaveGen.SAMPLE_RATE) * 2, "长度匹配时长")
	var peak := 0
	var step := maxi(1, stream.data.size() / 2 / 50)
	var index := 0
	while index < stream.data.size():
		peak = maxi(peak, absi(stream.data.decode_s16(index)))
		index += step * 2
	h.check(peak > 1000, "钟声有可闻振幅（峰值 %d）" % peak)
	h.check(peak < 32767, "未削波")


static func _test_loop(h: TestHarness) -> void:
	h.section("audio/loop")
	var stream := WaveGen.chord_loop([[220.0, 261.63], [174.61, 220.0]], 1.0, 0.2)
	h.eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "音乐循环模式")
	h.eq(stream.loop_begin, 0, "循环从 0 开始")
	h.eq(stream.loop_end, stream.data.size() / 2, "循环终点 = 样本数")
	h.eq(stream.mix_rate, WaveGen.MUSIC_RATE, "音乐用低采样率")
	h.check(absi(stream.data.decode_s16(0)) < 800, "循环起点做了淡入")
	h.check(absi(stream.data.decode_s16(stream.data.size() - 2)) < 800, "循环终点做了淡出")