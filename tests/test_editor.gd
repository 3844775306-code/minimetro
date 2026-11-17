extends RefCounted
## 画线手势：连续画线、撤销、回退、取消、端点延伸、站序重排、资源限制。
## 直接调用 LineEditor 的公开手势 API，不需要真实输入事件。

static func run(h: TestHarness) -> void:
	_test_continuous_draw(h)
	_test_undo(h)
	_test_retract_and_rollback(h)
	_test_cancel(h)
	_test_extend_from_handle(h)
	_test_reorder(h)
	_test_no_line_resource(h)
	_test_tap_flip(h)
	_test_drag_insert(h)
	_test_dwell_remove(h)
	_test_dwell_remove_endpoint(h)
	_test_segment_dwell_remove(h)
	_test_reconnect_cooldown(h)
	_test_loop(h)
	_test_loop_closing_segment(h)


static func _make(level: LevelData) -> Array:
	var network := MetroNetwork.new(level)
	var editor := LineEditor.new()
	editor.setup(network, level, null)
	return [network, editor]


static func _test_continuous_draw(h: TestHarness) -> void:
	h.section("editor/continuous_draw")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	var c := network.add_station(Vector2(500, 500), Shape.Kind.SQUARE)

	h.eq(editor.begin_gesture(a.pos), true, "按住车站开始手势")
	h.eq(editor.state, LineEditor.State.DRAFT, "进入 DRAFT")
	h.eq(network.lines.size(), 1, "新建一条线路")
	h.eq(network.available_lines(), 2, "消耗一个线路资源")

	editor.move_gesture(b.pos)
	h.eq(network.lines[0].stops.size(), 2, "经过第二站即时接线")
	editor.move_gesture(c.pos)
	h.eq(network.lines[0].stops.size(), 3, "经过第三站即时接线")
	h.check(network.lines[0].stops[2] == c, "站序为 a-b-c")

	editor.end_gesture(c.pos)
	h.eq(editor.state, LineEditor.State.IDLE, "抬手回到 IDLE")
	h.eq(network.lines[0].stops.size(), 3, "线路保留")
	h.check(network.lines[0].geometry.is_drawable(), "线路几何可绘制")
	editor.free()


static func _test_undo(h: TestHarness) -> void:
	h.section("editor/undo")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	editor.begin_gesture(a.pos)
	editor.move_gesture(b.pos)
	editor.end_gesture(b.pos)
	h.eq(network.lines.size(), 1, "先画出一条线")

	editor.undo()
	h.eq(network.lines.size(), 0, "撤销后线路消失")
	h.eq(network.available_lines(), level.start_lines, "撤销后资源返还")
	h.eq(a.line_ids.size(), 0, "撤销后站点缓存清理")
	editor.free()


static func _test_retract_and_rollback(h: TestHarness) -> void:
	h.section("editor/retract")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	editor.begin_gesture(a.pos)
	editor.move_gesture(b.pos)
	editor.move_gesture(a.pos)
	h.eq(network.lines[0].stops.size(), 2, "拖回上一站不再立即回退（改为停留移出）")
	editor.advance(LineEditor.DWELL_REMOVE_TIME + 0.1)
	h.eq(network.lines[0].stops.size(), 1, "停留 0.8s 后才把上一站移出")

	editor.end_gesture(a.pos)
	h.eq(network.lines.size(), 0, "不足两站的线在抬手时回滚")
	h.eq(network.available_lines(), level.start_lines, "回滚后资源返还")
	editor.free()


static func _test_cancel(h: TestHarness) -> void:
	h.section("editor/cancel")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	editor.begin_gesture(a.pos)
	editor.move_gesture(b.pos)
	editor.cancel_gesture()
	h.eq(network.lines.size(), 0, "取消手势后线路消失")
	h.eq(editor.state, LineEditor.State.IDLE, "取消后回到 IDLE")
	editor.free()


static func _test_extend_from_handle(h: TestHarness) -> void:
	h.section("editor/extend")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	var c := network.add_station(Vector2(500, 500), Shape.Kind.SQUARE)
	var d := network.add_station(Vector2(800, 500), Shape.Kind.CIRCLE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	network.touch()

	var handle := line.geometry.handle_position(false)
	h.eq(editor.begin_gesture(handle), true, "按住末端手柄开始手势")
	h.eq(editor.state, LineEditor.State.DRAFT, "手柄手势进入 DRAFT")
	editor.move_gesture(d.pos)
	h.eq(line.stops.size(), 4, "延伸出一个站")
	h.check(line.stops[3] == d, "新站追加在末端")
	editor.end_gesture(d.pos)
	h.eq(editor.state, LineEditor.State.IDLE, "延伸后回到 IDLE")
	editor.free()


static func _test_reorder(h: TestHarness) -> void:
	h.section("editor/reorder")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	var c := network.add_station(Vector2(500, 500), Shape.Kind.SQUARE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	network.touch()

	h.eq(editor.begin_gesture(b.pos), true, "按住中间站开始重排")
	h.eq(editor.state, LineEditor.State.REORDER, "进入 REORDER")
	editor.move_gesture(c.pos)
	h.check(line.stops[1] == c and line.stops[2] == b, "相邻站顺序交换")
	editor.end_gesture(c.pos)
	h.eq(editor.state, LineEditor.State.IDLE, "重排结束回到 IDLE")
	editor.free()


static func _test_no_line_resource(h: TestHarness) -> void:
	h.section("editor/no_line_resource")
	var level := LevelData.new()
	level.start_lines = 3
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var pts: Array[Vector2] = [
		Vector2(200, 200), Vector2(500, 200), Vector2(200, 500),
		Vector2(500, 500), Vector2(800, 200), Vector2(800, 500),
		Vector2(1100, 350),
	]
	var stations: Array[Station] = []
	for i in pts.size():
		stations.append(network.add_station(pts[i], Shape.Kind.CIRCLE))
	for i in 3:
		var line := network.create_line()
		line.add_stop(stations[i * 2])
		line.add_stop(stations[i * 2 + 1])
	network.touch()
	h.eq(network.available_lines(), 0, "三条线用尽资源")

	var fresh := network.add_station(Vector2(1400, 800), Shape.Kind.SQUARE)
	h.eq(editor.begin_gesture(fresh.pos), false, "无资源时不能新建线路")
	h.eq(network.lines.size(), 3, "线路数量不变")
	editor.free()


## 轻点线段 → 翻转该段弯曲方向；撤销可恢复。
static func _test_tap_flip(h: TestHarness) -> void:
	h.section("editor/tap_flip")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(700, 500), Shape.Kind.SQUARE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	network.touch()
	h.check(not line.is_segment_flipped(0), "初始未翻转")

	var mid := line.geometry.sample(line.geometry.total_length * 0.5).origin
	h.eq(editor.begin_gesture(mid), true, "按在线段上开始手势")
	h.eq(editor.state, LineEditor.State.SEGMENT, "进入 SEGMENT")
	editor.end_gesture(mid)
	h.eq(line.bend_flips.size(), 1, "轻点后记录一次翻转")
	h.check(line.is_segment_flipped(0), "第 0 段已翻转")

	editor.undo()
	var restored: MetroLine = network.lines[0]
	h.check(restored.bend_flips.is_empty(), "撤销恢复弯曲方向")
	editor.free()


## 从线段中间拖到别的站 → 把该站插入这两站之间。
static func _test_drag_insert(h: TestHarness) -> void:
	h.section("editor/drag_insert")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(700, 200), Shape.Kind.SQUARE)
	var c := network.add_station(Vector2(450, 520), Shape.Kind.TRIANGLE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	network.touch()

	var mid := line.geometry.sample(line.geometry.total_length * 0.5).origin
	h.eq(editor.begin_gesture(mid), true, "按在线段上开始手势")
	editor.move_gesture(c.pos)
	editor.end_gesture(c.pos)
	h.eq(line.stops.size(), 3, "站点插入后线路有三站")
	h.check(line.stops[1] == c, "新站插入在 a、b 之间")
	editor.free()


## 拖拽中在前序站点停留 0.8s → 把它移出线路。
static func _test_dwell_remove(h: TestHarness) -> void:
	h.section("editor/dwell_remove")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	var c := network.add_station(Vector2(800, 200), Shape.Kind.SQUARE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	network.touch()

	var handle := line.geometry.handle_position(false)
	h.eq(editor.begin_gesture(handle), true, "从末端手柄继续画线")
	editor.move_gesture(a.pos)
	h.eq(line.stops.size(), 3, "短暂停留不会立刻删站")
	editor.advance(LineEditor.DWELL_REMOVE_TIME + 0.1)
	h.eq(line.stops.size(), 2, "停留 0.8s 后移出该站")
	h.check(not line.has_station(a), "被移出的是指针下的站")
	h.check(line.stops[0] == b and line.stops[1] == c, "其余站序保持")
	editor.end_gesture(a.pos)
	editor.free()


## 拖线段的两个端点站上停留 0.8s 也能把站移出线路。
static func _test_segment_dwell_remove(h: TestHarness) -> void:
	h.section("editor/segment_dwell")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(600, 200), Shape.Kind.SQUARE)
	var c := network.add_station(Vector2(1000, 200), Shape.Kind.TRIANGLE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	network.touch()

	h.eq(editor.begin_gesture(Vector2(400, 200)), true, "按住 A-B 段")
	h.eq(editor.state, LineEditor.State.SEGMENT, "进入拖线段状态")
	editor.move_gesture(a.pos)
	editor.advance(LineEditor.DWELL_REMOVE_TIME + 0.1)
	h.eq(line.stops.size(), 2, "端点站被移出线路")
	h.check(not line.has_station(a), "移出的是段端点 A")
	editor.end_gesture(a.pos)
	editor.free()


## 站台刚被移出线路后，1 秒内不能再接回同一条线。
static func _test_reconnect_cooldown(h: TestHarness) -> void:
	h.section("editor/reconnect_cooldown")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(600, 200), Shape.Kind.SQUARE)
	var c := network.add_station(Vector2(1000, 200), Shape.Kind.TRIANGLE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	network.touch()

	# 从末端手柄延长时把 B 停留移出
	var handle := line.geometry.handle_position(false)
	editor.begin_gesture(handle)
	editor.move_gesture(b.pos)
	editor.advance(LineEditor.DWELL_REMOVE_TIME + 0.1)
	h.check(not line.has_station(b), "B 已被移出线路")
	h.check(editor._cooling(line, b), "刚移出的站进入 1 秒冷却")

	# 冷却期内尝试把 B 接回（先移开再回到 B）
	editor.move_gesture(Vector2(600, 400))
	editor.move_gesture(b.pos)
	h.check(not line.has_station(b), "冷却期内不能接回")
	editor.advance(LineEditor.RECONNECT_COOLDOWN + 0.1)
	editor.move_gesture(Vector2(600, 400))
	editor.move_gesture(b.pos)
	h.check(line.has_station(b), "冷却结束后可以重新接上")
	editor.end_gesture(b.pos)
	editor.free()


## 端点站同样可以被停留 0.8s 移出（从末端手柄延长时，指针下的就是末端站）。
static func _test_dwell_remove_endpoint(h: TestHarness) -> void:
	h.section("editor/dwell_remove_endpoint")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(200, 200), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(500, 200), Shape.Kind.TRIANGLE)
	var c := network.add_station(Vector2(800, 200), Shape.Kind.SQUARE)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	network.touch()

	var handle := line.geometry.handle_position(false)
	h.eq(editor.begin_gesture(handle), true, "抓住末端手柄延长")
	editor.move_gesture(c.pos)
	h.eq(line.stops.size(), 3, "停在末端站上不会立即删除")
	editor.advance(LineEditor.DWELL_REMOVE_TIME + 0.1)
	h.eq(line.stops.size(), 2, "停留 0.8s 后末端站被移出")
	h.check(not line.has_station(c), "末端站已移出线路")
	editor.end_gesture(c.pos)
	editor.free()


## 拖回对侧端点松手 → 闭合为环线。
static func _test_loop(h: TestHarness) -> void:
	h.section("editor/loop")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(700, 300), Shape.Kind.SQUARE)
	var c := network.add_station(Vector2(500, 700), Shape.Kind.TRIANGLE)

	h.eq(editor.begin_gesture(a.pos), true, "从 A 开始画线")
	editor.move_gesture(b.pos)
	editor.move_gesture(c.pos)
	h.eq(network.lines[0].stops.size(), 3, "先连成三站折线")
	editor.move_gesture(a.pos)
	h.check(editor._loop_candidate, "拖回起点进入可闭合状态")
	editor.end_gesture(a.pos)
	var line: MetroLine = network.lines[0]
	h.check(line.is_loop, "松手后闭合成环线")
	h.eq(line.stops.size(), 3, "环线仍是三站")
	h.check(line.geometry.is_drawable(), "环线几何可绘制")
	var perimeter := line.geometry.total_length
	h.check(perimeter > 0.0, "环线总长大于 0")
	h.check(line.geometry.sample(perimeter).origin.distance_to(a.pos) < 1.0,
		"环线终点回到起点所在位置")
	editor.free()


## 环线的闭合段（末站 -> 首站）也可以轻点翻转、拖动/停留移站。
static func _test_loop_closing_segment(h: TestHarness) -> void:
	h.section("editor/loop_closing_segment")
	var level := LevelData.new()
	var made := _make(level)
	var network: MetroNetwork = made[0]
	var editor: LineEditor = made[1]
	var a := network.add_station(Vector2(300, 300), Shape.Kind.CIRCLE)
	var b := network.add_station(Vector2(700, 300), Shape.Kind.SQUARE)
	var c := network.add_station(Vector2(700, 700), Shape.Kind.TRIANGLE)
	var d := network.add_station(Vector2(300, 700), Shape.Kind.DIAMOND)
	var line := network.create_line()
	line.add_stop(a)
	line.add_stop(b)
	line.add_stop(c)
	line.add_stop(d)
	line.is_loop = true
	line.rebuild()
	network.touch()

	var last_offset: float = line.geometry.stop_offsets[line.geometry.stop_offsets.size() - 1]
	var closing_mid := line.geometry.sample(
		(last_offset + line.geometry.total_length) * 0.5).origin
	h.eq(editor.begin_gesture(closing_mid), true, "按在环线闭合段上")
	h.eq(editor.state, LineEditor.State.SEGMENT, "闭合段进入 SEGMENT")
	h.eq(editor._segment_index, 3, "闭合段索引 = 末站下标")

	# 轻点翻转闭合段
	editor.end_gesture(closing_mid)
	h.check(line.is_segment_flipped_pair(d, a), "环线闭合段可以轻点翻转")
	editor.undo()
	line = network.lines[0]

	# 拖动闭合段并在端点 D 上停留 0.8s
	last_offset = line.geometry.stop_offsets[line.geometry.stop_offsets.size() - 1]
	closing_mid = line.geometry.sample(
		(last_offset + line.geometry.total_length) * 0.5).origin
	editor.begin_gesture(closing_mid)
	editor.move_gesture(d.pos)
	editor.advance(LineEditor.DWELL_REMOVE_TIME + 0.1)
	h.check(not line.has_station(d), "环线闭合段端点也能停留移出")
	h.check(editor._segment_removed, "抬手时不会重新插回")
	editor.end_gesture(d.pos)
	editor.free()
