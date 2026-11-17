extends RefCounted
## 时间（1 现实秒 = 1 游戏小时）与拖动列车/车厢换线。

static func run(h: TestHarness) -> void:
	_test_time(h)
	_test_train_drag(h)
	_test_carriage_drag(h)


static func _make_level() -> LevelData:
	var level := LevelData.new()
	level.start_lines = 3
	level.start_trains = 0
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.start_hour = 7.0
	level.week_seconds = 168.0
	level.overload_grace = 9999.0
	return level


## 两张互不相交的两站线路。
static func _make_net(level: LevelData) -> Array:
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(700, 300), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(300, 700), Shape.Kind.TRIANGLE)
	var d := net.add_station(Vector2(700, 700), Shape.Kind.CIRCLE)
	var l1 := net.create_line()
	l1.add_stop(a)
	l1.add_stop(b)
	var l2 := net.create_line()
	l2.add_stop(c)
	l2.add_stop(d)
	net.touch()
	return [net, l1, l2, a, b, c, d]


static func _make_train(line: MetroLine, carriages: int = 0) -> Train:
	var train := Train.new()
	train.id = 1
	train.line_id = line.id
	train.carriages = carriages
	train.refresh_capacity()
	train.dist = line.geometry.stop_offsets[0]
	train.stop_index = 0
	train.target_index = 0
	train.state = Train.State.DWELL
	train.dwell_left = 10.0
	train.line_version = line.version
	line.trains.append(train)
	return train


static func _test_time(h: TestHarness) -> void:
	h.section("fleet/time")
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	h.near(sim.hour_of_day(), 7.0, 0.001, "开局 07:00")
	h.check(not sim.is_night(), "07:00 是白天")
	for i in 60:
		sim.tick(Simulation.STEP)
	h.near(sim.hour_of_day(), 8.0, 0.02, "1 秒后是 08:00")
	h.eq(sim.day_index(), 0, "仍是第 0 天")
	for i in 60 * 11:
		sim.tick(Simulation.STEP)
	h.near(sim.hour_of_day(), 19.0, 0.02, "12 秒后是 19:00")
	h.check(sim.is_night(), "19:00 属于夜晚")
	for i in 60 * 12:
		sim.tick(Simulation.STEP)
	h.near(sim.hour_of_day(), 7.0, 0.02, "24 秒后回到 07:00")
	h.eq(sim.day_index(), 1, "进入第 1 天")

	h.eq(Simulation.night_strength(12.0), 0.0, "正午没有夜色")
	h.near(Simulation.night_strength(19.0), 0.5, 0.01, "19:00 夜色渐入一半")
	h.eq(Simulation.night_strength(23.0), 1.0, "深夜夜色全满")
	h.near(Simulation.night_strength(6.0), 0.5, 0.01, "06:00 晨光渐出到一半")
	h.eq(Simulation.night_strength(9.0), 0.0, "上午没有夜色")
	h.eq(sim.hour_12(), 7, "07:00 显示为 7 点")
	h.check(not sim.is_pm(), "07:00 是上午")
	h.eq(sim.weekday_name(), "周二", "跨过一天后是周二")


static func _test_train_drag(h: TestHarness) -> void:
	h.section("fleet/train_drag")
	var level := _make_level()
	var made := _make_net(level)
	var net: MetroNetwork = made[0]
	var l1: MetroLine = made[1]
	var l2: MetroLine = made[2]
	var a: Station = made[3]
	var train := _make_train(l1)
	train.riders.append(Passenger.new(Shape.Kind.TRIANGLE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	var editor := LineEditor.new()
	editor.setup(net, level, null)
	editor.simulation = sim

	var start_pos := l1.geometry.sample(train.dist).origin
	h.eq(editor.begin_gesture(start_pos), true, "按住列车开始拖动")
	h.eq(editor.state, LineEditor.State.TRAIN, "进入 TRAIN 状态")
	var target_pos := l2.geometry.sample(l2.geometry.total_length * 0.5).origin
	editor.move_gesture(target_pos)
	editor.end_gesture(target_pos)
	h.check(train.relocating, "松手后进入'先下客再移动'的收尾流程")
	h.eq(train.line_id, l1.id, "收尾完成前仍属于原线路")
	h.eq(train.relocate_line_id, l2.id, "记录了目标线路")
	h.check(train.relocate_pos.distance_to(target_pos) < 1.0, "记录了目标位置（浅色车画在这里）")

	var finished := false
	for i in 1200:
		sim.tick(Simulation.STEP)
		if not train.relocating:
			finished = true
			break
	h.check(finished, "收尾流程结束")
	h.eq(train.line_id, l2.id, "列车最终换到 2 号线")
	h.eq(l1.trains.size(), 0, "1 号线已没有该列车")
	h.eq(l2.trains.size(), 1, "2 号线接管列车")
	h.eq(a.waiting.size(), 1, "车上的乘客在最近站下车等待")
	h.eq(editor.state, LineEditor.State.IDLE, "拖动结束回到 IDLE")
	editor.free()


static func _test_carriage_drag(h: TestHarness) -> void:
	h.section("fleet/carriage_drag")
	var level := _make_level()
	var made := _make_net(level)
	var net: MetroNetwork = made[0]
	var l1: MetroLine = made[1]
	var l2: MetroLine = made[2]
	var source := _make_train(l1, 1)
	var target := _make_train(l2, 0)
	var editor := LineEditor.new()
	editor.setup(net, level, null)

	var xf := l1.geometry.sample(source.dist)
	var carriage_pos := xf.origin + xf.x.normalized() * -45.0
	h.eq(editor.begin_gesture(carriage_pos), true, "按住车厢开始拖动")
	h.eq(editor.state, LineEditor.State.CARRIAGE, "进入 CARRIAGE 状态")
	var target_pos := l2.geometry.sample(target.dist).origin
	editor.move_gesture(target_pos)
	editor.end_gesture(target_pos)
	h.eq(source.carriages, 0, "源列车失去车厢")
	h.eq(target.carriages, 1, "目标列车获得车厢")
	h.eq(source.capacity, Train.BASE_CAPACITY, "源列车容量回落")
	h.eq(target.capacity, Train.BASE_CAPACITY + Train.CARRIAGE_CAPACITY, "目标列车容量 +6")
	editor.free()