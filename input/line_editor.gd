class_name LineEditor
extends Node2D
## 画线手势控制器。
##
## 交互：
##   · 按住车站拖拽 → 新建线路；经过其他站即时接线（连续画线）
##   · 拖回上一站 → 回退一段
##   · 按住线路端点的小圆手柄 → 从该端继续延伸
##   · 按住线路中间的车站拖动 → 调整站序
##   · 拖拽中在"已在本线上的非相邻站"停留 0.8s → 把该站移出线路（画线橡皮擦）
##   · 轻点线路（按下即抬起、几乎不移动）→ 翻转该段 45° 折线的弯曲方向
##   · 从一段线路中间拖到别的车站 → 把该站插入这两站之间
##   · 右键 / Esc → 取消本次手势；Ctrl+Z → 撤销（整次手势为单位）
##
## 手势只改 MetroNetwork 与 MetroLine；本节点负责拾取、预览、快照/撤销。
## begin_gesture / move_gesture / end_gesture / advance 是公开 API，测试直接调用。

signal toast_requested(message: String)
## 没有手势在进行时按 Esc：交给外层打开暂停/设置菜单。
signal settings_requested

enum State { IDLE, DRAFT, REORDER, SEGMENT, TRAIN, CARRIAGE, STOCK }

signal stock_drop_requested(kind: String, pos: Vector2)

const SNAP_RADIUS := 32.0
## 端点手柄做大一点，更容易抓住
const HANDLE_HIT_RADIUS := 30.0
const HANDLE_DISTANCE := 34.0
## 站台移出线路后，1 秒内不能再接回同一条线
const RECONNECT_COOLDOWN := 1.0
const REORDER_SNAP := 52.0
const REORDER_DEADZONE := 9.0
const SWAP_COOLDOWN := 0.15
const UNDO_LIMIT := 40
const LINE_HIT_RADIUS := 13.0
const TAP_MAX_MOVE := 7.0
## 画线时在已在本线上的站点停留多久触发"移出线路"。
const DWELL_REMOVE_TIME := 0.8

var network: MetroNetwork = null
var level: LevelData = null
var station_layer: StationLayer = null
## 撤销站台（停留移出）的悬停时间，设置里可调，默认 0.8 秒。
var dwell_remove_time := DWELL_REMOVE_TIME
## 主场景注入：拖车换线时由模拟层负责"先下客再移动"的收尾流程
var simulation: Simulation = null

var state: int = State.IDLE
var cursor := Vector2.ZERO
var hover_station: Station = null

var _dragging := false
var _press_pos := Vector2.ZERO
var _gesture_dirty := false

var _draft_line: MetroLine = null
var _draft_is_new := false
var _draft_at_start := false
var _draft_base_len := 0

var _reorder_line: MetroLine = null
var _reorder_station: Station = null
var _swap_cooldown := 0.0

var _segment_line: MetroLine = null
var _segment_index := -1
var _segment_dragging := false
## 本次拖线段手势已经通过"停留"移出过站台：抬手时不要再触发插入/翻折
var _segment_removed := false

## 拖动列车 / 车厢换线
var _fleet_line: MetroLine = null
var _fleet_train: Train = null
var _fleet_dragging := false
var _fleet_target_line: MetroLine = null
var _fleet_target_train: Train = null

## 从 HUD 库存图标拖资源到地图
var _stock_kind := ""
var _stock_hover_line: MetroLine = null
var _stock_hover_station: Station = null
var _stock_hover_train: Train = null

var _hover_dwell := 0.0
var _dwell_station: Station = null
## 拖回对侧端点时进入"可闭合环线"状态：松手成环
var _loop_candidate := false
## 站台被移出线路后的再接冷却（key = "线路id:站台id"，值 = 剩余秒数）
var _removal_cooldowns := {}

var _undo: Array[Dictionary] = []


func setup(net: MetroNetwork, lvl: LevelData, view: StationLayer = null) -> void:
	network = net
	level = lvl
	station_layer = view


func _unhandled_input(event: InputEvent) -> void:
	if network == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			cursor = get_global_mouse_position()
			if event.pressed:
				begin_gesture(cursor)
			else:
				end_gesture(cursor)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_gesture()
	elif event is InputEventMouseMotion:
		cursor = get_global_mouse_position()
		if _dragging:
			move_gesture(cursor)
		else:
			_refresh_hover(cursor)
			_request_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			undo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if state != State.IDLE or _dragging:
				cancel_gesture()
				get_viewport().set_input_as_handled()
			else:
				settings_requested.emit()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	advance(delta)


## 独立于渲染推进手势计时（停留删除、重排冷却）。测试直接调用。
func advance(delta: float) -> void:
	if _swap_cooldown > 0.0:
		_swap_cooldown = maxf(0.0, _swap_cooldown - delta)
	for key in _removal_cooldowns.keys():
		var remaining := float(_removal_cooldowns[key]) - delta
		if remaining <= 0.0:
			_removal_cooldowns.erase(key)
		else:
			_removal_cooldowns[key] = remaining
	_update_dwell(delta)
	_request_redraw()


## 站台刚被移出：1 秒内不允许再接到同一条线上。
func _mark_removed(line: MetroLine, station: Station) -> void:
	if line == null or station == null:
		return
	_removal_cooldowns["%d:%d" % [line.id, station.id]] = RECONNECT_COOLDOWN


func _cooling(line: MetroLine, station: Station) -> bool:
	if line == null or station == null:
		return false
	return float(_removal_cooldowns.get("%d:%d" % [line.id, station.id], 0.0)) > 0.0


# ---------------------------------------------------------------------------
# 公开手势 API（测试直接调用）
# ---------------------------------------------------------------------------

func begin_gesture(pos: Vector2) -> bool:
	if network == null:
		return false
	_dragging = true
	_press_pos = pos
	cursor = pos
	_gesture_dirty = false
	_segment_line = null
	_segment_index = -1
	_segment_dragging = false
	_segment_removed = false
	_loop_candidate = false
	_fleet_line = null
	_fleet_train = null
	_fleet_dragging = false
	_fleet_target_line = null
	_fleet_target_train = null
	_refresh_hover(pos)

	# 车厢 / 列车优先：拖动它们换线
	var carriage_hit := _carriage_at(pos)
	if not carriage_hit.is_empty():
		_begin_fleet_drag(carriage_hit, true)
		return true
	var train_hit := _train_at(pos)
	if not train_hit.is_empty():
		_begin_fleet_drag(train_hit, false)
		return true

	var handle_line := _handle_at(pos)
	if handle_line != null:
		_begin_extend(handle_line)
		return true

	var st := network.station_at(pos, SNAP_RADIUS)
	if st != null:
		var middle_line := _middle_line_of(st)
		if middle_line != null:
			_begin_reorder(middle_line, st)
			return true
		return _begin_new_line(st)

	var hit := _line_hit(pos)
	if not hit.is_empty():
		_segment_line = hit["line"]
		_segment_index = int(hit["segment"])
		_segment_dragging = false
		state = State.SEGMENT
		return true

	_dragging = false
	state = State.IDLE
	_request_redraw()
	return false


func move_gesture(pos: Vector2) -> void:
	if not _dragging:
		return
	cursor = pos
	_refresh_hover(pos)
	_update_loop_candidate()
	match state:
		State.DRAFT:
			_draft_update()
		State.REORDER:
			_reorder_update()
		State.SEGMENT:
			if cursor.distance_to(_press_pos) >= TAP_MAX_MOVE:
				_segment_dragging = true
		State.TRAIN:
			if cursor.distance_to(_press_pos) >= 8.0:
				_fleet_dragging = true
			_fleet_target_line = _target_line(pos, null)
		State.CARRIAGE:
			if cursor.distance_to(_press_pos) >= 8.0:
				_fleet_dragging = true
			_fleet_target_train = _target_train(pos, _fleet_train)
		State.STOCK:
			_stock_update_hover(pos)
	_request_redraw()


func end_gesture(pos: Vector2) -> void:
	_dragging = false
	cursor = pos
	match state:
		State.DRAFT:
			if _loop_candidate and _draft_line != null and _draft_line.stops.size() >= 3:
				_close_loop()
			else:
				var too_short := _draft_line == null or _draft_line.stops.size() < 2
				if too_short:
					_restore_pending_undo()
				elif not _gesture_dirty:
					_drop_pending_undo()
		State.REORDER:
			if not _gesture_dirty:
				_drop_pending_undo()
		State.SEGMENT:
			if _segment_removed:
				pass
			elif not _segment_dragging:
				_apply_segment_tap()
			elif hover_station != null:
				_apply_segment_insert()
		State.TRAIN:
			if _fleet_dragging and _fleet_train != null and _fleet_target_line != null:
				_move_train(_fleet_train, _fleet_line, _fleet_target_line)
		State.CARRIAGE:
			if _fleet_dragging and _fleet_train != null:
				_move_carriage(_fleet_train, _fleet_target_train)
		State.STOCK:
			stock_drop_requested.emit(_stock_kind, pos)
	_reset_gesture()
	_request_redraw()


func cancel_gesture() -> void:
	if state == State.SEGMENT:
		_dragging = false
		_reset_gesture()
		_request_redraw()
		return
	if state == State.IDLE:
		return
	_restore_pending_undo()
	_dragging = false
	_reset_gesture()
	_request_redraw()


func undo() -> void:
	if state != State.IDLE:
		cancel_gesture()
		return
	if _undo.is_empty():
		return
	_apply_snapshot(_undo.pop_back())
	_request_redraw()


# ---------------------------------------------------------------------------
# 新建 / 延长 / 回退
# ---------------------------------------------------------------------------

func _begin_new_line(st: Station) -> bool:
	if network.available_lines() <= 0:
		toast_requested.emit("没有可用的线路了")
		_dragging = false
		state = State.IDLE
		return false
	_push_undo()
	var line := network.create_line()
	_draft_line = line
	_draft_is_new = true
	_draft_at_start = false
	_draft_base_len = 0
	line.add_stop(st)
	network.touch()
	state = State.DRAFT
	_request_redraw()
	return true


func _begin_extend(line: MetroLine) -> void:
	_push_undo()
	_draft_line = line
	_draft_is_new = false
	_draft_at_start = _handle_at_start
	_draft_base_len = line.stops.size()
	state = State.DRAFT


func _begin_reorder(line: MetroLine, st: Station) -> void:
	_push_undo()
	_reorder_line = line
	_reorder_station = st
	state = State.REORDER


func _draft_update() -> void:
	if _draft_line == null or hover_station == null:
		return
	if _loop_candidate:
		return
	var tip_index := _draft_tip_index()
	if hover_station == _draft_line.stops[tip_index]:
		return
	if _draft_line.has_station(hover_station):
		# 已在本线上的站：交给"停留 0.8s 移出"逻辑处理
		return
	_extend_with(hover_station)


func _draft_tip_index() -> int:
	return 0 if _draft_at_start else _draft_line.stops.size() - 1


func _extend_with(st: Station) -> void:
	if _cooling(_draft_line, st):
		toast_requested.emit("站台刚被移出线路，稍后再接")
		return
	var tip: Station = _draft_line.stops[_draft_tip_index()]
	var from_pos: Vector2 = st.pos if _draft_at_start else tip.pos
	var to_pos: Vector2 = tip.pos if _draft_at_start else st.pos
	if network.segment_crosses_water(from_pos, to_pos, false) and network.available_bridges() <= 0:
		toast_requested.emit("没有可用的桥 / 隧道了")
		return
	# 从环线的端点手柄继续延伸时，先把环打开（快照里保留着环线状态，可撤销）
	if _draft_line.is_loop:
		_draft_line.is_loop = false
		_draft_line.rebuild()
	if _draft_at_start:
		_draft_line.prepend_stop(st)
	else:
		_draft_line.add_stop(st)
	network.touch()
	_gesture_dirty = true


## 拖回对侧端点（首站↔末站）时进入"可闭合成环"状态；松手即闭合。
func _update_loop_candidate() -> void:
	_loop_candidate = false
	if state != State.DRAFT or _draft_line == null or hover_station == null:
		return
	if _draft_line.is_loop or _draft_line.stops.size() < 3:
		return
	var opposite: Station
	if _draft_at_start:
		opposite = _draft_line.stops[_draft_line.stops.size() - 1]
	else:
		opposite = _draft_line.stops[0]
	if hover_station == opposite:
		_loop_candidate = true


func _close_loop() -> void:
	if _draft_line == null:
		return
	_draft_line.is_loop = true
	_draft_line.rebuild()
	network.touch()
	_gesture_dirty = true


# ---------------------------------------------------------------------------
# 画线时"停留移出站点"（任意已在本线上的站，不限相邻）
# ---------------------------------------------------------------------------

func _update_dwell(delta: float) -> void:
	var line: MetroLine = null
	var drafting := false
	if state == State.DRAFT:
		line = _draft_line
		drafting = true
	elif state == State.SEGMENT and _segment_line != null \
			and (cursor.distance_to(_press_pos) >= TAP_MAX_MOVE or _segment_dragging):
		line = _segment_line
	else:
		_reset_dwell()
		return
	if line == null or line.stops.size() <= 1:
		_reset_dwell()
		return
	if drafting:
		if hover_station == null or not line.has_station(hover_station):
			_reset_dwell()
			return
		if hover_station != _dwell_station:
			_dwell_station = hover_station
			_hover_dwell = 0.0
		_hover_dwell += delta
		if _hover_dwell >= dwell_remove_time:
			_remove_dwelled_station()
		return
	# 拖线段时只认这一段的两个端点站；按光标距离判断，避免 hover 状态抖动导致计时被重置
	var endpoints := _segment_endpoint_stations(line, _segment_index)
	if endpoints.is_empty():
		_reset_dwell()
		return
	var target: Station = null
	for endpoint in endpoints:
		if cursor.distance_to(endpoint.pos) <= SNAP_RADIUS + 8.0:
			target = endpoint
			break
	if target == null:
		_reset_dwell()
		return
	hover_station = target
	if target != _dwell_station:
		_dwell_station = target
		_hover_dwell = 0.0
	_hover_dwell += delta
	if _hover_dwell >= dwell_remove_time:
		_remove_segment_endpoint()


func _reset_dwell() -> void:
	_hover_dwell = 0.0
	_dwell_station = null


func _remove_dwelled_station() -> void:
	var target := _dwell_station
	_reset_dwell()
	if target == null or _draft_line == null:
		return
	var idx := _draft_line.stops.find(target)
	if idx < 0 or _draft_line.stops.size() <= 1:
		return
	_draft_line.remove_stop_at(idx)
	network.touch()
	_mark_removed(_draft_line, target)
	_gesture_dirty = true
	_loop_candidate = false
	if not _draft_is_new and _draft_line.stops.size() < 2:
		_cancel_short_line(_draft_line)
		_reset_gesture()


## 拖线段时，在段两端的车站上停留 0.8s 也能把该站移出线路。
func _remove_segment_endpoint() -> void:
	var target := _dwell_station
	_reset_dwell()
	var line := _segment_line
	if target == null or line == null:
		return
	var idx := line.stops.find(target)
	if idx < 0 or line.stops.size() <= 1:
		return
	_push_undo()
	line.remove_stop_at(idx)
	network.touch()
	_mark_removed(line, target)
	_segment_line = null
	_segment_index = -1
	_segment_dragging = false
	_segment_removed = true
	_gesture_dirty = true
	if line.stops.size() < 2:
		_cancel_short_line(line)


## 编辑后不足两站：移除线路并返还列车（有模拟层时由 Simulation 处理库存）。
func _cancel_short_line(line: MetroLine) -> void:
	if line == null or line.stops.size() >= 2:
		return
	if simulation != null:
		simulation.cancel_line(line)
	else:
		network.remove_line(line)


## 是否正在画线/拖线（供 Simulation 避免剪掉草稿线）。
func is_busy() -> bool:
	return _dragging or state != State.IDLE


# ---------------------------------------------------------------------------
# 轻点翻转 / 拖拽插入
# ---------------------------------------------------------------------------

func _apply_segment_tap() -> void:
	var line := _segment_line
	if line == null or _segment_index < 0:
		return
	var endpoints := _segment_endpoint_stations(line, _segment_index)
	if endpoints.size() != 2:
		return
	_push_undo()
	line.flip_segment(endpoints[0], endpoints[1])
	network.touch()
	_gesture_dirty = true


func _apply_segment_insert() -> void:
	var line := _segment_line
	if line == null or _segment_index < 0:
		return
	var endpoints := _segment_endpoint_stations(line, _segment_index)
	if endpoints.size() != 2:
		return
	var st := hover_station
	if st == null or line.has_station(st):
		return
	if _cooling(line, st):
		toast_requested.emit("站台刚被移出线路，稍后再接")
		return
	var a: Station = endpoints[0]
	var b: Station = endpoints[1]
	var delta := 0
	if network.segment_crosses_water(a.pos, st.pos, false):
		delta += 1
	if network.segment_crosses_water(st.pos, b.pos, false):
		delta += 1
	if network.segment_crosses_water(a.pos, b.pos, line.is_segment_flipped_pair(a, b)):
		delta -= 1
	if delta > network.available_bridges():
		toast_requested.emit("没有可用的桥 / 隧道了")
		return
	_push_undo()
	line.insert_stop(_segment_index + 1, st)
	network.touch()
	_gesture_dirty = true


## 命中哪条线、哪一段（按最近距离）。
func _line_hit(pos: Vector2) -> Dictionary:
	var best_line: MetroLine = null
	var best_segment := -1
	var best_dist := LINE_HIT_RADIUS
	for line in network.lines:
		if line.stops.size() < 2 or not line.geometry.is_drawable():
			continue
		var d := line.geometry.nearest_distance(pos)
		var nearest := line.geometry.sample(d).origin
		var dist := nearest.distance_to(pos)
		if dist > best_dist:
			continue
		var segment := _segment_at_offset(line, d)
		if segment < 0:
			continue
		best_line = line
		best_segment = segment
		best_dist = dist
	if best_line == null:
		return {}
	return {"line": best_line, "segment": best_segment}


func _segment_at_offset(line: MetroLine, offset: float) -> int:
	var offsets := line.geometry.stop_offsets
	if offsets.size() < 2:
		return -1
	if line.is_loop and line.stops.size() >= 3:
		# 环线的闭合段（末站 -> 首站）也要能拖
		if offset >= offsets[offsets.size() - 1] - 1.0 or offset <= offsets[0] + 1.0:
			return offsets.size() - 1
	for i in range(offsets.size() - 1):
		if offset >= offsets[i] - 1.0 and offset <= offsets[i + 1] + 1.0:
			return i
	return -1


## 取某个段索引的两端站；环线的闭合段（index = 末站下标）另一端是首站。
func _segment_endpoint_stations(line: MetroLine, segment: int) -> Array[Station]:
	var result: Array[Station] = []
	if line == null or segment < 0 or segment >= line.stops.size():
		return result
	if segment == line.stops.size() - 1:
		if not line.is_loop or line.stops.size() < 3:
			return result
		result.append(line.stops[segment])
		result.append(line.stops[0])
		return result
	result.append(line.stops[segment])
	result.append(line.stops[segment + 1])
	return result


# ---------------------------------------------------------------------------
# 从 HUD 库存图标拖资源到地图
# ---------------------------------------------------------------------------

func begin_stock_drag(kind: String, pos: Vector2) -> bool:
	if network == null:
		return false
	_dragging = true
	_press_pos = pos
	cursor = pos
	_stock_kind = kind
	_stock_hover_line = null
	_stock_hover_station = null
	_stock_hover_train = null
	state = State.STOCK
	_refresh_hover(pos)
	_request_redraw()
	return true


func _stock_update_hover(pos: Vector2) -> void:
	_stock_hover_station = network.station_at(pos, Shape.STATION_RADIUS + 12.0)
	_stock_hover_train = _train_at(pos).get("train")
	_stock_hover_line = null
	if _stock_kind == "interchange":
		return
	_stock_hover_line = _target_line(pos, null)
	if _stock_kind == "carriage" and _stock_hover_train == null and _stock_hover_line != null:
		_stock_hover_train = _least_carriage_train(_stock_hover_line)


func _draw_stock_preview() -> void:
	var paper := Color.WHITE
	var ink := Color("#2B2B2B")
	match _stock_kind:
		"train":
			var body := Vector2(56.0, 28.0)
			draw_rect(Rect2(cursor - body * 0.5, body), Color(paper, 0.85))
			draw_rect(Rect2(cursor - body * 0.5, body), Color(ink, 0.85), false, 2.5)
		"express":
			var body := Vector2(66.0, 24.0)
			draw_rect(Rect2(cursor - body * 0.5, body), Color(paper, 0.85))
			draw_rect(Rect2(cursor - body * 0.5, body), Color(ink, 0.85), false, 2.5)
			draw_colored_polygon(PackedVector2Array([
				cursor + Vector2(body.x * 0.5, -body.y * 0.5),
				cursor + Vector2(body.x * 0.5 + 10.0, 0.0),
				cursor + Vector2(body.x * 0.5, body.y * 0.5),
			]), Color(paper, 0.85))
		"carriage":
			var rect := Rect2(cursor - Vector2(10.0, 11.0), Vector2(20.0, 22.0))
			draw_rect(rect, Color(paper, 0.85))
			draw_rect(rect, Color(ink, 0.85), false, 2.5)
		"interchange":
			draw_circle(cursor, 13.0, Color(paper, 0.9), true, -1.0, true)
			draw_arc(cursor, 13.0, 0.0, TAU, 32, Color(ink, 0.9), 2.5, true)
	if _stock_kind == "interchange" and _stock_hover_station != null:
		draw_arc(_stock_hover_station.pos, Shape.STATION_RADIUS + 16.0, 0.0, TAU, 48,
			Color(ink, 0.7), 3.0, true)
	elif _stock_hover_line != null:
		var offset := _stock_hover_line.geometry.nearest_distance(cursor)
		var point := _stock_hover_line.geometry.sample(offset).origin
		draw_arc(point, 24.0, 0.0, TAU, 40, Color(ink, 0.7), 3.0, true)
	if _stock_kind == "carriage" and _stock_hover_train != null:
		for line in network.lines:
			if line.geometry.is_drawable() and line.trains.has(_stock_hover_train):
				var point := line.geometry.sample(_stock_hover_train.dist).origin
				draw_arc(point, 30.0, 0.0, TAU, 40, Color(ink, 0.8), 3.0, true)
				break


# ---------------------------------------------------------------------------
# 拖动列车 / 车厢换线
# ---------------------------------------------------------------------------

func _begin_fleet_drag(hit: Dictionary, is_carriage: bool) -> void:
	_fleet_line = hit["line"]
	_fleet_train = hit["train"]
	_fleet_dragging = false
	_fleet_target_line = null
	_fleet_target_train = null
	state = State.CARRIAGE if is_carriage else State.TRAIN


## 光标下的列车（靠近车身中心；旧线收尾时按旧几何算位置）。
func _train_at(pos: Vector2) -> Dictionary:
	for line in network.lines:
		if not line.geometry.is_drawable():
			continue
		for train in line.trains:
			var point := _train_world_position(line, train)
			if point.distance_to(pos) <= 23.0:
				return {"line": line, "train": train}
	return {}


func _train_world_position(line: MetroLine, train: Train) -> Vector2:
	var geometry := line.geometry
	if train.legacy_active and train.legacy_geometry != null:
		geometry = train.legacy_geometry
	var xf := geometry.sample(train.dist)
	return xf.origin + LineGeometry.canonical_normal(xf.x) * line.render_offset


## 光标下的车厢（车厢画在列车尾部，与 TrainView 使用同一套偏移）。
func _carriage_at(pos: Vector2) -> Dictionary:
	for line in network.lines:
		if not line.geometry.is_drawable():
			continue
		for train in line.trains:
			for i in train.carriages:
				if _carriage_position(line, train, i).distance_to(pos) <= 26.0:
					return {"line": line, "train": train, "index": i}
	return {}


func _carriage_position(line: MetroLine, train: Train, index: int) -> Vector2:
	var geometry := line.geometry
	if train.legacy_active and train.legacy_geometry != null:
		geometry = train.legacy_geometry
	var xf := geometry.sample(train.dist)
	return xf.origin + LineGeometry.canonical_normal(xf.x) * line.render_offset + xf.x.normalized() * -(
		TrainView.CARRIAGE_FIRST_OFFSET + TrainView.CARRIAGE_SPACING * float(index)
	)


## 拖动目标是哪条线（排除源线路）：优先线路本体，其次站内线路。
func _target_line(pos: Vector2, exclude: MetroLine) -> MetroLine:
	var best: MetroLine = null
	var best_dist := LINE_HIT_RADIUS + 5.0
	for line in network.lines:
		if line == exclude or line.stops.size() < 2 or not line.geometry.is_drawable():
			continue
		var offset := line.geometry.nearest_distance(pos)
		var nearest := line.geometry.sample(offset).origin
		var distance := nearest.distance_to(pos)
		if distance < best_dist:
			best_dist = distance
			best = line
	if best != null:
		return best
	var station := network.station_at(pos, 40.0)
	if station != null:
		for line in network.lines:
			if line != exclude and line.stops.size() >= 2 and line.has_station(station):
				return line
	return null


## 车厢的落点列车：优先光标附近的列车，其次目标线路上车厢最少的列车。
func _target_train(pos: Vector2, exclude: Train) -> Train:
	var best: Train = null
	var best_dist := 60.0
	for line in network.lines:
		if not line.geometry.is_drawable():
			continue
		for train in line.trains:
			if train == exclude:
				continue
			var distance := line.geometry.sample(train.dist).origin.distance_to(pos)
			if distance < best_dist:
				best_dist = distance
				best = train
	if best != null:
		return best
	var line := _target_line(pos, null)
	if line == null:
		return null
	return _least_carriage_train(line)


func _least_carriage_train(line: MetroLine) -> Train:
	var best: Train = null
	for train in line.trains:
		if best == null or train.carriages < best.carriages:
			best = train
	return best


## 把列车拖到别处：先停靠当前线路最近站下客，再移动到目标位置。
## 有模拟层时交给 Simulation 做收尾；没有（纯编辑器测试）时直接落位。
func _move_train(train: Train, from_line: MetroLine, to_line: MetroLine) -> void:
	if train == null or from_line == null or to_line == null:
		return
	if to_line.stops.size() < 2 or not to_line.geometry.is_drawable():
		return
	if from_line == to_line and absf(to_line.geometry.nearest_distance(cursor) - train.dist) < 20.0:
		return
	if simulation != null:
		simulation.request_train_relocation(train, from_line, to_line, cursor)
		return
	_apply_train_move_instant(train, from_line, to_line)


func _apply_train_move_instant(train: Train, from_line: MetroLine, to_line: MetroLine) -> void:
	from_line.trains.erase(train)
	to_line.trains.append(train)
	train.line_id = to_line.id
	train.line_version = -1
	_place_train_on_line(train, to_line, cursor)
	network.touch()


## 让列车落在目标线上的任意弧长位置（不需要从起点站出发）。
## 朝向按"距离最近的站台"决定：车头指向最近的站。
func _place_train_on_line(train: Train, line: MetroLine, pos: Vector2) -> void:
	var total := line.geometry.total_length
	var d := clampf(line.geometry.nearest_distance(pos), 0.0, total)
	train.dist = d
	train.speed = 0.0
	train.dwell_left = 0.0
	var offsets := line.geometry.stop_offsets
	var nearest := 0
	var best_diff := INF
	var loop_dir := 1
	for i in offsets.size():
		var diff := 0.0
		if line.is_loop:
			var forward := fposmod(offsets[i] - d, total) if total > 0.001 else 0.0
			var backward := fposmod(d - offsets[i], total) if total > 0.001 else 0.0
			diff = minf(forward, backward)
			loop_dir = 1 if forward <= backward else -1
		else:
			diff = absf(offsets[i] - d)
		if diff < best_diff:
			best_diff = diff
			nearest = i
	if line.is_loop and line.stops.size() >= 3:
		if best_diff <= 1.0:
			loop_dir = 1
			nearest = (nearest + 1) % line.stops.size()
		train.dir = loop_dir
		train.target_index = nearest
		var target := offsets[nearest]
		if train.dir > 0 and target <= d:
			target += total
		elif train.dir < 0 and target >= d:
			target -= total
		train.target_dist = target
		train.state = Train.State.MOVING
		return
	var station_offset := offsets[nearest]
	if absf(station_offset - d) < 1.0:
		# 正好落在站上：朝向下一站（末站则朝前一站）
		if nearest < line.stops.size() - 1:
			train.dir = 1
			train.target_index = nearest + 1
			train.target_dist = offsets[nearest + 1]
		else:
			train.dir = -1
			train.target_index = nearest - 1
			train.target_dist = offsets[nearest - 1]
	else:
		train.dir = 1 if station_offset > d else -1
		train.target_index = nearest
		train.target_dist = station_offset
	train.state = Train.State.MOVING


## 把一节车厢从一列车挂到另一列车上（可跨线路）。
func _move_carriage(source: Train, target: Train) -> void:
	if source == null or target == null or source == target:
		return
	if source.carriages <= 0:
		return
	source.carriages -= 1
	source.refresh_capacity()
	target.carriages += 1
	target.refresh_capacity()


# ---------------------------------------------------------------------------
# 重排
# ---------------------------------------------------------------------------

func _reorder_update() -> void:
	if _reorder_line == null or _reorder_station == null:
		return
	if cursor.distance_to(_press_pos) < REORDER_DEADZONE:
		return
	if _swap_cooldown > 0.0:
		return
	var idx := _reorder_line.stops.find(_reorder_station)
	if idx < 0:
		return
	var neighbors: Array[int] = []
	if idx > 0:
		neighbors.append(idx - 1)
	if idx < _reorder_line.stops.size() - 1:
		neighbors.append(idx + 1)
	for ni in neighbors:
		var other: Station = _reorder_line.stops[ni]
		if cursor.distance_to(other.pos) <= REORDER_SNAP:
			_swap(idx, ni)
			# 重排可能让某段跨河：桥隧不够就回滚
			if level != null and network.used_bridges() > level.start_bridges:
				_swap(idx, ni)
				toast_requested.emit("没有可用的桥 / 隧道了")
				return
			_gesture_dirty = true
			_swap_cooldown = SWAP_COOLDOWN
			network.touch()
			return


func _swap(a: int, b: int) -> void:
	var tmp: Station = _reorder_line.stops[a]
	_reorder_line.stops[a] = _reorder_line.stops[b]
	_reorder_line.stops[b] = tmp
	_reorder_line.rebuild()


# ---------------------------------------------------------------------------
# 拾取
# ---------------------------------------------------------------------------

var _handle_at_start := false


## 命中某条线路的端点手柄则返回该线路，并记录是首端还是末端。
func _handle_at(pos: Vector2) -> MetroLine:
	if network == null:
		return null
	for line in network.lines:
		if line.stops.size() < 2:
			continue
		for at_start in [true, false]:
			var hp := _handle_world_position(line, at_start)
			if pos.distance_to(hp) <= HANDLE_HIT_RADIUS:
				_handle_at_start = at_start
				return line
	return null


func _handle_world_position(line: MetroLine, at_start: bool) -> Vector2:
	var hp := line.geometry.handle_position(at_start, HANDLE_DISTANCE)
	var xf := line.geometry.sample(0.0 if at_start else line.geometry.total_length)
	# 端点手柄比线身错开更多，避免多条线收尾时几个圆头叠在一起
	return hp + LineGeometry.canonical_normal(xf.x) * line.render_offset * 3.0


## 若不是端点、且在某条线的中间，则返回那条线（用于重排）。
func _middle_line_of(st: Station) -> MetroLine:
	for line in network.lines:
		if line.is_loop:
			continue
		if line.is_middle(st):
			return line
	return null


func _refresh_hover(pos: Vector2) -> void:
	var st := network.station_at(pos, SNAP_RADIUS) if network != null else null
	if st != hover_station:
		hover_station = st
		if station_layer != null:
			station_layer.set_hover(st)


# ---------------------------------------------------------------------------
# 快照 / 撤销
# ---------------------------------------------------------------------------

func _push_undo() -> void:
	# 记录"本次编辑前"的线路几何：沿旧线路行驶的列车与浅色旧线都要用它
	for line in network.lines:
		line.edit_legacy_geometry = line.geometry.clone()
		line.edit_legacy_stops = line.stops.duplicate()
		line.edit_legacy_flips = line.bend_flips.duplicate()
		line.edit_legacy_valid = line.stops.size() >= 2 and not line.geometry.points.is_empty()
	_undo.append(_snapshot())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _snapshot() -> Dictionary:
	var lines_data := []
	for line in network.lines:
		var ids := []
		for st in line.stops:
			ids.append(st.id)
		lines_data.append({
			"id": line.id,
			"color": line.color,
			"stops": ids,
			"flips": line.bend_flips.duplicate(),
			"loop": line.is_loop,
		})
	return {"lines": lines_data, "next_line_id": network.next_line_id}


func _restore_pending_undo() -> void:
	if not _undo.is_empty():
		_apply_snapshot(_undo.pop_back())


func _drop_pending_undo() -> void:
	if not _undo.is_empty():
		_undo.pop_back()


func _apply_snapshot(snap: Dictionary) -> void:
	network.rescue_riders()
	network.lines.clear()
	var entries: Array = snap["lines"]
	for raw_entry in entries:
		var entry: Dictionary = raw_entry
		var line := MetroLine.new(int(entry["id"]), entry["color"])
		var stop_ids: Array = entry["stops"]
		for raw_id in stop_ids:
			var st := network.station_by_id(int(raw_id))
			if st != null:
				line.stops.append(st)
		var flips: Dictionary = entry.get("flips", {})
		line.bend_flips = flips
		line.is_loop = bool(entry.get("loop", false))
		line.rebuild()
		network.lines.append(line)
	network.next_line_id = int(snap["next_line_id"])
	network.touch()
	_hover_after_change()


func _reset_gesture() -> void:
	state = State.IDLE
	_draft_line = null
	_draft_is_new = false
	_draft_at_start = false
	_draft_base_len = 0
	_reorder_line = null
	_reorder_station = null
	_segment_line = null
	_segment_index = -1
	_segment_dragging = false
	_segment_removed = false
	_loop_candidate = false
	_fleet_line = null
	_fleet_train = null
	_fleet_dragging = false
	_fleet_target_line = null
	_fleet_target_train = null
	_stock_kind = ""
	_stock_hover_line = null
	_stock_hover_station = null
	_stock_hover_train = null
	_hover_dwell = 0.0
	_dwell_station = null
	_gesture_dirty = false
	_hover_after_change()


func _hover_after_change() -> void:
	if station_layer != null:
		station_layer.set_hover(hover_station)


# ---------------------------------------------------------------------------
# 预览绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	if network == null:
		return
	_draw_endpoint_handles()
	if hover_station != null and state == State.IDLE:
		draw_arc(hover_station.pos, Shape.STATION_RADIUS + 14.0, 0.0, TAU, 48,
			Color(0.16, 0.17, 0.19, 0.45), 2.5, true)
	if state == State.DRAFT and _draft_line != null and not _draft_line.stops.is_empty():
		_draw_draft_preview()
	if state == State.REORDER and _reorder_station != null:
		draw_dashed_line(_reorder_station.pos, cursor, Color(0.16, 0.17, 0.19, 0.55), 4.0, 8.0, true, true)
		draw_arc(_reorder_station.pos, Shape.STATION_RADIUS + 16.0, 0.0, TAU, 48,
			Color(0.16, 0.17, 0.19, 0.5), 3.0, true)
	if state == State.SEGMENT:
		_draw_segment_preview()
	if state == State.TRAIN and _fleet_dragging and _fleet_train != null:
		_draw_train_drag_preview()
	if state == State.CARRIAGE and _fleet_dragging:
		_draw_carriage_drag_preview()
	if state == State.STOCK:
		_draw_stock_preview()


func _draw_draft_preview() -> void:
	var tip: Station = _draft_line.stops[_draft_tip_index()]
	var to := hover_station.pos if hover_station != null else cursor
	var col := _draft_line.color
	var preview := LineGeometry.octilinear_segment(tip.pos, to)
	for i in range(preview.size() - 1):
		draw_dashed_line(preview[i], preview[i + 1], Color(col, 0.9), 8.0, 14.0, true, true)
	draw_circle(to, 7.0, Color(col, 0.95), true, -1.0, true)
	if _loop_candidate and _draft_line != null and _draft_line.stops.size() >= 3:
		var opposite: Station
		if _draft_at_start:
			opposite = _draft_line.stops[_draft_line.stops.size() - 1]
		else:
			opposite = _draft_line.stops[0]
		draw_arc(opposite.pos, Shape.STATION_RADIUS + 20.0, 0.0, TAU, 48,
			Color(_draft_line.color, 0.9), 3.0, true)
	if _dwell_station != null and _hover_dwell > 0.0:
		var t: float = clampf(_hover_dwell / dwell_remove_time, 0.0, 1.0)
		draw_arc(_dwell_station.pos, Shape.STATION_RADIUS + 19.0, -PI * 0.5,
			-PI * 0.5 + TAU * t, 48, Color(0.84, 0.27, 0.27, 0.95), 4.0, true)


func _draw_segment_preview() -> void:
	var line := _segment_line
	if line == null or _segment_index < 0:
		return
	var endpoints := _segment_endpoint_stations(line, _segment_index)
	if endpoints.size() != 2:
		return
	var a := endpoints[0].pos
	var b := endpoints[1].pos
	var to := hover_station.pos if hover_station != null else cursor
	var col := Color(line.color, 0.55)
	var first := LineGeometry.octilinear_segment(a, to)
	for i in range(first.size() - 1):
		draw_dashed_line(first[i], first[i + 1], col, 5.0, 10.0, true, true)
	var second := LineGeometry.octilinear_segment(to, b)
	for i in range(second.size() - 1):
		draw_dashed_line(second[i], second[i + 1], col, 5.0, 10.0, true, true)
	draw_circle(to, 6.0, Color(line.color, 0.8), true, -1.0, true)
	if hover_station != null and not line.has_station(hover_station):
		draw_arc(hover_station.pos, Shape.STATION_RADIUS + 16.0, 0.0, TAU, 48,
			Color(0.24, 0.55, 0.35, 0.85), 3.0, true)


func _draw_train_drag_preview() -> void:
	var color: Color = _fleet_line.color if _fleet_line != null else Color("#555555")
	var body := Vector2(66.0, 34.0)
	draw_rect(Rect2(cursor - body * 0.5, body), Color(1.0, 1.0, 1.0, 0.55))
	draw_rect(Rect2(cursor - body * 0.5, body), Color(color, 0.85), false, 2.5)
	if _fleet_target_line != null and _fleet_target_line.geometry.is_drawable():
		var offset := _fleet_target_line.geometry.nearest_distance(cursor)
		var point := _fleet_target_line.geometry.sample(offset).origin
		draw_arc(point, 26.0, 0.0, TAU, 40, Color(_fleet_target_line.color, 0.65), 3.0, true)


func _draw_carriage_drag_preview() -> void:
	var color: Color = _fleet_line.color if _fleet_line != null else Color("#555555")
	var size := TrainView.CARRIAGE_BODY
	var poly := DrawUtil.rounded_rect(Rect2(cursor - size * 0.5, size), size.y * 0.5, 8)
	draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.65))
	draw_polyline(DrawUtil.closed(poly), Color(color, 0.9), 2.5, true)
	if _fleet_target_train != null:
		for line in network.lines:
			if line.geometry.is_drawable() and line.trains.has(_fleet_target_train):
				var point := line.geometry.sample(_fleet_target_train.dist).origin
				draw_arc(point, 24.0, 0.0, TAU, 40, Color(line.color, 0.7), 3.0, true)
				break


func _draw_endpoint_handles() -> void:
	for line in network.lines:
		if line.stops.size() < 2:
			continue
		for at_start in [true, false]:
			var hp := _handle_world_position(line, at_start)
			draw_circle(hp, 9.5, Color.WHITE, true, -1.0, true)
			draw_arc(hp, 9.5, 0.0, TAU, 32, Color(line.color, 0.95), 3.5, true)
			if line.is_loop:
				# 环线的首末手柄落在接环处：中心小点区分"起点/终点"
				draw_circle(hp, 2.6, Color(line.color, 0.9), true, -1.0, true)


## 不在场景树里时（单元测试直接 new 出来）跳过重绘请求。
func _request_redraw() -> void:
	if is_inside_tree():
		queue_redraw()
