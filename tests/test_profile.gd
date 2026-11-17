extends RefCounted
## M6：玩家档案（设置 / 最高分 / 每日成绩 / JSON 持久化）。

static func run(h: TestHarness) -> void:
	_test_defaults(h)
	_test_scores(h)
	_test_roundtrip(h)


static func _test_defaults(h: TestHarness) -> void:
	h.section("profile/defaults")
	var profile := Profile.new()
	h.near(float(profile.get_setting("master_volume", 0.0)), 0.8, 0.001, "默认主音量 80%")
	h.eq(String(profile.get_setting("language", "")), "zh", "默认中文")
	h.eq(profile.best_score("classic"), 0, "默认没有最高分")
	h.eq(profile.daily_best("2026-11-17"), 0, "默认没有每日成绩")


static func _test_scores(h: TestHarness) -> void:
	h.section("profile/scores")
	var profile := Profile.new()
	profile.set_setting("master_volume", 0.4)
	h.near(float(profile.get_setting("master_volume")), 0.4, 0.001, "设置可写入")

	h.check(profile.record_score("classic", 30), "首次成绩刷新纪录")
	h.eq(profile.best_score("classic"), 30, "经典最高分 30")
	h.check(not profile.record_score("classic", 20), "低分不刷新")
	h.eq(profile.best_score("classic"), 30, "纪录仍为 30")
	h.check(profile.record_score("endless", 77), "无尽成绩独立记录")
	h.eq(profile.best_score("endless"), 77, "无尽最高分 77")

	h.check(profile.record_daily("2026-11-17", 12), "每日成绩记录")
	h.eq(profile.daily_best("2026-11-17"), 12, "当日最高 12")
	h.check(not profile.record_daily("", 99), "空日期不记录")
	h.eq(profile.daily_best(""), 0, "空日期没有成绩")


static func _test_roundtrip(h: TestHarness) -> void:
	h.section("profile/roundtrip")
	var profile := Profile.new()
	profile.set_setting("language", "en")
	profile.set_setting("fullscreen", true)
	profile.set_setting("music_volume", 0.1)
	profile.record_score("endless", 88)
	profile.record_daily("2026-11-17", 42)

	var loaded := Profile.from_json(profile.to_json())
	h.check(loaded != null, "JSON 可解析")
	if loaded != null:
		h.eq(String(loaded.get_setting("language")), "en", "语言持久化")
		h.eq(bool(loaded.get_setting("fullscreen")), true, "全屏持久化")
		h.near(float(loaded.get_setting("music_volume")), 0.1, 0.001, "音乐音量持久化")
		h.eq(loaded.best_score("endless"), 88, "最高分持久化")
		h.eq(loaded.daily_best("2026-11-17"), 42, "每日成绩持久化")

	h.check(Profile.from_json("not json") == null, "坏存档解析返回 null")
	h.check(Profile.from_json("") == null, "空存档解析返回 null")