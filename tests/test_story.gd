extends RefCounted
## 故事化城镇：地标语义、发展阶段的形状解锁/车站增长/相机拉远、按时段的乘客出行规律。

static func run(h: TestHarness) -> void:
	_test_starting_trio(h)
	_test_landmarks(h)
	_test_stages(h)
	_test_time_rules(h)
	_test_station_unlock_in_sim(h)
	_test_passenger_pattern(h)


## 开局固定三座基础车站：圆形、三角形、方形。
static func _test_starting_trio(h: TestHarness) -> void:
	h.section("story/starting_trio")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var spawner := StationSpawner.new(level, rng)
	spawner.spawn_starting_trio(net)
	h.eq(net.stations.size(), 3, "开局正好三座车站")
	var shapes := {}
	for st in net.stations:
		shapes[st.shape] = true
	h.check(shapes.has(Shape.Kind.CIRCLE), "开局有圆形（居民区）")
	h.check(shapes.has(Shape.Kind.TRIANGLE), "开局有三角形（商务区）")
	h.check(shapes.has(Shape.Kind.SQUARE), "开局有方形（车站）")


static func _make_level(hour: float = 7.0) -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = 0
	level.start_interchanges = 0
	level.start_hour = hour
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 9999.0
	return level


static func _make_sim(net: MetroNetwork, level: LevelData) -> Simulation:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	return sim


static func _add_stations(net: MetroNetwork, count: int, kinds: Array = []) -> void:
	for i in count:
		var shape_kind: int = Shape.Kind.CIRCLE if kinds.is_empty() else int(kinds[i % kinds.size()])
		net.add_station(Vector2(180.0 + float(i % 8) * 190.0,
			180.0 + float(i / 8) * 170.0), shape_kind)


static func _test_landmarks(h: TestHarness) -> void:
	h.section("story/landmarks")
	var kinds := [
		Shape.Kind.CIRCLE, Shape.Kind.SQUARE, Shape.Kind.TRIANGLE,
		Shape.Kind.PLUS, Shape.Kind.DIAMOND, Shape.Kind.STAR,
		Shape.Kind.PENTAGON, Shape.Kind.HEXAGON, Shape.Kind.OCTAGON,
		Shape.Kind.RING, Shape.Kind.SEMICIRCLE, Shape.Kind.CLOVER,
	]
	var names := {}
	for kind in kinds:
		var name := Shape.landmark_name(kind)
		h.check(name != "", "地标有名称：" + Shape.shape_name(kind))
		h.check(not names.has(name), "地标名称不重复：" + name)
		names[name] = true
		h.check(Shape.landmark_role(kind) != "unknown", "地标有角色：" + name)
	h.eq(Shape.landmark_name(Shape.Kind.CIRCLE), "居民区", "圆形 = 居民区")
	h.eq(Shape.landmark_name(Shape.Kind.SQUARE), "车站", "方形 = 车站")
	h.eq(Shape.landmark_name(Shape.Kind.TRIANGLE), "商务区", "三角形 = 商务区")
	h.eq(Shape.landmark_name(Shape.Kind.PLUS), "医院", "加号 = 医院")
	h.eq(Shape.landmark_name(Shape.Kind.DIAMOND), "度假区", "菱形 = 度假区")
	h.eq(Shape.landmark_name(Shape.Kind.STAR), "景点", "星形 = 景点")
	h.eq(Shape.landmark_name(Shape.Kind.PENTAGON), "市政厅", "五边形 = 市政厅")
	h.eq(Shape.landmark_name(Shape.Kind.HEXAGON), "大学", "六边形 = 大学")
	h.eq(Shape.landmark_name(Shape.Kind.OCTAGON), "体育场", "八边形 = 体育场")
	h.eq(Shape.landmark_name(Shape.Kind.RING), "公园", "圆环 = 公园")
	h.eq(Shape.landmark_name(Shape.Kind.SEMICIRCLE), "博物馆", "半圆 = 博物馆")
	h.eq(Shape.landmark_name(Shape.Kind.CLOVER), "花园", "四叶草 = 花园")
	h.check(Shape.polygon(Shape.Kind.RING).is_empty(), "圆环用特殊绘制（无多边形）")
	var shapes_with_polygon := [
		Shape.Kind.PENTAGON, Shape.Kind.HEXAGON, Shape.Kind.OCTAGON,
		Shape.Kind.SEMICIRCLE, Shape.Kind.CLOVER,
	]
	for kind in shapes_with_polygon:
		h.check(Shape.polygon(kind).size() >= 5, "新形状有多边形：" + Shape.shape_name(kind))


static func _test_stages(h: TestHarness) -> void:
	h.section("story/stages")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var sim := _make_sim(net, level)
	_add_stations(net, 3)
	h.eq(sim.development_stage(), 0, "3 站时是村庄")
	var weights0 := sim.station_shape_weights()
	h.check(weights0.has(Shape.Kind.CIRCLE) and weights0.has(Shape.Kind.SQUARE),
		"村庄有居民区和车站")
	h.check(weights0.has(Shape.Kind.TRIANGLE), "村庄也有商务区（开局三站之一）")
	h.check(not weights0.has(Shape.Kind.PENTAGON), "村庄没有市政厅")
	h.near(sim.camera_zoom_target(), 1.25, 0.001, "开局相机较近（1.25）")

	_add_stations(net, 6)
	h.eq(sim.development_stage(), 1, "9 站时是小镇")
	h.check(sim.station_shape_weights().has(Shape.Kind.PENTAGON), "小镇解锁市政厅")
	h.check(sim.station_shape_weights().has(Shape.Kind.PLUS), "小镇解锁医院")
	_add_stations(net, 6)
	h.eq(sim.development_stage(), 2, "15 站时是城市")
	var weights2 := sim.station_shape_weights()
	h.check(weights2.has(Shape.Kind.STAR), "城市解锁景点")
	h.check(weights2.has(Shape.Kind.HEXAGON), "城市解锁大学")
	h.check(not weights2.has(Shape.Kind.DIAMOND), "城市还没有度假区")
	_add_stations(net, 6)
	h.eq(sim.development_stage(), 3, "21 站时是大都市")
	var weights3 := sim.station_shape_weights()
	h.check(weights3.has(Shape.Kind.DIAMOND), "大都市解锁度假区")
	h.check(weights3.has(Shape.Kind.SEMICIRCLE), "大都市解锁博物馆")
	h.check(weights3.has(Shape.Kind.OCTAGON), "大都市解锁体育场")
	h.check(not weights3.has(Shape.Kind.RING), "大都市还没有公园")
	_add_stations(net, 8)
	h.eq(sim.development_stage(), 4, "29 站时是都会")
	h.check(sim.station_shape_weights().has(Shape.Kind.RING), "都会解锁公园")
	h.check(sim.station_shape_weights().has(Shape.Kind.CLOVER), "都会解锁花园")
	_add_stations(net, 8)
	h.near(sim.camera_zoom_target(), 1.0, 0.001, "车站足够多时相机回到正常距离 1.0")
	h.check(sim.station_interval() < level.station_spawn_interval,
		"城镇越大，新车站出现越快")


static func _test_time_rules(h: TestHarness) -> void:
	h.section("story/time")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var sim := _make_sim(net, level)
	h.near(sim.hour_of_day(), 7.0, 0.01, "开局 07:00")
	h.check(sim.origin_activity(Shape.Kind.CIRCLE) > sim.origin_activity(Shape.Kind.TRIANGLE),
		"早高峰居民区出门更多")
	var morning_to_business: float = sim.destination_weights(Shape.Kind.CIRCLE)[Shape.Kind.TRIANGLE]
	sim.elapsed = 11.0
	h.near(sim.hour_of_day(), 18.0, 0.01, "时间推进到 18:00")
	h.check(sim.origin_activity(Shape.Kind.TRIANGLE) > sim.origin_activity(Shape.Kind.CIRCLE),
		"晚高峰商务区下班更多")
	var evening_to_business: float = sim.destination_weights(Shape.Kind.CIRCLE)[Shape.Kind.TRIANGLE]
	h.check(morning_to_business > evening_to_business,
		"居民区早上更想去商务区，晚上变少")
	h.check(sim.destination_weights(Shape.Kind.TRIANGLE)[Shape.Kind.CIRCLE]
		> sim.destination_weights(Shape.Kind.CIRCLE)[Shape.Kind.CIRCLE],
		"商务区晚高峰更想回居民区")

	# 周末 vs 工作日（同样 12:00）
	var weekend_level := _make_level(12.0)
	var weekend_net := MetroNetwork.new(weekend_level)
	var weekend_sim := _make_sim(weekend_net, weekend_level)
	weekend_sim.elapsed = 24.0 * 5.0  # 第 5 天 = 周六
	h.check(weekend_sim.is_weekend(), "第 5 天是周末")
	var weekend_resort := weekend_sim.origin_activity(Shape.Kind.DIAMOND)
	var weekday_sim := _make_sim(MetroNetwork.new(_make_level(12.0)), _make_level(12.0))
	weekday_sim.elapsed = 24.0 * 2.0  # 周三
	h.check(not weekday_sim.is_weekend(), "第 2 天是工作日")
	h.check(weekend_resort > weekday_sim.origin_activity(Shape.Kind.DIAMOND),
		"周末度假区更活跃")
	h.check(weekend_sim.destination_weights(Shape.Kind.CIRCLE)[Shape.Kind.DIAMOND]
		> weekday_sim.destination_weights(Shape.Kind.CIRCLE)[Shape.Kind.DIAMOND],
		"周末居民区更想去度假区")


## 实际生成循环里，村庄阶段只会生成居民区/车站。
static func _test_station_unlock_in_sim(h: TestHarness) -> void:
	h.section("story/spawn_unlock")
	var level := _make_level()
	level.station_spawn_interval = 0.1
	level.max_stations = 20
	var net := MetroNetwork.new(level)
	_add_stations(net, 6)
	var sim := _make_sim(net, level)
	sim.auto_spawn = true
	for i in 600:
		sim.tick(Simulation.STEP)
		if net.stations.size() >= 8:
			break
	h.check(net.stations.size() > 6, "村庄会继续出现新车站（%d）" % net.stations.size())
	for i in range(6, mini(net.stations.size(), 8)):
		var kind := net.stations[i].shape
		h.check(kind == Shape.Kind.CIRCLE or kind == Shape.Kind.SQUARE
			or kind == Shape.Kind.TRIANGLE,
			"村庄阶段只出现居民区/车站/商务区")


static func _test_passenger_pattern(h: TestHarness) -> void:
	h.section("story/passengers")
	var level := _make_level(7.0)
	var net := MetroNetwork.new(level)
	var circle := net.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	var business := net.add_station(Vector2(900, 300), Shape.Kind.TRIANGLE)
	var sim := _make_sim(net, level)
	for i in 240:
		sim._spawn_passenger()
	h.check(circle.waiting.size() > business.waiting.size(),
		"早高峰居民区产生更多乘客（%d vs %d）" % [circle.waiting.size(), business.waiting.size()])
	var all_to_business := true
	for passenger in circle.waiting:
		if passenger.target_shape != Shape.Kind.TRIANGLE:
			all_to_business = false
	h.check(all_to_business, "居民区早高峰的乘客目的地是商务区")

	circle.waiting.clear()
	business.waiting.clear()
	sim.elapsed = 11.0  # 18:00
	for i in 240:
		sim._spawn_passenger()
	h.check(business.waiting.size() > circle.waiting.size(),
		"晚高峰商务区产生更多乘客（%d vs %d）" % [business.waiting.size(), circle.waiting.size()])