extends RefCounted
## 核心闭环：自动配车、上车、送达计分、换乘、站点溢出失败。

static func run(h: TestHarness) -> void:
	_test_delivery(h)
	_test_transfer(h)
	_test_overflow(h)
	_test_loop_opposite_board(h)
	_test_along_line_train_distance(h)


static func _make_level(train_count: int = 2) -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = train_count
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 5.0
	return level


static func _make_sim(net: MetroNetwork, level: LevelData) -> Simulation:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	return sim


static func _run(sim: Simulation, ticks: int) -> void:
	for i in ticks:
		sim.tick(Simulation.STEP)


static func _test_delivery(h: TestHarness) -> void:
	h.section("sim/delivery")
	var level := _make_level(1)
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 200), Shape.Kind.SQUARE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	net.touch()
	var sim := _make_sim(net, level)
	for i in 3:
		a.waiting.append(Passenger.new(Shape.Kind.SQUARE))

	_run(sim, 120)
	h.eq(net.train_count(), 1, "线路自动配 1 列车")
	h.eq(line.trains.size(), 1, "列车挂在线上")
	var train: Train = line.trains[0]
	h.eq(train.riders.size(), 3, "三名乘客全部上车")

	_run(sim, 720)
	h.eq(sim.delivered, 3, "三名乘客送达")
	h.eq(sim.score, 3, "得分等于送达数")
	h.eq(b.waiting.size(), 0, "目的地站没有滞留乘客")


static func _test_transfer(h: TestHarness) -> void:
	h.section("sim/transfer")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 200), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(800, 800), Shape.Kind.TRIANGLE)
	var l1 := net.create_line()
	l1.add_stop(a)
	l1.add_stop(b)
	var l2 := net.create_line()
	l2.add_stop(b)
	l2.add_stop(c)
	net.touch()
	var sim := _make_sim(net, level)
	a.waiting.append(Passenger.new(Shape.Kind.TRIANGLE))

	_run(sim, 480)
	h.eq(net.train_count(), 2, "两条线路各配一辆车")
	h.check(b.waiting.size() >= 1, "乘客在 B 站下车等待换乘")

	_run(sim, 900)
	h.eq(sim.delivered, 1, "换乘后送达三角站")
	h.eq(a.waiting.size(), 0, "起点站已清空")


static func _test_overflow(h: TestHarness) -> void:
	h.section("sim/overflow")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	net.add_station(Vector2(900, 300), Shape.Kind.SQUARE)
	# 没有线路：8 名乘客（容量 6）只会堆积
	for i in 8:
		a.waiting.append(Passenger.new(Shape.Kind.SQUARE))
	var sim := _make_sim(net, level)
	var over_ids := []
	sim.game_over.connect(func(st: Station) -> void: over_ids.append(st.id))

	_run(sim, 240)
	h.check(not sim.is_over, "宽限期内不判负")

	_run(sim, 180)
	h.check(sim.is_over, "超过宽限后判定游戏结束")
	h.eq(over_ids.size(), 1, "game_over 只发一次")
	h.check(over_ids.size() == 1 and int(over_ids[0]) == a.id, "失败站点是拥堵站")
	h.eq(net.train_count(), 0, "没有线路时不生成列车")


## 环线上首选方向的列车很远时，乘客会改坐反方向、但已经到站的车。
static func _test_loop_opposite_board(h: TestHarness) -> void:
	h.section("sim/loop_opposite_board")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 200), Shape.Kind.TRIANGLE)
	var c := net.add_station(Vector2(800, 800), Shape.Kind.PLUS)
	var d := net.add_station(Vector2(200, 800), Shape.Kind.SQUARE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	line.add_stop(d)
	line.is_loop = true
	line.rebuild()
	net.touch()
	var sim := _make_sim(net, level)
	var total := line.geometry.total_length
	var offsets := line.geometry.stop_offsets

	# 反方向列车已经停在 A；首选方向（经闭合段直去 D）的列车停在远处的 D
	var opposite := Train.new()
	opposite.id = 1
	opposite.line_id = line.id
	opposite.line_version = line.version
	opposite.dir = 1
	opposite.stop_index = 0
	opposite.target_index = 1
	opposite.dist = offsets[0]
	opposite.target_dist = offsets[1]
	opposite.state = Train.State.DWELL
	opposite.refresh_capacity()
	line.trains.append(opposite)
	var preferred := Train.new()
	preferred.id = 2
	preferred.line_id = line.id
	preferred.line_version = line.version
	preferred.dir = 1
	preferred.stop_index = 3
	preferred.target_index = 0
	preferred.dist = offsets[3]
	preferred.target_dist = total
	preferred.state = Train.State.MOVING
	preferred.refresh_capacity()
	line.trains.append(preferred)

	a.waiting.append(Passenger.new(Shape.Kind.SQUARE))
	sim.routing.rebuild(net)
	sim._begin_stop(opposite, line, a)
	h.eq(opposite.riders.size(), 1, "乘客坐上反方向但已到站的车")
	h.eq(a.waiting.size(), 0, "乘客不再死等首选方向")
	h.check(sim._passenger_should_board(opposite, line, a,
		Passenger.new(Shape.Kind.SQUARE), b.id), "综合评分允许反方向上车")


## 车到乘客的距离必须是线路弧长；L 形线路不能拿两点直线距离近似。
static func _test_along_line_train_distance(h: TestHarness) -> void:
	h.section("sim/along_line_distance")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(100, 100), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(700, 100), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(700, 700), Shape.Kind.TRIANGLE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	net.touch()
	var sim := _make_sim(net, level)
	var train := Train.new()
	train.line_id = line.id
	train.dir = 1
	train.dist = line.geometry.stop_offsets[0]
	train.stop_index = 0
	train.state = Train.State.MOVING
	var along := sim._train_distance_to_station(train, line, c)
	var straight := a.pos.distance_to(c.pos)
	h.near(along, line.geometry.stop_offsets[2], 0.1, "距离等于沿线弧长")
	h.check(along > straight + 100.0,
		"L 形线路的沿线距离明显大于直线距离（%.0f vs %.0f）" % [along, straight])
