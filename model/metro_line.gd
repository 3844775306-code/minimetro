class_name MetroLine
extends RefCounted
## 一条线路：颜色 + 有序站点 + 几何缓存。
## 所有"结构变更"都必须 rebuild()，否则视图与列车会读到旧几何。

var id: int = 0
var color: Color = Color.WHITE
var stops: Array[Station] = []
var geometry := LineGeometry.new()
var version: int = 0


func _init(p_id: int = 0, p_color: Color = Color.WHITE) -> void:
	id = p_id
	color = p_color


func rebuild() -> void:
	geometry.build(stops)
	version += 1


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


func has_station(st: Station) -> bool:
	return stops.has(st)


func index_of(st: Station) -> int:
	return stops.find(st)


## 端点：至少 2 站，且是该线首站或末站。
func is_endpoint(st: Station) -> bool:
	if stops.size() < 2:
		return false
	return stops[0] == st or stops[stops.size() - 1] == st


## 中间站：不在首尾。
func is_middle(st: Station) -> bool:
	var i := index_of(st)
	return i > 0 and i < stops.size() - 1


func length() -> int:
	return stops.size()


func handle_position(at_start: bool) -> Vector2:
	return geometry.handle_position(at_start)
