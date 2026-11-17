class_name MetroLine
extends RefCounted
## 一条线路：颜色 + 有序站点 + 每段折线弯曲方向 + 车厢数 + 列车 + 几何缓存。
## 所有"结构变更"都必须 rebuild()，否则视图与列车会读到旧几何。

var id: int = 0
var color: Color = Color.WHITE
var stops: Array[Station] = []

## 每条线段是否翻转弯曲方向（key = LineGeometry.segment_key(起点 id, 终点 id)）。
var bend_flips := {}

## 环线：末站与首站相连，列车沿着环单向循环。
var is_loop := false

## 手动编辑前的旧几何/旧站序：供"正在被修改的线路"上的列车沿原线行驶完。
var edit_legacy_geometry: LineGeometry = null
var edit_legacy_stops: Array[Station] = []
var edit_legacy_valid := false

## 这条线上的列车（由 Simulation 负责投放 / 回收，也可被玩家拖动换线）。
var trains: Array[Train] = []

var geometry := LineGeometry.new()
var version: int = 0


func _init(p_id: int = 0, p_color: Color = Color.WHITE) -> void:
	id = p_id
	color = p_color


func rebuild() -> void:
	geometry.build(stops, bend_flips, is_loop)
	version += 1


## 翻转第 segment 段（stops[segment] -> stops[segment + 1]）的弯曲方向。
func flip_segment_by_index(segment: int) -> void:
	if segment < 0 or segment + 1 >= stops.size():
		return
	flip_segment(stops[segment], stops[segment + 1])


func flip_segment(a: Station, b: Station) -> void:
	var key := LineGeometry.segment_key(a.id, b.id)
	if bend_flips.has(key):
		bend_flips.erase(key)
	else:
		bend_flips[key] = true
	rebuild()


func is_segment_flipped(segment: int) -> bool:
	if segment < 0 or segment + 1 >= stops.size():
		return false
	return bend_flips.has(LineGeometry.segment_key(stops[segment].id, stops[segment + 1].id))


func add_stop(st: Station) -> void:
	if st == null:
		return
	stops.append(st)
	rebuild()


func prepend_stop(st: Station) -> void:
	if st == null:
		return
	stops.push_front(st)
	rebuild()


func insert_stop(index: int, st: Station) -> void:
	if st == null:
		return
	stops.insert(clampi(index, 0, stops.size()), st)
	rebuild()


func remove_tail() -> void:
	if stops.is_empty():
		return
	stops.pop_back()
	rebuild()


func remove_head() -> void:
	if stops.is_empty():
		return
	stops.pop_front()
	rebuild()


func remove_stop_at(index: int) -> void:
	if index < 0 or index >= stops.size():
		return
	stops.remove_at(index)
	rebuild()


func has_station(st: Station) -> bool:
	return stops.has(st)


func index_of(st: Station) -> int:
	return stops.find(st)


## 端点：至少 2 站，且是该线首站或末站（环线没有端点）。
func is_endpoint(st: Station) -> bool:
	if is_loop or stops.size() < 2:
		return false
	return stops[0] == st or stops[stops.size() - 1] == st


## 中间站：不在首尾。
func is_middle(st: Station) -> bool:
	var i := index_of(st)
	return i > 0 and i < stops.size() - 1


func length() -> int:
	return stops.size()


## 本线所有列车上的车厢总数（车厢现在挂在单列车上）。
func carriages() -> int:
	var total := 0
	for train in trains:
		total += train.carriages
	return total


func total_capacity() -> int:
	var total := 0
	for train in trains:
		total += train.capacity
	return total


func handle_position(at_start: bool) -> Vector2:
	return geometry.handle_position(at_start)
