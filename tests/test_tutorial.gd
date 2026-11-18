extends RefCounted
## 新手教程状态机：画线 → 接第三站 → 发车 → 挂车厢 → 送客。

static func run(h: TestHarness) -> void:
	_test_steps(h)


static func _test_steps(h: TestHarness) -> void:
	h.section("tutorial/steps")
	var level := LevelData.new()
	level.no_station_spawn = true
	level.start_lines = 1
	level.start_trains = 0
	level.start_carriages = 0
	level.start_bridges = 0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.week_seconds = 999999.0
	level.overload_grace = 999999.0
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(700, 300), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(500, 700), Shape.Kind.TRIANGLE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	var tutorial := TutorialController.new()
	tutorial.setup(net, sim, a, b, c)
	h.check(not sim.auto_assign_lines, "教程关闭自动配车")
	tutorial.update()
	h.eq(tutorial.step, 0, "还没画线时停在第 0 步")

	var line := net.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.rebuild()
	net.touch()
	tutorial.update()
	h.eq(tutorial.step, 1, "两站线路完成后进入第 1 步")
	line.add_stop(c)
	line.rebuild()
	net.touch()
	tutorial.update()
	h.eq(tutorial.step, 2, "接上第三站后进入第 2 步")
	h.eq(sim.inventory_trains, 1, "第 2 步发一辆库存列车")

	var train := Train.new()
	train.line_id = line.id
	train.line_version = line.version
	train.dir = 1
	train.refresh_capacity()
	line.trains.append(train)
	tutorial.update()
	h.eq(tutorial.step, 3, "列车拖上线路后进入第 3 步")
	h.eq(sim.inventory_carriages, 1, "第 3 步发一节库存车厢")
	train.carriages = 1
	tutorial.update()
	h.eq(tutorial.step, 4, "挂上车厢后进入第 4 步")
	h.eq(a.waiting.size(), 1, "第 4 步生成一名待送达乘客")
	sim.delivered = 1
	tutorial.update()
	h.eq(tutorial.step, 5, "送达后进入改线教学")
	h.check(tutorial.station_d != null, "第 5 步出现第四座车站")
	line.add_stop(tutorial.station_d)
	line.rebuild()
	net.touch()
	tutorial.update()
	h.eq(tutorial.step, 6, "插入第四站后进入拆站教学")

	line.stops.erase(tutorial.station_d)
	line.rebuild()
	net.touch()
	tutorial.update()
	h.eq(tutorial.step, 7, "移出 D 站后进入环线教学")

	line.is_loop = true
	line.rebuild()
	net.touch()
	tutorial.update()
	h.eq(tutorial.step, 8, "闭合环线后进入第二条线教学")
	h.check(tutorial.station_e != null, "第 8 步出现河对岸车站")
	h.eq(level.start_lines, 2, "第 8 步解锁第二条线路")
	h.eq(level.start_bridges, 1, "第 8 步发放桥梁额度")

	var line2 := net.create_line()
	line2.add_stop(b)
	line2.add_stop(tutorial.station_e)
	line2.rebuild()
	net.touch()
	tutorial.update()
	h.eq(tutorial.step, 9, "画出跨河第二条线后进入发车教学")
	var train2 := Train.new()
	train2.line_id = line2.id
	train2.line_version = line2.version
	train2.dir = 1
	train2.refresh_capacity()
	line2.trains.append(train2)
	tutorial.update()
	h.eq(tutorial.step, 10, "第二条线发车后进入换乘教学")
	h.check(c.waiting.size() >= 1, "第 10 步生成换乘乘客")
	sim.delivered = 2
	tutorial.update()
	h.eq(tutorial.step, 11, "换乘送达后进入升级卡教学")
	sim.week_pending = true
	tutorial.update()
	h.eq(tutorial.step, 11, "升级卡弹窗期间教程等待")
	sim.week_pending = false
	tutorial.update()
	h.check(tutorial.completed, "选完升级卡后教程完成")
	h.check(not tutorial.active, "完成后停止推进")
