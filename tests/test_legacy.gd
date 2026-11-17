extends RefCounted
## 手动编辑线路后的"旧线收尾"与车头朝向。

static func run(h: TestHarness) -> void:
	_test_place_train_facing(h)
	_test_legacy_line(h)
	_test_legacy_unchanged(h)


static func _make_level(trains: int = 2) -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = trains
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 9999.0
	return level


static func _make_line(level: LevelData) -> Array:
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(1200, 500), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(1200, 1000), Shape.Kind.TRIANGLE)
	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	net.touch()
	return [net, line, a, b, c]


static func _make_sim(net: MetroNetwork, level: LevelData) -> Simulation:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	return sim


## 把库存列车拖到线路上时，车头朝向距离最近的站台。
static func _test_place_train_facing(h: TestHarness) -> void:
	h.section("legacy/place_facing")
	var level := _make_level(2)
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	h.eq(sim.inventory_trains, 1, "自动配车后还剩一辆库存")
	h.check(sim.place_train(line, Vector2(300, 500)), "把库存车放到 A 站附近")
	var train: Train = line.trains[line.trains.size() - 1]
	h.eq(train.dir, -1, "最近站是 A（左侧），车头朝左")
	h.eq(train.target_index, 0, "目标站是 A")

	var level2 := _make_level(2)
	var made2 := _make_line(level2)
	var net2: MetroNetwork = made2[0]
	var line2: MetroLine = made2[1]
	var sim2 := _make_sim(net2, level2)
	sim2.tick(Simulation.STEP)
	h.check(sim2.place_train(line2, Vector2(1100, 500)), "把库存车放到 B 站附近")
	var train2: Train = line2.trains[line2.trains.size() - 1]
	h.eq(train2.dir, 1, "最近站是 B（右侧），车头朝右")
	h.eq(train2.target_index, 1, "目标站是 B")


## 手动编辑线路后：只有变化段上的列车沿旧几何行驶完；未变化段的车直接重映射。
static func _test_legacy_line(h: TestHarness) -> void:
	h.section("legacy/old_line")
	var level := _make_level(1)
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	# 加一个末端站，让"变化段"前后都有未变化的站
	line.add_stop(net.add_station(Vector2(1200, 1500), Shape.Kind.DIAMOND))
	net.touch()
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	var train: Train = line.trains[0]

	# 先跑一段，让车离开起点，落在 A-B 之间
	for i in 120:
		sim.tick(Simulation.STEP)
	h.check(train.dist > 0.0 and train.dist < line.geometry.stop_offsets[1],
		"列车位于 A-B 之间（变化段内）")

	# 删除中间站 B：变化段 = A..C，列车在变化段上
	var editor := LineEditor.new()
	editor.setup(net, level, null)
	editor._push_undo()
	line.remove_stop_at(1)
	net.touch()
	sim.tick(Simulation.STEP)
	h.check(train.legacy_active, "变化段上的列车切换到旧线收尾")
	h.check(train.legacy_geometry != null, "旧几何被保留")
	h.eq(train.legacy_stops.size(), 4, "旧站序是编辑前的四站")
	h.check(line.edit_legacy_valid, "线路记录了编辑前的几何")
	h.check(train.legacy_range_end > train.legacy_range_start, "记录了旧线变化区间")
	h.check(train.legacy_range_end - train.legacy_range_start < line.geometry.total_length,
		"浅色只覆盖变化段，不是整条线")

	var finished := false
	for i in 2400:
		sim.tick(Simulation.STEP)
		if not train.legacy_active:
			finished = true
			break
	h.check(finished, "列车跑完变化段后结束旧线状态")
	h.check(train.legacy_geometry == null, "结束后释放旧几何")
	h.eq(train.line_version, line.version, "列车切换回当前线路版本")
	editor.free()


## 列车在没变化的那一段上时，编辑后直接重映射，不做旧线收尾。
static func _test_legacy_unchanged(h: TestHarness) -> void:
	h.section("legacy/unchanged")
	var level := _make_level(1)
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	var train: Train = line.trains[0]
	for i in 60:
		sim.tick(Simulation.STEP)
	var editor := LineEditor.new()
	editor.setup(net, level, null)
	editor._push_undo()
	# 删掉最后一个站 C：变化段是 B..C，但列车还在 A 附近
	line.remove_stop_at(2)
	net.touch()
	sim.tick(Simulation.STEP)
	h.check(not train.legacy_active, "未变化段上的列车不做旧线收尾")
	h.eq(train.line_version, line.version, "直接切到新线版本")
	editor.free()