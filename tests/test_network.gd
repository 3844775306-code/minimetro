extends RefCounted
## 网络模型：增删站点/线路、资源计数、派生缓存、拾取。

static func run(h: TestHarness) -> void:
	_test_basics(h)
	_test_line_lifecycle(h)
	_test_station_cache(h)


static func _test_basics(h: TestHarness) -> void:
	h.section("network/basics")
	var level := LevelData.new()
	var net := MetroNetwork.new(level)
	var s0 := net.add_station(Vector2(100, 100), Shape.Kind.CIRCLE)
	var s1 := net.add_station(Vector2(400, 100), Shape.Kind.TRIANGLE)
	var s2 := net.add_station(Vector2(400, 400), Shape.Kind.SQUARE)
	h.eq(net.stations.size(), 3, "三个站点")
	h.eq(net.station_at(Vector2(105, 102), 32.0), s0, "半径内命中最近站点")
	h.eq(net.station_at(Vector2(600, 600), 32.0), null, "半径外返回 null")
	h.eq(net.station_by_id(s2.id), s2, "按 id 查站")
	h.eq(net.available_lines(), level.start_lines, "初始可用线路数")
	h.eq(net.stations[0].line_ids.size(), 0, "新站没有线路")


static func _test_line_lifecycle(h: TestHarness) -> void:
	h.section("network/line_lifecycle")
	var level := LevelData.new()
	var net := MetroNetwork.new(level)
	var s0 := net.add_station(Vector2(100, 100), Shape.Kind.CIRCLE)
	var s1 := net.add_station(Vector2(400, 100), Shape.Kind.TRIANGLE)
	var s2 := net.add_station(Vector2(400, 400), Shape.Kind.SQUARE)

	var line := net.create_line()
	h.eq(net.lines.size(), 1, "创建一条线路")
	h.eq(net.available_lines(), level.start_lines - 1, "线路资源被占用")
	h.eq(line.color, level.line_colors[0], "第一条线使用调色板第一个颜色")

	line.add_stop(s0)
	line.add_stop(s1)
	line.add_stop(s2)
	net.touch()
	h.eq(line.stops.size(), 3, "三个站序")
	h.check(line.is_endpoint(s0), "首站是端点")
	h.check(line.is_endpoint(s2), "末站是端点")
	h.check(line.is_middle(s1), "中间站不是端点")
	h.check(not line.is_middle(s0), "端点不算中间站")
	h.check(line.geometry.is_drawable(), "线路几何可绘制")

	net.remove_line(line)
	h.eq(net.lines.size(), 0, "删除线路")
	h.eq(net.available_lines(), level.start_lines, "删除后资源返还")
	h.eq(s1.line_ids.size(), 0, "站点缓存被清理")

	# 删除中间一条线后，新建线路应复用空出的颜色，不能和已有线重色
	var l1 := net.create_line()
	l1.add_stop(s0)
	l1.add_stop(s1)
	var l2 := net.create_line()
	l2.add_stop(s1)
	l2.add_stop(s2)
	var l3 := net.create_line()
	net.remove_line(l2)
	var l4 := net.create_line()
	var colors := {}
	for each in net.lines:
		colors[each.color] = true
	h.eq(colors.size(), net.lines.size(), "清除线路后新建线路颜色不与已有线路重合")


static func _test_station_cache(h: TestHarness) -> void:
	h.section("network/station_cache")
	var level := LevelData.new()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(100, 100), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(400, 100), Shape.Kind.CIRCLE)
	var c := net.add_station(Vector2(400, 400), Shape.Kind.CIRCLE)
	var l1 := net.create_line()
	l1.add_stop(a)
	l1.add_stop(b)
	var l2 := net.create_line()
	l2.add_stop(b)
	l2.add_stop(c)
	net.touch()
	h.eq(b.line_ids.size(), 2, "换乘站记录两条线路")
	h.eq(a.line_ids.size(), 1, "端点站记录一条线路")
	h.eq(net.available_lines(), level.start_lines - 2, "两条线的资源占用")
