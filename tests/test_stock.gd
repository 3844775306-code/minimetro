extends RefCounted
## 库存资源：新线自动配车（只在有新线且有余车时）、手动拖放列车/车厢/换乘中心。

static func run(h: TestHarness) -> void:
	_test_auto_assign(h)
	_test_place_train(h)
	_test_place_carriage(h)
	_test_place_interchange(h)


static func _level(trains: int = 3, carriages: int = 0, interchanges: int = 0) -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = trains
	level.start_carriages = carriages
	level.start_interchanges = interchanges
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 9999.0
	return level


static func _make_net(level: LevelData) -> Array:
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 200), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(800, 700), Shape.Kind.TRIANGLE)
	var d := net.add_station(Vector2(200, 700), Shape.Kind.DIAMOND)
	var l1 := net.create_line()
	l1.add_stop(a)
	l1.add_stop(b)
	var l2 := net.create_line()
	l2.add_stop(c)
	l2.add_stop(d)
	net.touch()
	return [net, l1, l2, a, b, c, d]


static func _make_sim(net: MetroNetwork, level: LevelData) -> Simulation:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	return sim


static func _test_auto_assign(h: TestHarness) -> void:
	h.section("stock/auto_assign")
	var level := _level(2)
	var made := _make_net(level)
	var net: MetroNetwork = made[0]
	var l3: MetroLine = null
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	h.eq(net.train_count(), 2, "两条新线各自动配一列车")
	h.eq(sim.inventory_trains, 0, "自动配车扣掉库存")
	# 没有库存时再开新线，不会自动配车
	l3 = net.create_line()
	l3.add_stop(made[3])
	l3.add_stop(made[5])
	net.touch()
	for i in 30:
		sim.tick(Simulation.STEP)
	h.eq(l3.trains.size(), 0, "没库存时新线不自动配车")
	h.eq(sim.inventory_trains, 0, "库存保持为 0")


static func _test_place_train(h: TestHarness) -> void:
	h.section("stock/place_train")
	var level := _level(3)
	var made := _make_net(level)
	var net: MetroNetwork = made[0]
	var l1: MetroLine = made[1]
	var l2: MetroLine = made[2]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	h.eq(sim.inventory_trains, 1, "两条新线用掉两辆，还剩一辆")
	var pos := Vector2(500.0, 200.0)
	h.check(sim.place_train(l1, pos), "把库存列车拖到线路上")
	h.eq(l1.trains.size(), 2, "线路上多了一列车")
	h.eq(sim.inventory_trains, 0, "库存扣 1")
	var train: Train = l1.trains[l1.trains.size() - 1]
	h.check(absf(train.dist - l1.geometry.nearest_distance(pos)) < 1.0,
		"列车落在任意拖动位置（不是只能从起点站出发）")
	h.eq(train.state, Train.State.MOVING, "拖动落位后开始行驶")
	h.check(not sim.place_train(l2, pos), "没有库存时不能再放")


static func _test_place_carriage(h: TestHarness) -> void:
	h.section("stock/place_carriage")
	var level := _level(2, 1)
	var made := _make_net(level)
	var net: MetroNetwork = made[0]
	var l1: MetroLine = made[1]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	var train: Train = l1.trains[0]
	var pos := l1.geometry.sample(train.dist).origin
	h.check(sim.place_carriage(pos), "把库存车厢拖到列车上")
	h.eq(train.carriages, 1, "列车挂上一节车厢")
	h.eq(train.capacity, Train.BASE_CAPACITY + Train.CARRIAGE_CAPACITY, "容量 +6")
	h.eq(sim.inventory_carriages, 0, "库存扣 1")
	h.check(not sim.place_carriage(pos), "没有库存时不能再挂")


static func _test_place_interchange(h: TestHarness) -> void:
	h.section("stock/place_interchange")
	var level := _level(2, 0, 1)
	var made := _make_net(level)
	var net: MetroNetwork = made[0]
	var a: Station = made[3]
	var b: Station = made[4]
	var sim := _make_sim(net, level)
	h.check(sim.place_interchange(a), "把库存换乘中心拖到车站")
	h.eq(a.capacity, 12, "目标站容量 6 → 12")
	h.eq(sim.inventory_interchanges, 0, "库存扣 1")
	h.check(not sim.place_interchange(b), "没有库存时不能再放")
	sim.inventory_interchanges = 1
	h.check(not sim.place_interchange(a), "已升级的站不能重复放")
	h.eq(sim.inventory_interchanges, 1, "失败的放置不扣库存")