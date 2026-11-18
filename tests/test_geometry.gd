extends RefCounted
## 线路几何：圆角折线、弧长采样、端点手柄。

static func run(h: TestHarness) -> void:
	_test_three_stops(h)
	_test_two_stops(h)
	_test_corner_clamp(h)
	_test_octilinear(h)
	_test_line_render_offset(h)


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


## 八向约束：所有线段只能是水平 / 垂直 / 45°。
static func _test_octilinear(h: TestHarness) -> void:
	h.section("geometry/octilinear")
	var a := Vector2(100, 100)
	var b := Vector2(500, 300)
	var path := LineGeometry.octilinear_segment(a, b)
	h.eq(path.size(), 3, "斜向连接被拆成 45° + 水平两段")
	h.check(path[0] == a and path[2] == b, "端点保持原样")
	h.check(LineGeometry.is_octilinear(path), "所有线段都满足八向约束")
	h.check(path[1].distance_to(Vector2(300, 300)) < 0.01, "折点在对角位置")
	h.check(absf(path[1].x - a.x) == absf(path[1].y - a.y), "第一段严格 45°")

	# 已经八向的连接不插折点
	h.eq(LineGeometry.octilinear_segment(Vector2.ZERO, Vector2(200, 200)).size(), 2, "45° 直连")
	h.eq(LineGeometry.octilinear_segment(Vector2.ZERO, Vector2(200, 0)).size(), 2, "水平直连")
	h.eq(LineGeometry.octilinear_segment(Vector2.ZERO, Vector2(0, 200)).size(), 2, "垂直直连")

	# 纵轴为主时先斜后竖直
	var vertical := LineGeometry.octilinear_segment(Vector2(100, 100), Vector2(300, 500))
	h.eq(vertical.size(), 3, "纵向连接同样两段")
	h.check(vertical[1].distance_to(Vector2(300, 300)) < 0.01, "纵向折点位置正确")
	h.check(LineGeometry.is_octilinear(vertical), "纵向路径八向合法")

	# 整条线路（含站点）也必须八向
	var s1 := Station.new(0, Shape.Kind.CIRCLE, Vector2(0, 0))
	var s2 := Station.new(1, Shape.Kind.SQUARE, Vector2(300, 100))
	var route := LineGeometry.octilinear_route([s1, s2])
	h.check(LineGeometry.is_octilinear(route), "整条线路八向合法")
	var g := LineGeometry.new()
	g.build([s1, s2])
	h.check(g.total_length > 333.0 and g.total_length < 342.0,
		"八向绕行总长约 341（实际 %.2f）" % g.total_length)
	h.check(g.stop_offsets.size() == 2, "两个站都有弧长位置")
	h.check(g.sample(g.stop_offsets[0]).origin.distance_to(s1.pos) < 0.01, "首站落在路径上")
	h.check(g.sample(g.stop_offsets[1]).origin.distance_to(s2.pos) < 0.01, "末站落在路径上")

	# 翻转弯曲方向：先水平/竖直，再 45°
	h.check(LineGeometry.octilinear_segment(Vector2(0, 0), Vector2(300, 100), false)[1]
		.distance_to(Vector2(100, 100)) < 0.01, "默认折点在对角位置")
	var flipped := LineGeometry.octilinear_segment(Vector2(0, 0), Vector2(300, 100), true)
	h.eq(flipped.size(), 3, "翻转后仍是两段")
	h.check(flipped[1].distance_to(Vector2(200, 0)) < 0.01, "翻转后折点落在水平轴上")
	h.check(LineGeometry.is_octilinear(flipped), "翻转后仍满足八向约束")
	h.check(LineGeometry.octilinear_segment(Vector2(100, 100), Vector2(300, 500), true)[1]
		.distance_to(Vector2(100, 300)) < 0.01, "纵向翻转后先竖直再 45°")

	# 线路几何读取 bend_flips（key = 起点 id > 终点 id）
	var s3 := Station.new(3, Shape.Kind.CIRCLE, Vector2(0, 0))
	var s4 := Station.new(4, Shape.Kind.CIRCLE, Vector2(300, 100))
	var flips := {"3>4": true}
	var flipped_route := LineGeometry.octilinear_route([s3, s4], flips)
	h.check(LineGeometry.is_octilinear(flipped_route), "带翻转的线路仍八向合法")
	h.check(flipped_route.size() == 3
		and flipped_route[1].distance_to(Vector2(200, 0)) < 0.01, "带翻转线路的折点正确")


## 多条线路重叠时，渲染点按线号向两侧错开，且反向路径用同一规范法线。
static func _test_line_render_offset(h: TestHarness) -> void:
	h.section("geometry/line_offset")
	var points := PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(300, 300)])
	var left := LineGeometry.offset_points(points, LineGeometry.render_offset(0, 3))
	var middle := LineGeometry.offset_points(points, LineGeometry.render_offset(1, 3))
	var right := LineGeometry.offset_points(points, LineGeometry.render_offset(2, 3))
	h.check(left[1].distance_to(right[1]) > 6.0, "多条重叠线路横向错开")
	h.check(LineGeometry.is_octilinear(left), "偏移后仍是八向折线")
	h.check(LineGeometry.is_octilinear(right), "右侧偏移仍保持水平/竖直/45°")
	h.check(middle[1].distance_to(Vector2(300, 0)) < 0.01, "中间线路保持中心")
	h.check(LineGeometry.offset_points(points, 0.0) == points, "单线不偏移")
	var reversed := PackedVector2Array([Vector2(300, 300), Vector2(300, 0), Vector2(0, 0)])
	var reversed_offset := LineGeometry.offset_points(reversed, LineGeometry.render_offset(0, 3))
	# 反向路径的对应拐点也应与正向偏移在同一侧
	h.check(reversed_offset[1].distance_to(left[1]) < 0.01, "反向绘制也使用同一侧偏移")

	# 圆角/浮点误差会制造极小的 x/y 分量；不能因此把法线判成相反方向，
	# 否则 miter 交点会被甩出几百像素，形成截图里的“竖向长线”。
	var near_axis := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.001, 100.0), Vector2(-0.001, 200.0),
	])
	var near_offset := LineGeometry.offset_points(near_axis, 6.0)
	h.check(absf(near_offset[1].x) < 12.0, "近竖直折线不会产生超长 miter 尖刺")
	h.check((near_offset[1] - near_axis[1]).length() < 20.0, "偏移量保持在合理范围")
