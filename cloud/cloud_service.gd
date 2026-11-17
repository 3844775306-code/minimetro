extends Node
## 排行榜 / 云端成绩 / 地图大厅。
##
## 当前实现是"可离线运行的云端模拟器"：数据持久化在 user://cloud_sim.json，
## 并带有确定性的示例玩家/地图，方便在没有后端时直接体验排行榜与地图大厅。
## 真正联网时只需要把这几个方法替换为 HTTP API（提交/查询/下载地图），
## UI 与存档层不需要改。

const PATH := "user://cloud_sim.json"

var _data := {}


func _ready() -> void:
	load_data()


func load_data() -> void:
	_data = {}
	if FileAccess.file_exists(PATH):
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				_data = parsed
	if _data.is_empty():
		_seed()
		save_data()


func save_data() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_data))
	file.close()


func player_name() -> String:
	if is_inside_tree():
		var save_node := get_node_or_null("/root/Save")
		if save_node != null:
			return save_node.player_name()
	return "玩家"


## 最近 days 天（含今天）的日期，最新在前。
func recent_dates(days: int = 7) -> Array[String]:
	var out: Array[String] = []
	var now := Time.get_unix_time_from_system()
	for i in days:
		out.append(Time.get_date_string_from_unix_time(int(now - float(i) * 86400.0)))
	return out


func daily_leaderboard(date: String, limit: int = 8) -> Array[Dictionary]:
	if _data.is_empty():
		load_data()
	var all: Array = _data.get("daily", {}).get(date, [])
	var entries: Array[Dictionary] = []
	for raw in all:
		if raw is Dictionary:
			entries.append((raw as Dictionary).duplicate())
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0)))
	if entries.size() > limit:
		entries.resize(limit)
	return entries


func submit_daily(date: String, score: int) -> void:
	if date == "":
		return
	if _data.is_empty():
		load_data()
	var daily: Dictionary = _data.get("daily", {})
	var entries: Array = daily.get(date, [])
	var replaced := false
	for i in entries.size():
		if String(entries[i].get("name", "")) == player_name():
			entries[i] = {"name": player_name(), "score": score}
			replaced = true
			break
	if not replaced:
		entries.append({"name": player_name(), "score": score})
	daily[date] = entries
	_data["daily"] = daily
	save_data()


## 最近一周每日挑战榜：每天取前 per_day 名，拼成可显示的文本行。
func recent_daily_lines(days: int = 7, per_day: int = 3) -> Array[String]:
	var lines: Array[String] = []
	for date in recent_dates(days):
		var board := daily_leaderboard(date, per_day)
		var parts: Array[String] = []
		for entry in board:
			parts.append("%s %d" % [String(entry.get("name", "?")), int(entry.get("score", 0))])
		lines.append("%s   %s" % [date, "   ".join(parts) if not parts.is_empty() else "暂无成绩"])
	return lines


func best_leaderboard(mode_key: String, city_id: String, limit: int = 8) -> Array[Dictionary]:
	if _data.is_empty():
		load_data()
	var key := "%s|%s" % [mode_key, city_id]
	var all: Array = _data.get("best", {}).get(key, [])
	var entries: Array[Dictionary] = []
	for raw in all:
		if raw is Dictionary:
			entries.append((raw as Dictionary).duplicate())
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0)))
	if entries.size() > limit:
		entries.resize(limit)
	return entries


func submit_best(mode_key: String, city_id: String, score: int) -> void:
	if _data.is_empty():
		load_data()
	var best: Dictionary = _data.get("best", {})
	var key := "%s|%s" % [mode_key, city_id]
	var entries: Array = best.get(key, [])
	var replaced := false
	for i in entries.size():
		if String(entries[i].get("name", "")) == player_name():
			entries[i] = {"name": player_name(), "score": score}
			replaced = true
			break
	if not replaced:
		entries.append({"name": player_name(), "score": score})
	best[key] = entries
	_data["best"] = best
	save_data()


func maps(limit: int = 20) -> Array[Dictionary]:
	if _data.is_empty():
		load_data()
	var all: Array = _data.get("maps", [])
	var result: Array[Dictionary] = []
	for raw in all:
		if raw is Dictionary:
			var map: Dictionary = (raw as Dictionary).duplicate()
			result.append(map)
	if result.size() > limit:
		result.resize(limit)
	return result


func upload_map(map: Dictionary) -> bool:
	if _data.is_empty():
		load_data()
	if not map.has("rivers") or not (map["rivers"] is Array) or map["rivers"].is_empty():
		return false
	var maps_list: Array = _data.get("maps", [])
	var copy := map.duplicate(true)
	copy["author"] = player_name()
	copy["downloads"] = int(copy.get("downloads", 0))
	copy["uploaded_at"] = Time.get_datetime_string_from_system()
	var replaced := false
	for i in maps_list.size():
		if String(maps_list[i].get("id", "")) == String(copy.get("id", "")):
			maps_list[i] = copy
			replaced = true
			break
	if not replaced:
		maps_list.append(copy)
	_data["maps"] = maps_list
	save_data()
	return true


func download_map(map_id: String) -> Dictionary:
	if _data.is_empty():
		load_data()
	var maps_list: Array = _data.get("maps", [])
	for i in maps_list.size():
		if String(maps_list[i].get("id", "")) == map_id:
			var map: Dictionary = (maps_list[i] as Dictionary).duplicate(true)
			map["downloads"] = int(map.get("downloads", 0)) + 1
			maps_list[i] = map
			_data["maps"] = maps_list
			save_data()
			return map
	return {}


func _seed() -> void:
	var players := ["林间", "Alex", "小周", "Mika", "老王", "Nina", "Kai"]
	var daily := {}
	var dates := recent_dates(7)
	for d in dates:
		var entries: Array = []
		for i in players.size():
			var base := 18 + (absi(hash(d + players[i])) % 70)
			entries.append({"name": players[i], "score": base})
		daily[d] = entries
	var best := {}
	var official: Array[String] = []
	for city in CityMaps.all():
		if not city.is_custom:
			official.append(city.id)
	for mode in ["classic", "endless", "manager"]:
		for city_id in official:
			var entries: Array = []
			for i in players.size():
				var base := 20 + (absi(hash(mode + city_id + players[i])) % 90)
				entries.append({"name": players[i], "score": base})
			best["%s|%s" % [mode, city_id]] = entries
	_data = {"daily": daily, "best": best, "maps": _seed_maps()}


func _seed_maps() -> Array:
	var maps: Array = []
	var samples := [
		{"name": "双河小镇", "author": "林间", "line": PackedVector2Array([
			Vector2(240, 200), Vector2(680, 430), Vector2(1000, 300), Vector2(1500, 600),
			Vector2(2100, 430)])},
		{"name": "环形水湾", "author": "Alex", "line": PackedVector2Array([
			Vector2(400, 1100), Vector2(800, 700), Vector2(1400, 900), Vector2(1900, 500)])},
		{"name": "北方运河", "author": "小周", "line": PackedVector2Array([
			Vector2(300, 150), Vector2(700, 500), Vector2(1300, 420), Vector2(2000, 800)])},
	]
	for i in samples.size():
		var sample: Dictionary = samples[i]
		var river := CityMaps.editor_band(sample["line"], 110.0)
		var encoded: Array = []
		for p in river:
			encoded.append([p.x, p.y])
		maps.append({
			"id": "hall_%d" % (i + 1),
			"name_zh": String(sample["name"]),
			"name_en": String(sample["name"]),
			"author": String(sample["author"]),
			"downloads": 12 + i * 7,
			"rivers": [encoded],
			"start_lines": 3,
			"start_trains": 3,
			"start_bridges": 2,
			"width": 110.0,
		})
	return maps
