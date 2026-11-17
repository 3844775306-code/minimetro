class_name MetroNetwork
extends RefCounted
## 线路网络：站点 + 线路的唯一事实来源。
## 变更后调 touch()：刷新 station.lines 缓存并 bump version，视图据此重绘。

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


## 新建空线路（颜色按创建顺序分配）。是否允许由调用方用 available_lines() 判断。
func create_line() -> MetroLine:
	var color: Color = Color("#555555")
	if level != null and not level.line_colors.is_empty():
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
	lines.erase(line)
	touch()
	line_removed.emit(line.id)


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


func available_lines() -> int:
	if level == null:
		return 0
	return maxi(0, level.start_lines - lines.size())


func station_by_id(station_id: int) -> Station:
	for st in stations:
		if st.id == station_id:
			return st
	return null


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
