extends RefCounted
## 云端模拟器（排行榜 / 每日榜 / 地图大厅）的纯数据行为。

static func run(h: TestHarness) -> void:
	_test_daily(h)
	_test_best(h)
	_test_map_hall(h)
	_test_daily_city(h)


static func _test_daily(h: TestHarness) -> void:
	h.section("cloud/daily")
	var dates := Cloud.recent_dates(7)
	h.eq(dates.size(), 7, "最近一周有 7 天")
	h.eq(dates[0], Time.get_date_string_from_system(), "第一天是今天")
	var board := Cloud.daily_leaderboard(dates[0], 8)
	h.check(not board.is_empty(), "每日榜有成绩")
	var sorted := true
	for i in range(1, board.size()):
		if int(board[i - 1].get("score", 0)) < int(board[i].get("score", 0)):
			sorted = false
	h.check(sorted, "每日榜按分数降序")

	Cloud.submit_daily(dates[0], 9999)
	var updated := Cloud.daily_leaderboard(dates[0], 8)
	h.eq(String(updated[0].get("name", "")), Cloud.player_name(), "提交后自己是第一")
	h.eq(int(updated[0].get("score", 0)), 9999, "每日成绩已更新")
	var lines := Cloud.recent_daily_lines(7, 3)
	h.eq(lines.size(), 7, "每日榜可以生成一周文本")


static func _test_best(h: TestHarness) -> void:
	h.section("cloud/best")
	var board := Cloud.best_leaderboard("classic", "paper", 8)
	h.check(not board.is_empty(), "地图排行榜有成绩")
	Cloud.submit_best("classic", "paper", 12345)
	var updated := Cloud.best_leaderboard("classic", "paper", 8)
	h.eq(String(updated[0].get("name", "")), Cloud.player_name(), "最高纪录上传后自己是第一")
	h.eq(int(updated[0].get("score", 0)), 12345, "分地图最高纪录已更新")


static func _test_map_hall(h: TestHarness) -> void:
	h.section("cloud/map_hall")
	var maps := Cloud.maps()
	h.check(maps.size() >= 1, "地图大厅有可下载地图")
	var first_id := String(maps[0].get("id", ""))
	var downloaded := Cloud.download_map(first_id)
	h.check(not downloaded.is_empty(), "地图可以下载")
	var map := CustomMapStore.new_map([
		CityMaps.editor_band(PackedVector2Array([
			Vector2(300, 300), Vector2(700, 500), Vector2(1100, 400),
		]), 100.0),
	], 100.0, "测试上传图")
	h.check(Cloud.upload_map(map), "地图可以上传到大厅")
	var after := Cloud.maps(30)
	var found := false
	for entry in after:
		if String(entry.get("id", "")) == String(map["id"]):
			found = true
	h.check(found, "上传后大厅能看到该地图")


static func _test_daily_city(h: TestHarness) -> void:
	h.section("cloud/daily_city")
	var a := GameMode.daily_city_index("2026-11-17", 7)
	var b := GameMode.daily_city_index("2026-11-17", 7)
	h.eq(a, b, "同一天的每日地图相同")
	h.check(a >= 0 and a < 7, "每日地图索引有效")
	var different := false
	for offset in range(1, 14):
		if GameMode.daily_city_index("2026-11-%02d" % (17 + offset), 7) != a:
			different = true
	h.check(different, "不同日期会随机到不同地图")