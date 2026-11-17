extends RefCounted
## 列车运动学与"近线未接入"标记：
## 加速度/刹车不突变、无人上下车直接驶过、停站时间 = 0.5s × 上下车人数、弯道按角度减速。

static func run(h: TestHarness) -> void:
	_test_acceleration(h)
	_test_pass_through(h)
	_test_dwell_proportional(h)
	_test_curve_limit(h)
	_test_near_line_marker(h)


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
	h.eq(train.riders.size(), 3, "三名乘客上车")
	h.near(train.dwell_left, 3.0 * Train.DWELL_PER_PASSENGER, 0.05,
		"停站时间 = 0.5s × 上车人数")
	# 开到 B（终点）后三人下车，停站时间同样是 0.5s × 下车人数
	for i in 600:
		sim.tick(Simulation.STEP)
		if sim.delivered >= 3:
			break
	h.eq(sim.delivered, 3, "三人送达")
	h.near(train.dwell_left, 3.0 * Train.DWELL_PER_PASSENGER, 0.05,
		"到站停站时间 = 0.5s × 下车人数")


static func _test_curve_limit(h: TestHarness) -> void:
	h.section("motion/curve")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 500), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(800, 1000), Shape.Kind.TRIANGLE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	net.touch()
	var factors: Array[float] = []
	for entry in line.geometry.curve_entries:
		factors.append(float(entry.y))
	h.check(not factors.is_empty(), "90° 折角产生弯道限速点")
	var tightest := 1.0
	for factor in factors:
		tightest = minf(tightest, factor)
	h.check(tightest < 0.5, "90° 弯道限速低于最高速一半（%.2f）" % tightest)
	h.check(tightest >= 0.3, "限速不会低到 0")
	var ahead := line.geometry.curve_entries_ahead(0.0, 1, 2000.0)
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
	# 靠近线路但不在线上
	var near := net.add_station(Vector2(700, 550), Shape.Kind.TRIANGLE)
	# 已经接上的站
	var on := net.add_station(Vector2(950, 500), Shape.Kind.DIAMOND)
	line.add_stop(on)
	net.touch()

	var markers := NearLineMarkerLayer.collect_markers(net)
	h.check(not markers.is_empty(), "存在靠线未接入的站台标记")
	var found := false
	for marker in markers:
		if marker["station"] == near:
			found = true
			h.check(float(marker["distance"]) <= NearLineMarkerLayer.NEAR_DISTANCE,
				"标记距离在阈值内")
	h.check(found, "近线站台有待接入标记")
	var false_positive := false
	for marker in markers:
		if marker["station"] == on:
			false_positive = true
	h.check(not false_positive, "已在线上的站台不会被标记为未接入")