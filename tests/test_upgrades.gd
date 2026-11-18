extends RefCounted
## M3 周循环：每周暂停抽卡、资源上限过滤、线路/列车/车厢升级生效。

static func run(h: TestHarness) -> void:
	_test_week_trigger(h)
	_test_choose_card(h)
	_test_apply_line(h)
	_test_apply_train(h)
	_test_apply_carriage(h)
	_test_apply_bridge(h)
	_test_apply_interchange(h)
	_test_early_line_weight(h)


static func _make_level(week_seconds: float = 999.0) -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = 2
	level.max_lines = 7
	level.max_trains = 6
	level.max_carriages = 3
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 9999.0
	level.week_seconds = week_seconds
	return level


static func _make_network(level: LevelData) -> MetroNetwork:
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(800, 200), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(800, 700), Shape.Kind.TRIANGLE)
	var l1 := net.create_line()
	l1.add_stop(a)
	l1.add_stop(b)
	var l2 := net.create_line()
	l2.add_stop(b)
	l2.add_stop(c)
	net.touch()
	return net


static func _make_sim(net: MetroNetwork, level: LevelData) -> Simulation:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	return sim


static func _run(sim: Simulation, ticks: int) -> void:
	for i in ticks:
		sim.tick(Simulation.STEP)


static func _test_week_trigger(h: TestHarness) -> void:
	h.section("upgrades/week")
	var level := _make_level(1.0)
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	var events: Array = []
	sim.week_completed.connect(func(cards: Array, week: int) -> void: events.append([cards, week]))

	_run(sim, 90)
	h.eq(events.size(), 1, "1 秒后触发一次周结算")
	h.check(sim.week_pending, "周结算时暂停模拟")
	h.eq(sim.week_index, 1, "第一次结算是第 1 周")
	if events.size() == 1:
		var cards: Array = events[0][0]
		h.eq(cards.size(), 2, "默认给两张卡")
		h.check(String(cards[0]["id"]) != String(cards[1]["id"]), "两张卡互不相同")
		h.check(String(cards[0]["title"]) != "", "卡片有标题")

	var elapsed_before := sim.elapsed
	sim.tick(Simulation.STEP)
	sim.advance(2.0)
	h.check(is_equal_approx(sim.elapsed, elapsed_before), "等待选择时不推进模拟")


static func _test_choose_card(h: TestHarness) -> void:
	h.section("upgrades/choose")
	var level := _make_level(1.0)
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	_run(sim, 90)
	h.check(sim.week_pending, "先进入周结算")
	var ids: Array[String] = []
	for card in sim.pending_cards:
		ids.append(String(card["id"]))
	sim.choose_upgrade(0)
	h.check(not sim.week_pending, "选择后恢复模拟")
	h.eq(sim.week_index, 2, "周数递增")
	h.eq(sim.pending_cards.size(), 0, "卡池清空")
	h.check(sim._week_end_hour > sim.elapsed, "下一次结算在未来")
	h.check(ids.size() == 2, "选择前有两张卡")


static func _test_apply_line(h: TestHarness) -> void:
	h.section("upgrades/line")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	var before := level.start_lines
	var trains_before := sim.inventory_trains
	sim.apply_upgrade("line")
	h.eq(level.start_lines, before + 1, "新线路 +1")
	h.eq(sim.inventory_trains, trains_before + 1, "线路奖励附赠 1 列车")
	h.eq(net.available_lines(), level.start_lines - net.lines.size(), "可用线路数同步")


static func _test_early_line_weight(h: TestHarness) -> void:
	h.section("upgrades/early_line_weight")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	sim.week_index = 1
	var early := sim.line_reward_weight()
	sim.week_index = 5
	var late := sim.line_reward_weight()
	h.check(early > late, "前几周线路奖励权重更高")
	h.check(early > 4.0, "第 1 周线路奖励权重明显高于其他奖励")


static func _test_apply_train(h: TestHarness) -> void:
	h.section("upgrades/train")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	h.eq(net.train_count(), 2, "两条新线各自动配一列车")
	h.eq(sim.inventory_trains, 0, "初始列车库存被新线用光")
	sim.apply_upgrade("train")
	h.eq(sim.inventory_trains, 1, "列车资源进入库存 +1")
	h.eq(net.train_count(), 2, "没有新线时不会自动投放")
	var pos := Vector2(500.0, 200.0)
	h.check(sim.place_train(net.lines[0], pos), "手动拖放库存列车")
	h.eq(net.train_count(), 3, "拖放后上线第三列车")
	h.eq(sim.inventory_trains, 0, "库存相应减少")


static func _test_apply_carriage(h: TestHarness) -> void:
	h.section("upgrades/carriage")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	sim.apply_upgrade("carriage")
	h.eq(sim.inventory_carriages, 1, "车厢进入库存")
	h.eq(net.total_carriages(), 0, "未拖放前不在线路上")
	var train: Train = net.lines[0].trains[0]
	var pos := net.lines[0].geometry.sample(train.dist).origin
	h.check(sim.place_carriage(pos), "拖到列车上挂载成功")
	h.eq(train.carriages, 1, "列车挂上一节车厢")
	h.eq(train.capacity, Train.BASE_CAPACITY + Train.CARRIAGE_CAPACITY, "容量 +6")
	h.eq(net.total_carriages(), 1, "全网一节车厢")


static func _test_apply_bridge(h: TestHarness) -> void:
	h.section("upgrades/bridge")
	var level := _make_level()
	level.start_bridges = 2
	level.max_bridges = 6
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	sim.apply_upgrade("bridge")
	h.eq(level.start_bridges, 3, "桥隧额度 +1")
	h.eq(net.available_bridges(), 3, "可用额度同步")


static func _test_apply_interchange(h: TestHarness) -> void:
	h.section("upgrades/interchange")
	var level := _make_level()
	level.start_interchanges = 0
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	var stations := net.stations
	sim.apply_upgrade("interchange")
	h.eq(sim.inventory_interchanges, 1, "换乘中心进入库存")
	h.eq(stations[0].capacity, 6, "未拖放前容量不变")
	h.check(sim.place_interchange(stations[0]), "拖到车站上升级成功")
	h.eq(stations[0].capacity, 12, "目标站容量 6 → 12")
	h.eq(sim.inventory_interchanges, 0, "库存扣减")
	h.check(not sim.place_interchange(stations[1]), "没有库存时不能再放")

	sim.apply_upgrade("interchange")
	h.check(not sim.place_interchange(stations[0]), "已升级的站不能重复放")
	h.eq(sim.inventory_interchanges, 1, "失败的放置不扣库存")
	h.check(sim.place_interchange(stations[1]), "可以放到另一座站")
	h.eq(stations[1].capacity, 12, "第二座换乘站生效")