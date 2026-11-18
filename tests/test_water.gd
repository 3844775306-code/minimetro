extends RefCounted
## M4：河道检测、桥隧预算、站点避水、形状权重。

static func run(h: TestHarness) -> void:
	_test_crossing_detect(h)
	_test_bridge_budget(h)
	_test_spawner_avoids_water(h)
	_test_shape_weights(h)
	_test_two_rivers_one_segment(h)


## 竖直河道把地图切成左右两半。
static func _level_with_river(bridges: int = 1) -> LevelData:
	var level := LevelData.new()
	level.rivers = [PackedVector2Array([
		Vector2(400, 0), Vector2(620, 0), Vector2(620, 1080), Vector2(400, 1080),
	])]
	level.start_bridges = bridges
	level.start_lines = 3
	level.start_trains = 0
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	return level


static func _test_crossing_detect(h: TestHarness) -> void:
	h.section("water/crossing")
	var level := _level_with_river(1)
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 500), Shape.Kind.SQUARE)
	var same_side := net.add_station(Vector2(300, 800), Shape.Kind.TRIANGLE)

	h.check(net.segment_crosses_water(a.pos, b.pos), "横跨河道需要桥")
	h.check(not net.segment_crosses_water(a.pos, same_side.pos), "同侧不需要桥")
	h.check(net.is_point_in_water(Vector2(500, 500)), "河中央在水里")
	h.eq(net.water_distance(Vector2(500, 500)), 0.0, "水里距离为 0")
	h.check(net.water_distance(Vector2(300, 500)) > 50.0, "离河道有距离")

	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	net.touch()
	h.eq(net.used_bridges(), 1, "一段跨河 = 1 座桥")
	h.eq(net.available_bridges(), 0, "桥隧额度用尽")


static func _test_bridge_budget(h: TestHarness) -> void:
	h.section("water/bridge_budget")
	var level := _level_with_river(0)
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 500), Shape.Kind.SQUARE)
	var editor := LineEditor.new()
	editor.setup(net, level, null)
	var toasts: Array[String] = []
	editor.toast_requested.connect(func(message: String) -> void: toasts.append(message))

	h.eq(editor.begin_gesture(a.pos), true, "从本站起手画线")
	editor.move_gesture(b.pos)
	h.eq(net.lines[0].stops.size(), 1, "没有桥时不能跨河接线")
	h.eq(toasts.size(), 1, "给出无桥提示")
	editor.end_gesture(b.pos)
	h.eq(net.lines.size(), 0, "不足两站的线抬手回滚")

	level.start_bridges = 1
	h.eq(editor.begin_gesture(a.pos), true, "再试一次")
	editor.move_gesture(b.pos)
	h.eq(net.lines[0].stops.size(), 2, "有桥时允许跨河")
	editor.end_gesture(b.pos)
	h.eq(net.used_bridges(), 1, "消耗一座桥")
	h.eq(net.available_bridges(), 0, "额度归零")
	editor.free()


static func _test_spawner_avoids_water(h: TestHarness) -> void:
	h.section("water/spawner")
	var level := _level_with_river(2)
	var net := MetroNetwork.new(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spawner := StationSpawner.new(level, rng)
	for i in 14:
		spawner.try_spawn(net)
	h.check(net.stations.size() >= 4, "河道两岸都能生成站点（实际 %d）" % net.stations.size())
	var clear := true
	for st in net.stations:
		if net.is_point_in_water(st.pos):
			clear = false
		if net.water_distance(st.pos) < level.station_water_clearance:
			clear = false
	h.check(clear, "站点都不在河里，且离岸有安全距离")


static func _test_shape_weights(h: TestHarness) -> void:
	h.section("water/shape_weights")
	var level := LevelData.new()
	level.rivers = []
	level.station_shape_weights = {Shape.Kind.DIAMOND: 1.0}
	level.station_min_distance = 60.0
	var net := MetroNetwork.new(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var spawner := StationSpawner.new(level, rng)
	for i in 3:
		spawner.try_spawn(net)
	h.eq(net.stations.size(), 3, "生成三个站点")
	for st in net.stations:
		h.eq(st.shape, Shape.Kind.DIAMOND, "权重表生效：全部为菱形")


## 同一段线路连续穿过两条独立河流，必须消耗 2 座桥，而不是 1 座。
static func _test_two_rivers_one_segment(h: TestHarness) -> void:
	h.section("water/two_rivers_one_segment")
	var level := LevelData.new()
	level.rivers = [
		PackedVector2Array([
			Vector2(300, 0), Vector2(420, 0), Vector2(420, 1000), Vector2(300, 1000),
		]),
		PackedVector2Array([
			Vector2(600, 0), Vector2(720, 0), Vector2(720, 1000), Vector2(600, 1000),
		]),
	]
	level.start_bridges = 1
	level.start_lines = 3
	level.start_trains = 0
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(100, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(900, 500), Shape.Kind.SQUARE)
	h.eq(net.segment_bridge_count(a.pos, b.pos), 2, "一段连续跨两条河 = 2 座桥")
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	net.touch()
	h.eq(net.line_bridge_count(line), 2, "线路桥数也计为 2")
	h.eq(net.used_bridges(), 2, "总桥数使用 2")
	var editor := LineEditor.new()
	editor.setup(net, level, null)
	var toasts: Array[String] = []
	editor.toast_requested.connect(func(message: String) -> void: toasts.append(message))
	editor.begin_gesture(a.pos)
	editor.move_gesture(b.pos)
	h.eq(network_line_count_free(net), 1, "没有桥额度时第二条跨河线不会被接上")
	h.eq(toasts.size(), 1, "给出无桥提示")
	editor.cancel_gesture()
	editor.free()


static func network_line_count_free(net: MetroNetwork) -> int:
	# 只保留第一条完整线路；草稿线若被拒会立即回滚
	var count := 0
	for line in net.lines:
		if line.stops.size() >= 2:
			count += 1
	return count