extends RefCounted
## 手动编辑线路后的"旧线收尾"与车头朝向。

static func run(h: TestHarness) -> void:
	_test_place_train_facing(h)
	_test_legacy_line(h)
	_test_legacy_unchanged(h)
	_test_legacy_remove_endpoint(h)
	_test_legacy_remove_middle(h)
	_test_legacy_dwell_remove(h)
	_test_legacy_flip(h)


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

	# 视图必须用旧几何采样；否则模型还在旧线上，画面会跳到新线
	var view := TrainView.new()
	view.update_from(train, line)
	var old_pos := train.legacy_geometry.sample(train.dist).origin
	var new_pos := line.geometry.sample(train.dist).origin
	h.near(view.position.distance_to(old_pos), 0.0, 0.1, "旧线收尾时列车视图使用旧几何")
	h.check(old_pos.distance_to(new_pos) > 5.0, "测试场景新旧几何位置确实不同")
	view.free()

	var start_dist := train.dist
	var farthest_legacy := start_dist
	var finished := false
	for i in 2400:
		sim.tick(Simulation.STEP)
		if train.legacy_active:
			farthest_legacy = maxf(farthest_legacy, train.dist)
		if not train.legacy_active:
			finished = true
			break
	h.check(finished, "列车跑完变化段后结束旧线状态")
	h.check(farthest_legacy - start_dist > 50.0,
		"列车确实沿旧线开了一段（不是瞬间跳到新线）")
	h.check(train.legacy_geometry == null, "结束后释放旧几何")
	h.eq(train.line_version, line.version, "列车切换回当前线路版本")
	editor.free()


## 只改弯曲方向（站序不变）也算"不一样的部分"：该段上的车要沿旧线收尾。
## 删除首/末站时，正在“被删站—相邻站”这一段上的列车也必须沿旧线收尾，
## 而不是瞬移到相邻站。这里覆盖靠近相邻站的边界位置。
static func _test_legacy_remove_endpoint(h: TestHarness) -> void:
	h.section("legacy/remove_endpoint")
	for at_start in [true, false]:
		for ratio in [0.25, 0.9]:
			var level := _make_level(1)
			var made := _make_line(level)
			var net: MetroNetwork = made[0]
			var line: MetroLine = made[1]
			var sim := _make_sim(net, level)
			sim.tick(Simulation.STEP)
			var train: Train = line.trains[0]
			var seg_index := 0 if at_start else 1
			var seg_start := line.geometry.stop_offsets[seg_index]
			var seg_end := line.geometry.stop_offsets[seg_index + 1]
			train.legacy_active = false
			train.dist = lerpf(seg_start, seg_end, ratio)
			train.stop_index = seg_index
			train.target_index = seg_index + 1
			train.target_dist = seg_end
			train.state = Train.State.MOVING
			train.line_version = line.version
			var old_dist := train.dist
			var editor := LineEditor.new()
			editor.setup(net, level, null)
			editor._push_undo()
			line.remove_stop_at(0 if at_start else line.stops.size() - 1)
			net.touch()
			sim.tick(Simulation.STEP)
			h.check(train.legacy_active,
				"删%s端站、列车在变化段 %.0f%% 处时进入旧线收尾" % [
					"首" if at_start else "末", ratio * 100.0])
			h.near(train.dist, old_dist, 0.1, "进入旧线收尾时列车位置不跳")
			var finished := false
			for i in 2400:
				sim.tick(Simulation.STEP)
				if not train.legacy_active:
					finished = true
					break
			h.check(finished, "旧线收尾能结束")
			h.check(train.line_version == line.version, "收尾后切回当前线路")
			editor.free()


## 删除中间站时，列车在它的任一侧变化段上都沿旧线收尾。
static func _test_legacy_remove_middle(h: TestHarness) -> void:
	h.section("legacy/remove_middle")
	var level := _make_level(1)
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	var train: Train = line.trains[0]
	for i in 30:
		sim.tick(Simulation.STEP)
	var old_dist := train.dist
	var editor := LineEditor.new()
	editor.setup(net, level, null)
	editor._push_undo()
	line.remove_stop_at(1)
	net.touch()
	sim.tick(Simulation.STEP)
	h.check(train.legacy_active, "列车在 B 左侧变化段时进入旧线收尾")
	h.near(train.dist, old_dist, 0.1, "旧线收尾位置不跳")
	editor.free()

	# 列车恰好停在将被删除的 B 站上：也不能直接重映射到相邻站
	var level2 := _make_level(1)
	var made2 := _make_line(level2)
	var net2: MetroNetwork = made2[0]
	var line2: MetroLine = made2[1]
	var sim2 := _make_sim(net2, level2)
	sim2.tick(Simulation.STEP)
	var train2: Train = line2.trains[0]
	train2.dist = line2.geometry.stop_offsets[1]
	train2.stop_index = 1
	train2.target_index = 2
	train2.target_dist = line2.geometry.stop_offsets[2]
	train2.state = Train.State.DWELL
	train2.line_version = line2.version
	var at_b := train2.dist
	var editor2 := LineEditor.new()
	editor2.setup(net2, level2, null)
	editor2._push_undo()
	line2.remove_stop_at(1)
	net2.touch()
	sim2.tick(Simulation.STEP)
	h.check(train2.legacy_active, "列车停在被删站 B 上时进入旧线收尾")
	h.near(train2.dist, at_b, 0.1, "停在被删站时也不瞬移")
	editor2.free()


## 真正走 LineEditor 的“停留移站”路径，确认删除瞬间不会把列车重映射。
static func _test_legacy_dwell_remove(h: TestHarness) -> void:
	h.section("legacy/dwell_remove")
	var level := _make_level(1)
	var made := _make_line(level)
	var net: MetroNetwork = made[0]
	var line: MetroLine = made[1]
	var sim := _make_sim(net, level)
	sim.tick(Simulation.STEP)
	var train: Train = line.trains[0]
	for i in 30:
		sim.tick(Simulation.STEP)
	var old_dist := train.dist
	var editor := LineEditor.new()
	editor.setup(net, level, null)
	editor.begin_gesture(line.geometry.handle_position(false))
	h.eq(editor.state, LineEditor.State.DRAFT, "从末端手柄进入延长状态")
	editor._dwell_station = line.stops[1]
	editor._remove_dwelled_station()
	net.touch()
	sim.tick(Simulation.STEP)
	h.eq(line.stops.size(), 2, "停留移站后只剩两站")
	h.check(train.legacy_active, "停留移站的同一帧就进入旧线收尾")
	h.near(train.dist, old_dist, 0.1, "停留移站不会瞬移列车")
	for i in 2400:
		sim.tick(Simulation.STEP)
		if not train.legacy_active:
			break
	h.check(not train.legacy_active, "旧线收尾能结束")
	editor.free()


static func _test_legacy_flip(h: TestHarness) -> void:
	h.section("legacy/flip")
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
	line.flip_segment_by_index(0)
	net.touch()
	sim.tick(Simulation.STEP)
	h.check(train.legacy_active, "改变弯曲方向的线段上的列车也做旧线收尾")
	h.check(train.legacy_range_end - train.legacy_range_start
		< line.geometry.total_length + 1.0, "变化区间只覆盖该线段")
	var finished := false
	for i in 1800:
		sim.tick(Simulation.STEP)
		if not train.legacy_active:
			finished = true
			break
	h.check(finished, "弯曲方向变化的旧线也能收尾完成")
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