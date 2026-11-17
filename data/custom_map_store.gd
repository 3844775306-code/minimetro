class_name CustomMapStore
extends RefCounted
## 玩家自定义地图存储：user://custom_maps.json。
## 河流直接用多边形点列保存（编辑器已把中心线转成河道多边形），
## 因此分享/导入不需要重复计算，也不会依赖曲线算法版本。

const PATH := "user://custom_maps.json"
const MAX_MAPS := 24


static func load_maps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(PATH):
		return result
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return result
	var data: Dictionary = parsed
	var list: Variant = data.get("maps", [])
	if list is Array:
		for raw in list:
			if raw is Dictionary:
				var map: Dictionary = raw
				if _valid_map(map):
					result.append(map)
	return result


static func save_maps(maps: Array) -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "maps": maps}))
	file.close()
	return true


## 保存一张图；同 id 覆盖，否则追加。返回保存后的列表。
static func save_map(map: Dictionary) -> bool:
	var maps := load_maps()
	var found := false
	for i in maps.size():
		if String(maps[i].get("id", "")) == String(map.get("id", "")):
			maps[i] = map
			found = true
			break
	if not found:
		maps.append(map)
	while maps.size() > MAX_MAPS:
		maps.remove_at(0)
	return save_maps(maps)


static func delete_map(map_id: String) -> bool:
	var maps := load_maps()
	for i in range(maps.size() - 1, -1, -1):
		if String(maps[i].get("id", "")) == map_id:
			maps.remove_at(i)
	return save_maps(maps)


static func new_map(polygons: Array, width: float, name: String = "") -> Dictionary:
	var map := {
		"id": "custom_%d" % int(Time.get_ticks_usec()),
		"name_zh": name if name != "" else "自定义地图",
		"name_en": name if name != "" else "Custom Map",
		"rivers": _encode_polygons(polygons),
		"start_lines": 3,
		"start_trains": 3,
		"start_bridges": 2,
		"width": width,
	}
	return map


## 把保存的字典变成游戏可直接使用的 CityMap。
static func to_city_map(map: Dictionary) -> CityMap:
	var city := CityMap.new()
	city.id = String(map.get("id", ""))
	city.is_custom = true
	city.name_zh = String(map.get("name_zh", "自定义地图"))
	city.name_en = String(map.get("name_en", "Custom Map"))
	city.start_lines = int(map.get("start_lines", 3))
	city.start_trains = int(map.get("start_trains", 3))
	city.start_bridges = int(map.get("start_bridges", 2))
	city.rivers.clear()
	var encoded: Variant = map.get("rivers", [])
	if encoded is Array:
		for raw_poly in encoded:
			var points := _decode_polygon(raw_poly)
			if points.size() >= 3:
				city.rivers.append(points)
	return city


static func load_cities() -> Array[CityMap]:
	var cities: Array[CityMap] = []
	for map in load_maps():
		var city := to_city_map(map)
		if not city.id.is_empty() and not city.rivers.is_empty():
			cities.append(city)
	return cities


## 分享码：整张地图 JSON 的 Base64，方便复制/粘贴。
static func share_code(map: Dictionary) -> String:
	return Marshalls.utf8_to_base64(JSON.stringify(map))


static func decode_share(code: String) -> Dictionary:
	var cleaned := code.strip_edges()
	if cleaned.is_empty():
		return {}
	var text := Marshalls.base64_to_utf8(cleaned)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var map: Dictionary = parsed
	if not _valid_map(map):
		return {}
	return map


static func _valid_map(map: Dictionary) -> bool:
	if String(map.get("id", "")).is_empty():
		return false
	var rivers: Variant = map.get("rivers", [])
	if not (rivers is Array) or rivers.is_empty():
		return false
	for raw_poly in rivers:
		if _decode_polygon(raw_poly).size() < 3:
			return false
	return true


static func _encode_polygons(polygons: Array) -> Array:
	var out: Array = []
	for raw_poly in polygons:
		var points := PackedVector2Array()
		if raw_poly is PackedVector2Array:
			points = raw_poly
		elif raw_poly is Array:
			for p in raw_poly:
				if p is Vector2:
					points.append(p)
		if points.size() < 3:
			continue
		var encoded: Array = []
		for p in points:
			encoded.append([p.x, p.y])
		out.append(encoded)
	return out


static func _decode_polygon(raw_poly: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not (raw_poly is Array):
		return out
	for raw_point in raw_poly:
		if raw_point is Array and raw_point.size() >= 2:
			out.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	return out
