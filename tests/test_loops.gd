extends RefCounted
## 环线：几何闭合、换乘寻路走环、列车单向循环。

static func run(h: TestHarness) -> void:
	_test_geometry(h)
	_test_routing(h)
	_test_trains(h)


static func _level() -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = 0
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 9999.0
	return level


## 三站环线：A(300,300) - B(700,300) - C(500,700) - 回到 A
static func _make_loop(level: LevelData) -> Array:
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(700, 300), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(500, 700), Shape.Kind.TRIANGLE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	line.is_loop = true
	line.rebuild()
	net.touch()
	return [net, line, a, b, c]


static func _test_geometry(h: TestHarness) -> void:
	h.section("loop/geometry")
	var level := _level()
	var made := _make_loop(level)
	var line: MetroLine = made[1]
	var a: Station = made[2]
	var b: Station = made[3]
	var c: Station = made[4]

	h.check(line.geometry.is_drawable(), "环线几何可绘制")
	h.eq(line.geometry.stop_offsets.size(), 3, "三个站都有弧长位置")
	h.check(line.geometry.sample(line.geometry.total_length).origin.distance_to(a.pos) < 1.0,
		"环线终点回到起点")
	h.check(LineGeometry.is_octilinear(LineGeometry.octilinear_route([a, b, c], {}, true)),
		"闭合折线仍满足八向约束")

	var open := LineGeometry.new()
	open.build([a, b, c])
	h.check(line.geometry.total_length > open.total_length + 50.0,
		"环线比开放折线多出回到起点的一段（%.1f vs %.1f）"
		% [line.geometry.total_length, open.total_length])


static func _test_routing(h: TestHarness) -> void:
	h.section("loop/routing")
	var level := _level()
	var made := _make_loop(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var a: Station = made[2]
	var c: Station = made[4]
	var routing := Routing.new()
	routing.rebuild(net)
	var step := routing.next_for(a.id, Shape.Kind.TRIANGLE)
	h.eq(int(step.get("line", -1)), line.id, "环线上车线路正确")
	h.eq(int(step.get("station", -1)), c.id, "环线可以走闭合段直达 C（而不是绕经 B）")


static func _test_trains(h: TestHarness) -> void:
	h.section("loop/trains")
	var level := _level()
	level.start_trains = 1
	var made := _make_loop(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	sim.tick(Simulation.STEP)
	h.eq(line.trains.size(), 1, "环线自动配一列车")
	var train: Train = line.trains[0]
	var visited := {}
	var dir_ok := true
	for i in 1200:
		sim.tick(Simulation.STEP)
		visited[train.stop_index] = true
		if train.dir != 1:
			dir_ok = false
			break
	h.check(dir_ok, "环线列车方向始终为 +1（不掉头）")
	h.eq(visited.size(), 3, "列车跑遍环线三站")
	h.check(train.dist >= 0.0 and train.dist <= line.geometry.total_length + 0.01,
		"列车位置始终在环线范围内")
	h.check(not sim.is_over, "环线运行不会触发失败")