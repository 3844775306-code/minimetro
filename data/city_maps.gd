class_name CityMaps
extends RefCounted
## 城市地图注册表。
## 河道中心线采用真实城市河道的 WGS84 经纬度简化坐标（公开地理常识数据），
## 用等距圆柱投影映射到 1920×1080 世界坐标；宽度按玩法放大，不是精确测绘图。
## 纸城是虚构地图。

const WORLD_SIZE := Vector2(1920, 1080)
## 城市水位可用的绘图区域（留出陆地圆角与站点边距）。
const MAP_AREA := Rect2(170.0, 130.0, 1580.0, 820.0)

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


## 中心线 → 河道多边形。先做 Catmull-Rom 平滑，再用 Geometry2D 圆角描边：
## 弯曲处更顺、两端是圆头，不会出现手写偏移在急弯处的自交尖角。
static func band(centerline: PackedVector2Array, width: float) -> PackedVector2Array:
	if centerline.size() < 2:
		return PackedVector2Array()
	var center := smooth_centerline(centerline, 8)
	var offset: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		center, width * 0.5, Geometry2D.JOIN_ROUND
	)
	if offset.is_empty():
		return _raw_band(centerline, width)
	# 极端自交时可能切成多块，取面积最大的一块作为河面
	var best: PackedVector2Array = offset[0]
	var best_area := absf(_signed_area(best))
	for i in range(1, offset.size()):
		var area := absf(_signed_area(offset[i]))
		if area > best_area:
			best = offset[i]
			best_area = area
	return best


## Catmull-Rom 平滑：把折线变成每段 steps 个采样点的曲线。
static func smooth_centerline(points: PackedVector2Array, steps: int) -> PackedVector2Array:
	if points.size() < 3 or steps <= 0:
		return points
	var out := PackedVector2Array()
	var count := points.size()
	for i in range(count - 1):
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, count - 1)]
		for s in steps:
			var t := float(s) / float(steps)
			out.append(_catmull_rom(p0, p1, p2, p3, t))
	out.append(points[count - 1])
	return out


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


## 无平滑的兜底：手工两侧偏移（Geometry2D 不可用时）。
static func _raw_band(centerline: PackedVector2Array, width: float) -> PackedVector2Array:
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


static func _signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		total += p.x * q.y - q.x * p.y
	return total * 0.5


## 把经纬度 bbox 按真实宽高比（含纬度余弦修正）拟合到 MAP_AREA。
static func fit_geo(bbox: Rect2, latitude: float) -> Rect2:
	var geo_width := bbox.size.x * cos(deg_to_rad(latitude))
	var geo_height := bbox.size.y
	if geo_width <= 0.0 or geo_height <= 0.0:
		return MAP_AREA
	var aspect := geo_width / geo_height
	var area := MAP_AREA
	var size: Vector2
	if aspect > area.size.x / area.size.y:
		size = Vector2(area.size.x, area.size.x / aspect)
	else:
		size = Vector2(area.size.y * aspect, area.size.y)
	return Rect2(area.position + (area.size - size) * 0.5, size)


## 经纬度点列 → 世界坐标点列。
static func project(points: Array, bbox: Rect2, target: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for raw in points:
		var point: Vector2 = raw
		var tx := (point.x - bbox.position.x) / bbox.size.x
		var ty := (point.y - bbox.position.y) / bbox.size.y
		out.append(Vector2(
			target.position.x + tx * target.size.x,
			target.position.y + (1.0 - ty) * target.size.y
		))
	return out


## 真实河道的中心线（经纬度）→ 世界坐标的河道多边形。
## extend_to_edge=true 时两端顺着走向延长出画面（干流）；运河水道用 false。
static func geo_band(points: Array, bbox: Rect2, width: float, extend_to_edge: bool = true) -> PackedVector2Array:
	var target := fit_geo(bbox, bbox.position.y + bbox.size.y * 0.5)
	var centerline := project(points, bbox, target)
	if extend_to_edge:
		centerline = extend_ends(centerline, target)
	return band(centerline, width)


## 把折线两端沿端点方向延长（延长量约为绘图区对角线的 1/4），让水流穿出画面。
static func extend_ends(centerline: PackedVector2Array, target: Rect2) -> PackedVector2Array:
	if centerline.size() < 2:
		return centerline
	var extension := target.size.length() * 0.25
	var out := PackedVector2Array()
	var start_dir := (centerline[0] - centerline[1]).normalized()
	out.append(centerline[0] + start_dir * extension)
	for point in centerline:
		out.append(point)
	var last := centerline.size() - 1
	var end_dir := (centerline[last] - centerline[last - 1]).normalized()
	out.append(centerline[last] + end_dir * extension)
	return out


## 真实水域（海湾等）的经纬度轮廓 → 世界坐标多边形。
static func geo_polygon(points: Array, bbox: Rect2) -> PackedVector2Array:
	return project(points, bbox, fit_geo(bbox, bbox.position.y + bbox.size.y * 0.5))


static func _build_all() -> Array[CityMap]:
	var cities: Array[CityMap] = []
	# 纸城：虚构河道（默认教学图）
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

	# 伦敦：泰晤士河（WGS84 简化中心线，西 → 东）
	var london_box := Rect2(-0.280, 51.440, 0.340, 0.100)
	cities.append(_make({
		"id": "london",
		"name_zh": "伦敦",
		"name_en": "London",
		"rivers": [geo_band([
			Vector2(-0.235, 51.487), Vector2(-0.220, 51.470), Vector2(-0.205, 51.462),
			Vector2(-0.190, 51.458), Vector2(-0.175, 51.465), Vector2(-0.160, 51.475),
			Vector2(-0.145, 51.482), Vector2(-0.130, 51.493), Vector2(-0.115, 51.502),
			Vector2(-0.095, 51.508), Vector2(-0.075, 51.506), Vector2(-0.045, 51.501),
			Vector2(-0.015, 51.496), Vector2(0.005, 51.482), Vector2(0.035, 51.488),
			Vector2(0.060, 51.495),
		], london_box, 120.0)],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))

	# 巴黎：塞纳河（东 → 西）
	var paris_box := Rect2(2.220, 48.810, 0.200, 0.070)
	cities.append(_make({
		"id": "paris",
		"name_zh": "巴黎",
		"name_en": "Paris",
		"rivers": [geo_band([
			Vector2(2.400, 48.830), Vector2(2.385, 48.838), Vector2(2.370, 48.845),
			Vector2(2.355, 48.852), Vector2(2.340, 48.857), Vector2(2.325, 48.862),
			Vector2(2.310, 48.864), Vector2(2.295, 48.863), Vector2(2.280, 48.860),
			Vector2(2.265, 48.855), Vector2(2.250, 48.848), Vector2(2.235, 48.840),
		], paris_box, 84.0)],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))

	# 纽约：哈德逊河（西）+ 东河（东），中间是曼哈顿
	var ny_box := Rect2(-74.060, 40.680, 0.160, 0.200)
	cities.append(_make({
		"id": "newyork",
		"name_zh": "纽约",
		"name_en": "New York",
		"rivers": [
			geo_band([
				Vector2(-74.015, 40.700), Vector2(-74.012, 40.715), Vector2(-74.008, 40.730),
				Vector2(-74.003, 40.745), Vector2(-73.998, 40.760), Vector2(-73.990, 40.775),
				Vector2(-73.978, 40.795), Vector2(-73.965, 40.815), Vector2(-73.950, 40.835),
				Vector2(-73.938, 40.855),
			], ny_box, 104.0),
			geo_band([
				Vector2(-73.995, 40.700), Vector2(-73.985, 40.702), Vector2(-73.978, 40.708),
				Vector2(-73.970, 40.720), Vector2(-73.965, 40.735), Vector2(-73.960, 40.750),
				Vector2(-73.952, 40.765), Vector2(-73.945, 40.780), Vector2(-73.938, 40.795),
			], ny_box, 78.0),
		],
		"lines": 3,
		"trains": 4,
		"bridges": 3,
	}))

	# 柏林：施普雷河（东 → 西）+ 南部运河（Landwehrkanal，两端接回施普雷河）
	var berlin_box := Rect2(13.240, 52.460, 0.360, 0.090)
	cities.append(_make({
		"id": "berlin",
		"name_zh": "柏林",
		"name_en": "Berlin",
		"rivers": [
			geo_band([
				Vector2(13.570, 52.450), Vector2(13.530, 52.470), Vector2(13.500, 52.490),
				Vector2(13.475, 52.500), Vector2(13.450, 52.508), Vector2(13.425, 52.512),
				Vector2(13.400, 52.517), Vector2(13.375, 52.521), Vector2(13.350, 52.525),
				Vector2(13.320, 52.528), Vector2(13.290, 52.533), Vector2(13.260, 52.535),
			], berlin_box, 74.0),
			geo_band([
				Vector2(13.375, 52.512), Vector2(13.365, 52.500), Vector2(13.355, 52.490),
				Vector2(13.360, 52.482), Vector2(13.380, 52.480), Vector2(13.400, 52.483),
				Vector2(13.420, 52.490), Vector2(13.415, 52.505),
			], berlin_box, 46.0, false),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 3,
	}))

	# 东京：隅田川（北 → 南）+ 东京湾东南水域
	var tokyo_box := Rect2(139.720, 35.580, 0.220, 0.210)
	cities.append(_make({
		"id": "tokyo",
		"name_zh": "东京",
		"name_en": "Tokyo",
		"rivers": [
			geo_band([
				Vector2(139.800, 35.770), Vector2(139.805, 35.755), Vector2(139.800, 35.740),
				Vector2(139.798, 35.725), Vector2(139.795, 35.710), Vector2(139.790, 35.695),
				Vector2(139.785, 35.680), Vector2(139.782, 35.665), Vector2(139.778, 35.650),
			], tokyo_box, 96.0),
			# 东京湾：东南角的大片水域，岸线弯向隅田川口，其余方向穿出画面
			geo_polygon([
				Vector2(139.795, 35.665), Vector2(139.850, 35.650), Vector2(139.910, 35.615),
				Vector2(139.980, 35.520), Vector2(139.860, 35.470), Vector2(139.720, 35.500),
				Vector2(139.700, 35.590), Vector2(139.740, 35.640),
			], tokyo_box),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))

	# 上海：黄浦江（南 → 北，陆家嘴弯）+ 苏州河（西 → 东汇入黄浦江）
	var shanghai_box := Rect2(121.320, 31.150, 0.240, 0.280)
	cities.append(_make({
		"id": "shanghai",
		"name_zh": "上海",
		"name_en": "Shanghai",
		"rivers": [
			geo_band([
				Vector2(121.465, 31.180), Vector2(121.470, 31.195), Vector2(121.472, 31.210),
				Vector2(121.475, 31.225), Vector2(121.482, 31.238), Vector2(121.490, 31.248),
				Vector2(121.497, 31.258), Vector2(121.503, 31.268), Vector2(121.505, 31.280),
				Vector2(121.500, 31.295), Vector2(121.492, 31.310), Vector2(121.480, 31.325),
				Vector2(121.468, 31.345), Vector2(121.455, 31.365), Vector2(121.443, 31.390),
			], shanghai_box, 112.0),
			geo_band([
				Vector2(121.360, 31.245), Vector2(121.390, 31.243), Vector2(121.420, 31.246),
				Vector2(121.445, 31.250), Vector2(121.465, 31.252), Vector2(121.485, 31.250),
				Vector2(121.497, 31.247),
			], shanghai_box, 52.0),
		],
		"lines": 3,
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