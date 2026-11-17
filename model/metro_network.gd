class_name MetroNetwork
extends RefCounted
## 线路网络：站点 + 线路 + 列车资源的唯一事实来源。
## 变更后调 touch()：刷新 station.line_ids 缓存并 bump version，视图/寻路据此重建。

signal station_added(station: Station)
signal line_added(line: MetroLine)
signal line_removed(line_id: int)

var level: LevelData
var stations: Array[Station] = []
var lines: Array[MetroLine] = []
var next_station_id: int = 0
var next_line_id: int = 0
var version: int = 0


func _init(p_level: LevelData = null) -> void:
	level = p_level if p_level != null else LevelData.new()


func add_station(pos: Vector2, shape_kind: int) -> Station:
	var st := Station.new(next_station_id, shape_kind, pos)
	next_station_id += 1
	stations.append(st)
	touch()
	station_added.emit(st)
	return st


## 新建空线路（选择尚未被占用的调色板颜色；全部占用时才回到顺序分配）。
func create_line() -> MetroLine:
	var color: Color = Color("#555555")
	if level != null and not level.line_colors.is_empty():
		var used := {}
		for existing in lines:
			used[existing.color] = true
		var picked := false
		for candidate in level.line_colors:
			if not used.has(candidate):
				color = candidate
				picked = true
				break
		if not picked:
			color = level.line_colors[lines.size() % level.line_colors.size()]
	var line := MetroLine.new(next_line_id, color)
	next_line_id += 1
	lines.append(line)
	touch()
	line_added.emit(line)
	return line


func remove_line(line: MetroLine) -> void:
	if line == null:
		return
	_rescue_line_riders(line)
	lines.erase(line)
	touch()
	line_removed.emit(line.id)


func line_by_id(line_id: int) -> MetroLine:
	for line in lines:
		if line.id == line_id:
			return line
	return null


## 半径内最近的站点（拾取用）。
func station_at(pos: Vector2, radius: float) -> Station:
	var best: Station = null
	var best_dist := radius
	for st in stations:
		var d := pos.distance_to(st.pos)
		if d <= best_dist:
			best_dist = d
			best = st
	return best


func nearest_station(pos: Vector2) -> Station:
	var best: Station = null
	var best_dist := INF
	for st in stations:
		var d := pos.distance_squared_to(st.pos)
		if d < best_dist:
			best_dist = d
			best = st
	return best


func station_by_id(station_id: int) -> Station:
	for st in stations:
		if st.id == station_id:
			return st
	return null


func available_lines() -> int:
	if level == null:
		return 0
	return maxi(0, level.start_lines - lines.size())


func train_count() -> int:
	var total := 0
	for line in lines:
		total += line.trains.size()
	return total


func available_trains() -> int:
	if level == null:
		return 0
	return maxi(0, level.start_trains - train_count())


func total_waiting() -> int:
	var total := 0
	for st in stations:
		total += st.waiting.size()
	return total


func total_carriages() -> int:
	var total := 0
	for line in lines:
		total += line.carriages()
	return total


# ---------------------------------------------------------------------------
# 水域 / 桥隧
# ---------------------------------------------------------------------------

## 已使用的桥隧数量 = 所有线路穿过河道的段数之和。
func used_bridges() -> int:
	if level == null or level.rivers.is_empty():
		return 0
	var total := 0
	for line in lines:
		total += line_bridge_count(line)
	return total


func available_bridges() -> int:
	if level == null:
		return 0
	return maxi(0, level.start_bridges - used_bridges())


func line_bridge_count(line: MetroLine) -> int:
	if level == null or level.rivers.is_empty():
		return 0
	var count := 0
	for i in range(line.stops.size() - 1):
		var a: Vector2 = line.stops[i].pos
		var b: Vector2 = line.stops[i + 1].pos
		if segment_crosses_water(a, b, line.is_segment_flipped(i)):
			count += 1
	return count


## 两站之间的八向折线是否穿过任意河道（考虑该段的弯曲翻转）。
func segment_crosses_water(a: Vector2, b: Vector2, flipped: bool = false) -> bool:
	if level == null or level.rivers.is_empty():
		return false
	var path := LineGeometry.octilinear_segment(a, b, flipped)
	for i in range(path.size() - 1):
		for river in level.rivers:
			if _segment_hits_polygon(path[i], path[i + 1], river):
				return true
	return false


func is_point_in_water(p: Vector2) -> bool:
	if level == null:
		return false
	for river in level.rivers:
		if river.size() >= 3 and Geometry2D.is_point_in_polygon(p, river):
			return true
	return false


## 点到河道的距离（在河道内返回 0）。
func water_distance(p: Vector2) -> float:
	if level == null or level.rivers.is_empty():
		return INF
	var best := INF
	for river in level.rivers:
		if river.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(p, river):
			return 0.0
		for i in river.size():
			var a: Vector2 = river[i]
			var b: Vector2 = river[(i + 1) % river.size()]
			best = minf(best, _distance_to_segment(p, a, b))
	return best


func _segment_hits_polygon(a: Vector2, b: Vector2, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
		return true
	for i in poly.size():
		var c: Vector2 = poly[i]
		var d: Vector2 = poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return true
	return false


func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 撤销 / 重建线路前调用：把车上乘客放回最近站台，避免"删线时乘客蒸发"。
func rescue_riders() -> void:
	for line in lines:
		_rescue_line_riders(line)


func touch() -> void:
	version += 1
	_rebuild_station_lines()


func _rebuild_station_lines() -> void:
	for st in stations:
		st.line_ids.clear()
	for line in lines:
		for st in line.stops:
			if not st.line_ids.has(line.id):
				st.line_ids.append(line.id)


func _rescue_line_riders(line: MetroLine) -> void:
	for train in line.trains:
		if train.riders.is_empty():
			continue
		var pos: Vector2 = Vector2.ZERO
		if not line.stops.is_empty():
			pos = line.geometry.sample(train.dist).origin
		var target := nearest_station(pos)
		if target == null:
			continue
		for passenger in train.riders:
			target.waiting.append(passenger)
		train.riders.clear()
