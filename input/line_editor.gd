class_name LineEditor
extends Node2D
## 画线手势控制器（M1 核心）。
##
## 交互：
##   · 按住车站拖拽 → 新建线路；经过其他站会即时接线（连续画线）
##   · 拖回上一站 → 回退一段
##   · 按住线路端点的小圆手柄 → 从该端继续延伸
##   · 按住线路中间的车站拖动 → 调整站序
##   · 右键 / Esc → 取消本次手势；Ctrl+Z → 撤销（整次手势为单位）
##
## 状态机与数据分离：手势只改 MetroNetwork 与 MetroLine，本节点负责拾取、预览、
## 快照/撤销。begin_gesture / move_gesture / end_gesture 是公开 API，测试直接调用它们。

signal toast_requested(message: String)

enum State { IDLE, DRAFT, REORDER }

const SNAP_RADIUS := 32.0
const HANDLE_HIT_RADIUS := 24.0
const HANDLE_DISTANCE := 30.0
const REORDER_SNAP := 52.0
const REORDER_DEADZONE := 9.0
const SWAP_COOLDOWN := 0.15
const UNDO_LIMIT := 40

var network: MetroNetwork = null
var level: LevelData = null
var station_layer: StationLayer = null

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
			cancel_gesture()


func _process(delta: float) -> void:
	if _swap_cooldown > 0.0:
		_swap_cooldown = maxf(0.0, _swap_cooldown - delta)
	_request_redraw()


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
	_refresh_hover(pos)

	var handle_line := _handle_at(pos)
	if handle_line != null:
		_begin_extend(handle_line)
		return true

	var st := network.station_at(pos, SNAP_RADIUS)
	if st == null:
		_dragging = false
		state = State.IDLE
		_request_redraw()
		return false

	var middle_line := _middle_line_of(st)
	if middle_line != null:
		_begin_reorder(middle_line, st)
		return true

	return _begin_new_line(st)


func move_gesture(pos: Vector2) -> void:
	if not _dragging:
		return
	cursor = pos
	_refresh_hover(pos)
	match state:
		State.DRAFT:
			_draft_update()
		State.REORDER:
			_reorder_update()
	_request_redraw()


func end_gesture(pos: Vector2) -> void:
	_dragging = false
	cursor = pos
	if state == State.DRAFT:
		var too_short := _draft_line == null or _draft_line.stops.size() < 2
		if too_short:
			_restore_pending_undo()
		elif not _gesture_dirty:
			_drop_pending_undo()
	elif state == State.REORDER:
		if not _gesture_dirty:
			_drop_pending_undo()
	_reset_gesture()
	_request_redraw()


func cancel_gesture() -> void:
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
# 手势内部实现
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
	var tip_index := _draft_tip_index()
	var tip: Station = _draft_line.stops[tip_index]
	if hover_station == tip:
		return
	if _draft_line.has_station(hover_station):
		var back_index := tip_index + (-1 if not _draft_at_start else 1)
		var stops := _draft_line.stops
		if back_index >= 0 and back_index < stops.size() and stops[back_index] == hover_station:
			_retract()
		return
	_extend_with(hover_station)


func _draft_tip_index() -> int:
	return 0 if _draft_at_start else _draft_line.stops.size() - 1


func _extend_with(st: Station) -> void:
	if _draft_at_start:
		_draft_line.prepend_stop(st)
	else:
		_draft_line.add_stop(st)
	network.touch()
	_gesture_dirty = true


func _retract() -> void:
	var min_len := _draft_base_len if not _draft_is_new else 1
	if _draft_line.stops.size() <= min_len:
		return
	if _draft_at_start:
		_draft_line.remove_head()
	else:
		_draft_line.remove_tail()
	network.touch()
	_gesture_dirty = true


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
			var hp := line.geometry.handle_position(at_start, HANDLE_DISTANCE)
			if pos.distance_to(hp) <= HANDLE_HIT_RADIUS:
				_handle_at_start = at_start
				return line
	return null


## 若不是端点、且在某条线的中间，则返回那条线（用于重排）。
func _middle_line_of(st: Station) -> MetroLine:
	for line in network.lines:
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
	_undo.append(_snapshot())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _snapshot() -> Dictionary:
	var lines_data := []
	for line in network.lines:
		var ids := []
		for st in line.stops:
			ids.append(st.id)
		lines_data.append({"id": line.id, "color": line.color, "stops": ids})
	return {"lines": lines_data, "next_line_id": network.next_line_id}


func _restore_pending_undo() -> void:
	if not _undo.is_empty():
		_apply_snapshot(_undo.pop_back())


func _drop_pending_undo() -> void:
	if not _undo.is_empty():
		_undo.pop_back()


func _apply_snapshot(snap: Dictionary) -> void:
	network.lines.clear()
	for entry in snap["lines"]:
		var line := MetroLine.new(int(entry["id"]), entry["color"])
		for sid in entry["stops"]:
			var st := network.station_by_id(int(sid))
			if st != null:
				line.stops.append(st)
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
	if hover_station != null and state != State.REORDER:
		draw_arc(hover_station.pos, Shape.STATION_RADIUS + 14.0, 0.0, TAU, 48,
			Color(0.16, 0.17, 0.19, 0.45), 2.5, true)
	if state == State.DRAFT and _draft_line != null and not _draft_line.stops.is_empty():
		var tip: Station = _draft_line.stops[_draft_tip_index()]
		var to := hover_station.pos if hover_station != null else cursor
		var col := _draft_line.color
		draw_dashed_line(tip.pos, to, Color(col, 0.9), 8.0, 14.0, true, true)
		draw_circle(to, 7.0, Color(col, 0.95), true, -1.0, true)
	elif state == State.REORDER and _reorder_station != null:
		draw_dashed_line(_reorder_station.pos, cursor, Color(0.16, 0.17, 0.19, 0.55), 4.0, 8.0, true, true)
		draw_arc(_reorder_station.pos, Shape.STATION_RADIUS + 16.0, 0.0, TAU, 48,
			Color(0.16, 0.17, 0.19, 0.5), 3.0, true)


func _draw_endpoint_handles() -> void:
	for line in network.lines:
		if line.stops.size() < 2:
			continue
		for at_start in [true, false]:
			var hp := line.geometry.handle_position(at_start, HANDLE_DISTANCE)
			draw_circle(hp, 6.5, Color.WHITE, true, -1.0, true)
			draw_arc(hp, 6.5, 0.0, TAU, 24, Color(line.color, 0.95), 3.0, true)


## 不在场景树里时（单元测试直接 new 出来）跳过重绘请求。
func _request_redraw() -> void:
	if is_inside_tree():
		queue_redraw()
