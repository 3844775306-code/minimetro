extends RefCounted
## 换乘寻路：站点-线路二部图、换乘代价、无路可走、继续坐 vs 下车换乘。

static func run(h: TestHarness) -> void:
	_test_transfer_route(h)
	_test_stay_vs_transfer(h)
	_test_no_route(h)


## 小网络：A(圆) -1号线- B(方) -2号线- C(三角)，另有孤立站 D(星)
static func _make() -> Array:
	var level := LevelData.new()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(700, 200), Shape.Kind.SQUARE)
	var c := net.add_station(Vector2(700, 700), Shape.Kind.TRIANGLE)
	var d := net.add_station(Vector2(1200, 900), Shape.Kind.STAR)
	var l1 := net.create_line()
	l1.add_stop(a)
	l1.add_stop(b)
	var l2 := net.create_line()
	l2.add_stop(b)
	l2.add_stop(c)
	net.touch()
	return [net, l1, l2, a, b, c, d]


static func _test_transfer_route(h: TestHarness) -> void:
	h.section("routing/transfer")
	var m := _make()
	var net: MetroNetwork = m[0]
	var l1: MetroLine = m[1]
	var a: Station = m[3]
	var b: Station = m[4]
	var c: Station = m[5]
	var routing := Routing.new()
	routing.rebuild(net)
	h.eq(routing.version, net.version, "寻路版本跟随网络版本")

	var step_a := routing.next_for(a.id, Shape.Kind.TRIANGLE)
	h.eq(int(step_a.get("line", -1)), l1.id, "A 去三角先上 1 号线")
	h.eq(int(step_a.get("station", -1)), b.id, "A 的下一站是 B")

	var step_b := routing.next_for(b.id, Shape.Kind.TRIANGLE)
	h.eq(int(step_b.get("line", -1)), m[2].id, "B 换乘 2 号线")
	h.eq(int(step_b.get("station", -1)), c.id, "B 的下一站是 C")

	var step_c := routing.next_for(c.id, Shape.Kind.CIRCLE)
	h.eq(int(step_c.get("line", -1)), m[2].id, "C 回圆先上 2 号线")
	h.eq(int(step_c.get("station", -1)), b.id, "C 的下一站是 B")

	h.check(routing.next_for(a.id, Shape.Kind.CIRCLE).is_empty(), "同形状站不需要路线")


static func _test_stay_vs_transfer(h: TestHarness) -> void:
	h.section("routing/stay_vs_transfer")
	var m := _make()
	var net: MetroNetwork = m[0]
	var l1: MetroLine = m[1]
	var a: Station = m[3]
	var b: Station = m[4]
	var c: Station = m[5]
	var routing := Routing.new()
	routing.rebuild(net)

	# 在 B 站坐在 1 号线上、目标三角：应该下车换乘（1 号线的下一站是 A，越坐越远）
	var stay := routing.stay_cost(l1.id, b.id, a.id, Shape.Kind.TRIANGLE)
	var leave := routing.board_cost(b.id, Shape.Kind.TRIANGLE)
	h.check(leave < stay, "B 站应下车换乘（leave=%.2f, stay=%.2f）" % [leave, stay])

	# 在 B 站坐上 2 号线、目标三角：继续坐更便宜
	var stay2 := routing.stay_cost(m[2].id, b.id, c.id, Shape.Kind.TRIANGLE)
	h.check(stay2 <= leave, "坐对线路时继续坐更便宜（stay=%.2f, leave=%.2f）" % [stay2, leave])
	h.check(routing.stay_cost(l1.id, a.id, b.id, Shape.Kind.TRIANGLE) < routing.board_cost(a.id, Shape.Kind.TRIANGLE),
		"在 A 站应继续坐 1 号线")


static func _test_no_route(h: TestHarness) -> void:
	h.section("routing/no_route")
	var m := _make()
	var net: MetroNetwork = m[0]
	var a: Station = m[3]
	var d: Station = m[6]
	var routing := Routing.new()
	routing.rebuild(net)
	h.check(routing.next_for(d.id, Shape.Kind.CIRCLE).is_empty(), "孤立站没有路线")
	h.check(routing.board_cost(d.id, Shape.Kind.CIRCLE) >= Routing.INF * 0.5, "孤立站上车代价为无穷")
	h.check(not routing.has_route(d.id, Shape.Kind.CIRCLE), "has_route 为 false")
	h.check(not routing.has_route(a.id, Shape.Kind.CIRCLE), "目标形状就在本站时无需路线")
