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
	_test_interchange_pick(h)


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
	h.check(sim._week_timer > 0.0, "进入下一周计时")
	h.check(ids.size() == 2, "选择前有两张卡")


static func _test_apply_line(h: TestHarness) -> void:
	h.section("upgrades/line")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	var before := level.start_lines
	sim.apply_upgrade("line")
	h.eq(level.start_lines, before + 1, "新线路 +1")
	h.eq(net.available_lines(), level.start_lines - net.lines.size(), "可用线路数同步")


static func _test_apply_train(h: TestHarness) -> void:
	h.section("upgrades/train")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	h.eq(net.train_count(), 2, "两条线各一列车")
	var before_trains := level.start_trains
	sim.apply_upgrade("train")
	h.eq(level.start_trains, before_trains + 1, "列车资源 +1")
	_run(sim, 10)
	h.eq(net.train_count(), 3, "下一 tick 自动投放第三列车")


static func _test_apply_carriage(h: TestHarness) -> void:
	h.section("upgrades/carriage")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	sim.apply_upgrade("carriage")
	h.eq(net.total_carriages(), 1, "一节车厢")
	var expected := Simulation.TRAIN_BASE_CAPACITY + Simulation.CARRIAGE_CAPACITY
	var found := false
	for line in net.lines:
		if line.carriages <= 0:
			continue
		found = true
		for train in line.trains:
			h.eq(train.capacity, expected, "挂车厢的线路列车容量 +6")
	h.check(found, "车厢挂到了某条线路上")

	sim.apply_upgrade("carriage")
	h.eq(net.total_carriages(), 2, "第二节点到另一条线路")
	var capacities: Array[int] = []
	for line in net.lines:
		if line.carriages > 0 and not line.trains.is_empty():
			capacities.append(line.trains[0].capacity)
	h.check(capacities.size() == 2, "两条线路各有一节车厢")


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
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	var stations := net.stations
	stations[0].waiting.append(Passenger.new(Shape.Kind.SQUARE))
	stations[0].waiting.append(Passenger.new(Shape.Kind.SQUARE))
	stations[2].waiting.append(Passenger.new(Shape.Kind.CIRCLE))

	sim.apply_upgrade("interchange")
	h.eq(stations[0].capacity, 12, "最拥挤站点升级为换乘站")
	h.eq(stations[2].capacity, 6, "其他站容量不变")

	sim.apply_upgrade("interchange")
	var upgraded := 0
	for st in net.stations:
		if st.capacity > 6:
			upgraded += 1
	h.eq(upgraded, 2, "第二座换乘站落在下一个拥挤站")


## 换乘站卡：手动点选车站的完整流程（含无效点、重复升级、取消兜底）。
static func _test_interchange_pick(h: TestHarness) -> void:
	h.section("upgrades/interchange_pick")
	var level := _make_level()
	var net := _make_network(level)
	var sim := _make_sim(net, level)
	var stations := net.stations
	stations[0].waiting.append(Passenger.new(Shape.Kind.SQUARE))

	sim.week_pending = true
	sim.pending_cards.clear()
	sim.pending_cards.append(UpgradeCards.get_card("interchange"))
	sim.choose_upgrade(0)
	h.check(sim.interchange_pending, "选中换乘站卡后进入点选状态")
	h.check(sim.week_pending, "点选期间保持暂停")
	h.check(not sim.upgrade_station(9999), "不存在的站点不接受")
	h.check(sim.interchange_pending, "无效点选后仍等待")
	h.check(sim.upgrade_station(stations[2].id), "可以升级指定站点")
	h.eq(stations[2].capacity, 12, "指定站点容量变 12")
	h.check(not sim.interchange_pending, "完成点选后退出点选状态")
	h.check(not sim.week_pending, "完成点选后进入下一周")
	h.eq(sim.week_index, 2, "周数递增")

	# 已升级的站不能重复升级
	sim.pending_cards.append(UpgradeCards.get_card("interchange"))
	sim.week_pending = true
	sim.choose_upgrade(0)
	h.check(sim.interchange_pending, "第二次换乘站卡进入点选")
	h.check(not sim.upgrade_station(stations[2].id), "换乘站不能重复升级")

	# 取消点选：兜底升级最拥挤的容量 6 站点
	stations[1].waiting.append(Passenger.new(Shape.Kind.CIRCLE))
	stations[1].waiting.append(Passenger.new(Shape.Kind.CIRCLE))
	sim.cancel_interchange()
	h.eq(stations[1].capacity, 12, "取消时兜底升级最拥挤站")
	h.check(not sim.interchange_pending, "取消后退出点选")
	h.check(not sim.week_pending, "取消后恢复运行")