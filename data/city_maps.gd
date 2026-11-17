class_name CityMaps
extends RefCounted
## 城市地图注册表：7 张手写的风格化城市河道布局。
## 说明：河道走向参考真实城市（泰晤士河 / 塞纳河 / 哈德逊河 / 施普雷河 / 隅田川 / 黄浦江），
## 但为玩法与可读性做了简化，不是精确地理数据。

const WORLD_SIZE := Vector2(1920, 1080)

static var _cache: Array[CityMap] = []


static func all() -> Array[CityMap]:
	if _cache.is_empty():
		_cache = _build_all()
	return _cache


static func get_city(city_id: String) -> CityMap:
	for city in all():
		if city.id == city_id:
			return city
	return all()[0]


static func index_of(city_id: String) -> int:
	var cities := all()
	for i in cities.size():
		if cities[i].id == city_id:
			return i
	return 0


static func default_city_id() -> String:
	return "paper"


## 中心线 → 河道多边形（两侧偏移后闭合）。
static func band(centerline: PackedVector2Array, width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var count := centerline.size()
	for i in count:
		var previous: Vector2 = centerline[maxi(0, i - 1)]
		var next_point: Vector2 = centerline[mini(count - 1, i + 1)]
		var direction := (next_point - previous).normalized()
		if direction.length() < 0.001:
			direction = Vector2.RIGHT
		var normal := Vector2(-direction.y, direction.x)
		left.append(centerline[i] + normal * width * 0.5)
		right.append(centerline[i] - normal * width * 0.5)
	var poly := PackedVector2Array()
	for point in left:
		poly.append(point)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly


static func _build_all() -> Array[CityMap]:
	var cities: Array[CityMap] = []
	cities.append(_make({
		"id": "paper",
		"name_zh": "纸城",
		"name_en": "Paper City",
		"rivers": [
			band(PackedVector2Array([
				Vector2(1190, 80), Vector2(1260, 300), Vector2(1180, 520),
				Vector2(1290, 760), Vector2(1230, 1000),
			]), 192.0),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))
	cities.append(_make({
		"id": "london",
		"name_zh": "伦敦",
		"name_en": "London",
		"rivers": [
			band(PackedVector2Array([
				Vector2(-40, 700), Vector2(360, 660), Vector2(700, 720),
				Vector2(1010, 640), Vector2(1320, 700), Vector2(1640, 630),
				Vector2(1960, 680),
			]), 130.0),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))
	cities.append(_make({
		"id": "paris",
		"name_zh": "巴黎",
		"name_en": "Paris",
		"rivers": [
			band(PackedVector2Array([
				Vector2(-40, 560), Vector2(380, 520), Vector2(660, 600),
				Vector2(960, 540), Vector2(1260, 600), Vector2(1560, 540),
				Vector2(1960, 570),
			]), 104.0),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))
	cities.append(_make({
		"id": "newyork",
		"name_zh": "纽约",
		"name_en": "New York",
		"rivers": [
			band(PackedVector2Array([
				Vector2(600, -40), Vector2(648, 300), Vector2(580, 520),
				Vector2(650, 760), Vector2(596, 1120),
			]), 140.0),
			band(PackedVector2Array([
				Vector2(1240, -40), Vector2(1320, 320), Vector2(1276, 560),
				Vector2(1380, 800), Vector2(1336, 1120),
			]), 120.0),
		],
		"lines": 4,
		"trains": 4,
		"bridges": 3,
	}))
	cities.append(_make({
		"id": "berlin",
		"name_zh": "柏林",
		"name_en": "Berlin",
		"rivers": [
			band(PackedVector2Array([
				Vector2(-40, 480), Vector2(420, 520), Vector2(720, 470),
				Vector2(1020, 540), Vector2(1320, 480), Vector2(1620, 530),
				Vector2(1960, 500),
			]), 100.0),
			band(PackedVector2Array([
				Vector2(820, 520), Vector2(860, 700), Vector2(800, 900),
				Vector2(840, 1120),
			]), 62.0),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 3,
	}))
	cities.append(_make({
		"id": "tokyo",
		"name_zh": "东京",
		"name_en": "Tokyo",
		"rivers": [
			band(PackedVector2Array([
				Vector2(1120, -40), Vector2(1180, 320), Vector2(1120, 540),
				Vector2(1220, 760), Vector2(1180, 1120),
			]), 110.0),
			PackedVector2Array([
				Vector2(1440, 1120), Vector2(1520, 840), Vector2(1740, 780),
				Vector2(1860, 820), Vector2(1860, 1120),
			]),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))
	cities.append(_make({
		"id": "shanghai",
		"name_zh": "上海",
		"name_en": "Shanghai",
		"rivers": [
			band(PackedVector2Array([
				Vector2(1080, -40), Vector2(1240, 300), Vector2(1180, 520),
				Vector2(1380, 700), Vector2(1450, 900), Vector2(1500, 1120),
			]), 150.0),
			band(PackedVector2Array([
				Vector2(-40, 430), Vector2(320, 450), Vector2(600, 420),
				Vector2(820, 460), Vector2(1160, 470),
			]), 70.0),
		],
		"lines": 4,
		"trains": 4,
		"bridges": 3,
	}))
	return cities


static func _make(spec: Dictionary) -> CityMap:
	var city := CityMap.new()
	city.id = String(spec["id"])
	city.name_zh = String(spec["name_zh"])
	city.name_en = String(spec["name_en"])
	city.start_lines = int(spec.get("lines", 3))
	city.start_trains = int(spec.get("trains", 3))
	city.start_bridges = int(spec.get("bridges", 2))
	city.rivers.clear()
	var rivers: Array = spec["rivers"]
	for river in rivers:
		city.rivers.append(river)
	return city
