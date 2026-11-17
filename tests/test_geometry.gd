extends RefCounted
## 线路几何：圆角折线、弧长采样、端点手柄。

static func run(h: TestHarness) -> void:
	_test_three_stops(h)
	_test_two_stops(h)
	_test_corner_clamp(h)


static func _test_three_stops(h: TestHarness) -> void:
	h.section("geometry/3_stops")
	var a := Station.new(0, Shape.Kind.CIRCLE, Vector2.ZERO)
	var b := Station.new(1, Shape.Kind.CIRCLE, Vector2(300, 0))
	var c := Station.new(2, Shape.Kind.CIRCLE, Vector2(300, 300))
	var g := LineGeometry.new()
	g.build([a, b, c])
	h.check(g.is_drawable(), "折线可绘制")
	h.check(g.total_length > 585.0 and g.total_length < 605.0,
		"总长约 593（圆角会缩短两个 16px 直角），实际 %.2f" % g.total_length)
	h.check(g.sample(0.0).origin.distance_to(Vector2.ZERO) < 0.01, "sample(0) 在首站")
	h.check(g.sample(g.total_length).origin.distance_to(c.pos) < 0.01, "sample(end) 在末站")
	h.check(absf(g.nearest_distance(Vector2(150, 5)) - 150.0) < 3.0,
		"投影到直线段约 150，实际 %.2f" % g.nearest_distance(Vector2(150, 5)))
	h.check(g.nearest_distance(Vector2.ZERO) < 0.01, "首站投影为 0")
	h.check(g.stop_offsets.size() == 3, "三个站都有弧长位置")
	h.check(g.sample(g.total_length * 0.5).origin.x > 250.0, "中点采样落在折线附近")


static func _test_two_stops(h: TestHarness) -> void:
	h.section("geometry/2_stops")
	var a := Station.new(0, Shape.Kind.CIRCLE, Vector2.ZERO)
	var b := Station.new(1, Shape.Kind.CIRCLE, Vector2(300, 0))
	var g := LineGeometry.new()
	g.build([a, b])
	h.near(g.total_length, 300.0, 0.01, "直线段总长 300")
	h.check(g.sample(150.0).origin.distance_to(Vector2(150, 0)) < 0.01, "中点位置")
	h.near(g.sample(150.0).x.angle(), 0.0, 0.01, "切线朝 +x")
	h.check(g.handle_position(true).distance_to(Vector2(-30, 0)) < 0.01, "起点手柄在站外侧 30px")
	h.check(g.handle_position(false).distance_to(Vector2(330, 0)) < 0.01, "终点手柄在站外侧 30px")


static func _test_corner_clamp(h: TestHarness) -> void:
	h.section("geometry/corner_clamp")
	var a := Station.new(0, Shape.Kind.CIRCLE, Vector2(0, 50))
	var b := Station.new(1, Shape.Kind.CIRCLE, Vector2(10, 50))
	var c := Station.new(2, Shape.Kind.CIRCLE, Vector2(10, 60))
	var g := LineGeometry.new()
	g.build([a, b, c])
	h.check(g.is_drawable(), "相邻站很近时仍可绘制")
	h.check(is_finite(g.total_length) and g.total_length > 0.0, "总长有限且为正")
	h.check(g.stop_offsets.size() == 3, "站点偏移依然完整")
