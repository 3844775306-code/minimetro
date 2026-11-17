extends RefCounted
## M6：模式键/种子、无尽模式不判负、每日种子稳定。

static func run(h: TestHarness) -> void:
	_test_keys_and_seeds(h)
	_test_endless(h)
	_test_manager(h)
	_test_throughput(h)


static func _test_keys_and_seeds(h: TestHarness) -> void:
	h.section("modes/keys")
	h.eq(GameMode.key(GameMode.Kind.CLASSIC), "classic", "经典 key")
	h.eq(GameMode.key(GameMode.Kind.ENDLESS), "endless", "无尽 key")
	h.eq(GameMode.key(GameMode.Kind.DAILY), "daily", "每日 key")
	h.eq(GameMode.from_key("endless"), GameMode.Kind.ENDLESS, "key 反解")
	h.eq(GameMode.from_key("nope"), GameMode.Kind.CLASSIC, "未知 key 回退经典")
	h.eq(GameMode.key(GameMode.Kind.MANAGER), "manager", "管理 key")

	var same_a := GameMode.daily_seed("2026-11-17")
	var same_b := GameMode.daily_seed("2026-11-17")
	var other := GameMode.daily_seed("2026-11-18")
	h.eq(same_a, same_b, "同一天种子稳定")
	h.check(same_a != other, "不同日期种子不同")
	h.check(same_a >= 0, "种子非负")


static func _test_endless(h: TestHarness) -> void:
	h.section("modes/endless")
	var level := LevelData.new()
	level.endless = true
	level.start_trains = 0
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 5.0
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	for i in 8:
		a.waiting.append(Passenger.new(Shape.Kind.SQUARE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	for i in 600:
		sim.tick(Simulation.STEP)
	h.check(not sim.is_over, "无尽模式不会判负")
	h.check(a.overload_timer > 0.0, "超载计时仍在累积")
	h.near(a.overload_timer, level.overload_grace, 0.5, "计时顶在宽限值")

	# 对照：同样条件经典模式会结束
	var classic := LevelData.new()
	classic.start_trains = 0
	classic.station_spawn_interval = 99999.0
	classic.passenger_spawn_start = 99999.0
	classic.passenger_spawn_end = 99999.0
	classic.overload_grace = 5.0
	var net2 := MetroNetwork.new(classic)
	var b := net2.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	for i in 8:
		b.waiting.append(Passenger.new(Shape.Kind.SQUARE))
	var sim2 := Simulation.new(net2, classic, rng)
	sim2.auto_spawn = false
	for i in 600:
		sim2.tick(Simulation.STEP)
	h.check(sim2.is_over, "经典模式同样条件会判负")


static func _test_manager(h: TestHarness) -> void:
	h.section("modes/manager")
	var level := LevelData.new()
	level.manager_mode = true
	level.no_station_spawn = true
	level.station_margin = 150.0
	level.station_spawn_interval = 1.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 9999.0
	var net := MetroNetwork.new(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var spawner := StationSpawner.new(level, rng)
	spawner.spawn_manager_layout(net, 40, level.station_shape_weights)
	h.eq(net.stations.size(), 40, "管理模式开局 40 座车站")
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = true
	for i in 120:
		sim.tick(Simulation.STEP)
	h.eq(net.stations.size(), 40, "管理模式不再生成新车站")
	h.near(sim.camera_zoom_target(), 1.0, 0.001, "管理模式相机固定 1x")


static func _test_throughput(h: TestHarness) -> void:
	h.section("modes/throughput")
	var level := LevelData.new()
	var net := MetroNetwork.new(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var sim := Simulation.new(net, level, rng)
	h.near(sim.recent_throughput_per_30s(), 0.0, 0.001, "没有送达时指标为 0")
	sim.elapsed = 40.0
	sim._delivery_times = [0.0, 10.0, 20.0, 40.0]
	h.near(sim.recent_throughput_per_30s(), 3.0, 0.001,
		"最近 30 秒内 3 人送达 = 平均每 30 秒 3 人")

	# 每 30 秒客运量达到 10 的里程碑时，给一次升级而不是等周结算
	var endless_level := LevelData.new()
	endless_level.endless = true
	endless_level.start_lines = 3
	endless_level.start_bridges = 2
	var endless_net := MetroNetwork.new(endless_level)
	var endless_sim := Simulation.new(endless_net, endless_level, rng)
	endless_sim.elapsed = 30.0
	for i in 12:
		endless_sim._delivery_times.append(10.0)
	endless_sim._update_endless_milestones()
	h.check(endless_sim.week_pending, "达到客运量里程碑会弹出升级选择")
	h.near(endless_sim.endless_next_milestone, 20.0, 0.001, "里程碑推进到下一档 20")
	h.check(endless_sim.pending_reward_title.contains("30"),
		"里程碑弹窗标题使用每 30 秒客运量")
	h.near(endless_sim.endless_best_per_30s, 12.0, 0.001, "记录本局最高 30 秒客运量")