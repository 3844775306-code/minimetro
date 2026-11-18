extends RefCounted
## 列车运动学与"近线未接入"标记：
## 加速度/刹车不突变、无人上下车直接驶过、停站时间 = 0.5s × 上下车人数、弯道按角度减速。

static func run(h: TestHarness) -> void:
	_test_scale(h)
	_test_acceleration(h)
	_test_pass_through(h)
	_test_dwell_proportional(h)
	_test_curve_limit(h)
	_test_near_line_marker(h)
	_test_carriage_follows_line(h)


## 车站尺寸与列车速度整体下调 40%（本轮手感调整）。
static func _test_scale(h: TestHarness) -> void:
	h.section("motion/scale")
	h.near(Shape.STATION_RADIUS, 15.6, 0.01, "车站半径缩小 40%")
	h.near(Train.MAX_SPEED, 126.0, 0.01, "最高速度降低 40%")
	h.near(Train.ACCEL, 90.0, 0.01, "加速度同比降低 40%")
	h.near(Train.DECEL, 144.0, 0.01, "减速度同比降低 40%")


static func _make_level(trains: int = 1, interchanges: int = 0) -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = trains
	level.start_interchanges = interchanges
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 9999.0
	return level


## 直线上 3 站：A(200,500) - B(800,500) - C(1400,500)
static func _make_line(level: LevelData) -> Array:
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 500), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(1400, 500), Shape.Kind.TRIANGLE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	net.touch()
	return [net, line, a, b, c]


static func _make_sim(net: MetroNetwork, level: LevelData) -> Simulation:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	return sim


static func _test_acceleration(h: TestHarness) -> void:
	h.section("motion/accel")
	var level := _make_level()
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	h.eq(line.trains.size(), 1, "新线自动配一列车")
	var train: Train = line.trains[0]
	var previous_speed := train.speed
	var max_jump := 0.0
	var max_speed_seen := 0.0
	for i in 120:
		sim.tick(Simulation.STEP)
		max_jump = maxf(max_jump, absf(train.speed - previous_speed))
		previous_speed = train.speed
		max_speed_seen = maxf(max_speed_seen, train.speed)
	h.check(max_jump <= Train.ACCEL * Simulation.STEP + 0.01,
		"每帧速度变化不超过加速度上限（%.3f）" % max_jump)
	h.check(max_speed_seen <= Train.MAX_SPEED + 0.01, "速度不超过最高速")
	h.check(max_speed_seen > 60.0, "列车确实加速起来了")


static func _test_pass_through(h: TestHarness) -> void:
	h.section("motion/pass_through")
	var level := _make_level()
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	var train: Train = line.trains[0]
	var stopped_at_middle := false
	for i in 600:
		sim.tick(Simulation.STEP)
		if train.state == Train.State.DWELL and train.stop_index == 1:
			stopped_at_middle = true
	h.check(not stopped_at_middle, "无人上下车时列车直接驶过中间站")
	h.check(sim.delivered == 0, "没有人需要送达")


static func _test_dwell_proportional(h: TestHarness) -> void:
	h.section("motion/dwell")
	var level := _make_level()
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var b: Station = made[3]
	for i in 3:
		made[2].waiting.append(Passenger.new(Shape.Kind.SQUARE))  # 目的地形状 = B 站
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	var train: Train = line.trains[0]
	# 逐个上车：每 0.5s 一名，不再一帧上完
	h.eq(train.riders.size(), 1, "第 1 名立即上车")
	h.near(train.dwell_left, 3.0 * Train.DWELL_PER_PASSENGER, 0.06,
		"总停站时间仍 = 0.5s × 人数")
	for i in 15:
		sim.tick(Simulation.STEP)
	h.eq(train.riders.size(), 1, "0.25s 时仍只有 1 名上车")
	for i in 15:
		sim.tick(Simulation.STEP)
	h.eq(train.riders.size(), 2, "0.5s 时第 2 名上车")
	for i in 30:
		sim.tick(Simulation.STEP)
	h.eq(train.riders.size(), 3, "1.0s 时第 3 名上车")
	# 开到 B（终点）后三人逐个下车并送达
	for i in 900:
		sim.tick(Simulation.STEP)
		if sim.delivered >= 3:
			break
	h.eq(sim.delivered, 3, "三人送达")
	h.eq(train.riders.size(), 0, "送达后车内清空")


static func _test_curve_limit(h: TestHarness) -> void:
	h.section("motion/curve")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 500), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(800, 1000), Shape.Kind.TRIANGLE)
	var line90 := net.create_line()
	line90.add_stop(a)
	line90.add_stop(b)
	line90.add_stop(c)
	# 45° 弯：水平段后接一条 45° 斜线
	var d := net.add_station(Vector2(300, 250), Shape.Kind.DIAMOND)
	var e := net.add_station(Vector2(700, 250), Shape.Kind.STAR)
	var f := net.add_station(Vector2(1100, 650), Shape.Kind.CIRCLE)
	var line45 := net.create_line()
	line45.add_stop(d)
	line45.add_stop(e)
	line45.add_stop(f)
	net.touch()

	var factor90 := 1.0
	for entry in line90.geometry.curve_entries:
		factor90 = minf(factor90, float(entry.y))
	var factor45 := 1.0
	for entry in line45.geometry.curve_entries:
		factor45 = minf(factor45, float(entry.y))
	# 135° 弯：先向东，再拐向西南
	var g := net.add_station(Vector2(300, 800), Shape.Kind.CIRCLE)
	var h_station := net.add_station(Vector2(700, 800), Shape.Kind.SQUARE)
	var i_station := net.add_station(Vector2(300, 400), Shape.Kind.TRIANGLE)
	var line135 := net.create_line()
	line135.add_stop(g)
	line135.add_stop(h_station)
	line135.add_stop(i_station)
	net.touch()
	var factor135 := 1.0
	for entry in line135.geometry.curve_entries:
		factor135 = minf(factor135, float(entry.y))
	# 180° 掉头：向东后直接折返向西
	var j := net.add_station(Vector2(300, 1000), Shape.Kind.CIRCLE)
	var k := net.add_station(Vector2(700, 1000), Shape.Kind.SQUARE)
	var l := net.add_station(Vector2(400, 1000), Shape.Kind.TRIANGLE)
	var line180 := net.create_line()
	line180.add_stop(j)
	line180.add_stop(k)
	line180.add_stop(l)
	net.touch()
	var factor180 := 1.0
	for entry in line180.geometry.curve_entries:
		factor180 = minf(factor180, float(entry.y))
	h.near(factor45, 0.9, 0.001, "45° 缓弯限速 0.9")
	h.near(factor90, 0.7, 0.001, "90° 直角弯限速 0.7")
	h.near(factor135, 0.5, 0.001, "135° 急弯限速 0.5")
	h.near(factor180, 0.3, 0.001, "180° 掉头限速 0.3")
	h.check(factor45 > factor90 and factor90 > factor135 and factor135 > factor180,
		"转弯越急限速越低：45° > 90° > 135° > 180°")
	var ahead := line90.geometry.curve_entries_ahead(0.0, 1, 2000.0)
	h.check(not ahead.is_empty(), "弯道限速点能被前方查询找到")


static func _test_near_line_marker(h: TestHarness) -> void:
	h.section("motion/near_line")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(1200, 500), Shape.Kind.SQUARE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	# 太远：不再算"近线未接入"
	var far := net.add_station(Vector2(700, 570), Shape.Kind.TRIANGLE)
	# 很近但不在线上
	var near := net.add_station(Vector2(700, 512), Shape.Kind.STAR)
	# 已经接上的站
	var on := net.add_station(Vector2(950, 500), Shape.Kind.DIAMOND)
	line.add_stop(on)
	net.touch()

	var markers := NearLineMarkerLayer.collect_markers(net)
	var found_near := false
	var found_far := false
	var found_on := false
	for marker in markers:
		if marker["station"] == near:
			found_near = true
			h.check(float(marker["distance"]) <= NearLineMarkerLayer.NEAR_DISTANCE,
				"标记距离在 20px 阈值内")
		if marker["station"] == far:
			found_far = true
		if marker["station"] == on:
			found_on = true
	h.check(found_near, "20px 内的近线站台有标记")
	h.check(not found_far, "超过 20px 的站台不再标记")
	h.check(not found_on, "已在线上的站台不会被标记为未接入")


## 车厢必须沿线路弧长采样：车头刚过弯时，车厢应还在上一段直线上，而不是沿车头切线飘出去。
static func _test_carriage_follows_line(h: TestHarness) -> void:
	h.section("motion/carriage_follows_line")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(100, 100), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(500, 100), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(500, 500), Shape.Kind.TRIANGLE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	net.touch()
	var train := Train.new()
	train.line_id = line.id
	train.line_version = line.version
	train.dir = 1
	train.dist = line.geometry.stop_offsets[1] + 30.0
	train.stop_index = 1
	train.target_index = 2
	train.state = Train.State.MOVING
	var expected_distance := train.dist - TrainView.CARRIAGE_FIRST_OFFSET
	var expected := line.geometry.sample(expected_distance).origin
	var actual := TrainView.carriage_transform(train, line, 0).origin
	h.near(actual.distance_to(expected), 0.0, 0.5,
		"车厢按弧长挂在车尾（转弯时跟随上一段线路）")
	var straight_behind := line.geometry.sample(train.dist).origin - Vector2(0.0, TrainView.CARRIAGE_FIRST_OFFSET)
	h.check(actual.distance_to(straight_behind) > 20.0,
		"车厢不会沿车头切线飘到线路外")