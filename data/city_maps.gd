class_name CityMaps
extends RefCounted
## 城市地图注册表。
## 河道中心线采用真实城市河道的 WGS84 经纬度简化坐标（公开地理常识数据），
## 用等距圆柱投影映射到 2400×1200 世界坐标；宽度按玩法放大，不是精确测绘图。
## 纸城是虚构地图。地图变大后每座城市都增加了更多水系（支流/运河/河流）。

const WORLD_SIZE := Vector2(2400, 1200)
## 城市水位可用的绘图区域（留出陆地圆角与站点边距）。
const MAP_AREA := Rect2(200.0, 160.0, 2000.0, 980.0)

static var _cache: Array[CityMap] = []


static func all() -> Array[CityMap]:
	if _cache.is_empty():
		_cache = _build_all()
		# 玩家自定义地图排在官方地图之后；同一 id 以官方为准
		for custom in CustomMapStore.load_cities():
			var duplicate := false
			for city in _cache:
				if city.id == custom.id:
					duplicate = true
					break
			if not duplicate:
				_cache.append(custom)
	return _cache


## 编辑器保存后清缓存，让模式菜单立刻看到新地图。
static func reload() -> void:
	_cache.clear()


static func get_city(city_id: String) -> CityMap:
	for city in all():
		if city.id == city_id:
			return city
	return all()[0]


static func index_of(city_id: String) -> int:
	for i in all().size():
		if all()[i].id == city_id:
			return i
	return 0


static func default_city_id() -> String:
	return "paper"


## 中心线 → 河道多边形。先做 Catmull-Rom 平滑，再用 Geometry2D 圆角描边：
## 弯曲处更顺、两端是圆头，不会出现手写偏移在急弯处的自交尖角。
static func band(centerline: PackedVector2Array, width: float) -> PackedVector2Array:
	if centerline.size() < 2:
		return PackedVector2Array()
	# 平滑步数降低 + 叠加蜿蜒，让河道更曲折、不要一条平滑的飘带；
	# 蜿蜒后再轻平滑一次，避免采样点处的硬折角。
	var center := smooth_centerline(centerline, 4)
	center = _meander(center, width)
	center = smooth_centerline(center, 2)
	var offset: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		center, width * 0.5, Geometry2D.JOIN_ROUND
	)
	if offset.is_empty():
		return _raw_band(centerline, width)
	var best: PackedVector2Array = offset[0]
	var best_area := absf(_signed_area(best))
	for i in range(1, offset.size()):
		var area := absf(_signed_area(offset[i]))
		if area > best_area:
			best = offset[i]
			best_area = area
	return best


## 沿河道法线叠加正弦位移，模拟自然的曲流/河湾。
static func _meander(center: PackedVector2Array, width: float) -> PackedVector2Array:
	if center.size() < 3 or width <= 0.0:
		return center
	# 振幅/波长控制在"河宽的一半"以内，避免曲流把河道自身挤成一个个水泡
	var amplitude := width * 0.16
	var wavelength := maxf(width * 2.6, 100.0)
	var phase := fmod(absf(center[0].x) * 0.021 + absf(center[0].y) * 0.017, TAU)
	var out := PackedVector2Array()
	var travelled := 0.0
	for i in center.size():
		if i > 0:
			travelled += center[i].distance_to(center[i - 1])
		var previous := center[maxi(i - 1, 0)]
		var next_point := center[mini(i + 1, center.size() - 1)]
		var direction := next_point - previous
		var normal := Vector2(-direction.y, direction.x)
		if normal.length() > 0.001:
			normal = normal.normalized()
		var offset := sin(travelled / wavelength * TAU + phase) * amplitude
		out.append(center[i] + normal * offset)
	return out


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


## 编辑器用的河道多边形：只做轻微平滑 + 等宽描边，不叠加随机曲流，
## 这样玩家画成什么样，河里就是什么样。
static func editor_band(centerline: PackedVector2Array, width: float) -> PackedVector2Array:
	if centerline.size() < 2 or width <= 0.0:
		return PackedVector2Array()
	var center := smooth_centerline(centerline, 3)
	var offset: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		center, width * 0.5, Geometry2D.JOIN_ROUND
	)
	if offset.is_empty():
		return _raw_band(centerline, width)
	var best: PackedVector2Array = offset[0]
	var best_area := absf(_signed_area(best))
	for i in range(1, offset.size()):
		var area := absf(_signed_area(offset[i]))
		if area > best_area:
			best = offset[i]
			best_area = area
	return best


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


## 真实水域（海湾等）的经纬度轮廓 → 世界坐标多边形。
static func geo_polygon(points: Array, bbox: Rect2) -> PackedVector2Array:
	return project(points, bbox, fit_geo(bbox, bbox.position.y + bbox.size.y * 0.5))


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


static func _build_all() -> Array[CityMap]:
	var cities: Array[CityMap] = []
	# 纸城：虚构河道（默认教学图）——主河 + 西侧支流 + 东南水湾
	cities.append(_make({
		"id": "paper",
		"name_zh": "纸城",
		"name_en": "Paper City",
		"rivers": [
			band(PackedVector2Array([
				Vector2(1500, 20), Vector2(1610, 170), Vector2(1465, 330),
				Vector2(1625, 500), Vector2(1480, 680), Vector2(1600, 860),
				Vector2(1450, 1020), Vector2(1540, 1180),
			]), 190.0),
			band(PackedVector2Array([
				Vector2(-40, 760), Vector2(250, 690), Vector2(520, 820),
				Vector2(780, 730), Vector2(1060, 860), Vector2(1300, 770),
				Vector2(1510, 790),
			]), 90.0),
			band(PackedVector2Array([
				Vector2(1800, 1220), Vector2(1880, 1050), Vector2(2020, 980),
				Vector2(2140, 1070), Vector2(2240, 930), Vector2(2360, 1060),
			]), 130.0),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))

	# 伦敦：泰晤士河（西 → 东）+ 利河（Lea，北侧支流）+ 拉文斯本河（南侧小支流）
	var london_box := Rect2(-0.340, 51.420, 0.460, 0.160)
	cities.append(_make({
		"id": "london",
		"name_zh": "伦敦",
		"name_en": "London",
		"rivers": [
			geo_band([
				Vector2(-0.300, 51.487), Vector2(-0.270, 51.477), Vector2(-0.245, 51.468),
				Vector2(-0.220, 51.466), Vector2(-0.195, 51.470), Vector2(-0.175, 51.478),
				Vector2(-0.155, 51.484), Vector2(-0.135, 51.495), Vector2(-0.115, 51.503),
				Vector2(-0.095, 51.509), Vector2(-0.075, 51.507), Vector2(-0.050, 51.502),
				Vector2(-0.020, 51.497), Vector2(0.005, 51.492), Vector2(0.030, 51.488),
				Vector2(0.060, 51.492), Vector2(0.090, 51.500), Vector2(0.115, 51.505),
			], london_box, 118.0),
			geo_band([
				Vector2(0.010, 51.575), Vector2(0.000, 51.550), Vector2(-0.010, 51.525),
				Vector2(-0.005, 51.500),
			], london_box, 46.0),
			geo_band([
				Vector2(-0.020, 51.420), Vector2(-0.010, 51.440), Vector2(0.000, 51.460),
				Vector2(0.005, 51.480),
			], london_box, 30.0, false),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))

	# 巴黎：塞纳河（东 → 西）+ 马恩河（东侧汇入）+ 圣马丁运河（北侧）
	var paris_box := Rect2(2.180, 48.780, 0.340, 0.130)
	cities.append(_make({
		"id": "paris",
		"name_zh": "巴黎",
		"name_en": "Paris",
		"rivers": [
			geo_band([
				Vector2(2.460, 48.835), Vector2(2.430, 48.836), Vector2(2.400, 48.833),
				Vector2(2.385, 48.840), Vector2(2.365, 48.847), Vector2(2.350, 48.853),
				Vector2(2.335, 48.858), Vector2(2.320, 48.862), Vector2(2.305, 48.864),
				Vector2(2.290, 48.863), Vector2(2.275, 48.860), Vector2(2.260, 48.855),
				Vector2(2.245, 48.848), Vector2(2.230, 48.840), Vector2(2.215, 48.833),
			], paris_box, 84.0),
			geo_band([
				Vector2(2.500, 48.845), Vector2(2.470, 48.840), Vector2(2.440, 48.836),
				Vector2(2.410, 48.834),
			], paris_box, 44.0),
			geo_band([
				Vector2(2.365, 48.885), Vector2(2.365, 48.872), Vector2(2.362, 48.858),
			], paris_box, 22.0, false),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))

	# 纽约：哈德逊河（西）+ 东河（东）+ 哈莱姆河（北）
	var ny_box := Rect2(-74.100, 40.640, 0.240, 0.270)
	cities.append(_make({
		"id": "newyork",
		"name_zh": "纽约",
		"name_en": "New York",
		"rivers": [
			geo_band([
				Vector2(-74.030, 40.660), Vector2(-74.020, 40.700), Vector2(-74.012, 40.730),
				Vector2(-74.005, 40.760), Vector2(-73.990, 40.790), Vector2(-73.970, 40.820),
				Vector2(-73.950, 40.850), Vector2(-73.930, 40.880),
			], ny_box, 104.0),
			geo_band([
				Vector2(-74.000, 40.660), Vector2(-73.990, 40.690), Vector2(-73.985, 40.710),
				Vector2(-73.978, 40.730), Vector2(-73.968, 40.750), Vector2(-73.958, 40.770),
				Vector2(-73.945, 40.790), Vector2(-73.935, 40.810), Vector2(-73.925, 40.840),
			], ny_box, 78.0),
			geo_band([
				Vector2(-73.935, 40.805), Vector2(-73.925, 40.815), Vector2(-73.918, 40.830),
				Vector2(-73.912, 40.850), Vector2(-73.910, 40.870),
			], ny_box, 44.0),
		],
		"lines": 3,
		"trains": 4,
		"bridges": 3,
	}))

	# 柏林：施普雷河（东 → 西）+ 南部运河 + 哈弗尔河（西）+ 达默河（东南）
	var berlin_box := Rect2(13.080, 52.380, 0.640, 0.250)
	cities.append(_make({
		"id": "berlin",
		"name_zh": "柏林",
		"name_en": "Berlin",
		"rivers": [
			geo_band([
				Vector2(13.700, 52.420), Vector2(13.660, 52.440), Vector2(13.620, 52.450),
				Vector2(13.570, 52.460), Vector2(13.530, 52.475), Vector2(13.500, 52.490),
				Vector2(13.475, 52.500), Vector2(13.450, 52.508), Vector2(13.425, 52.512),
				Vector2(13.400, 52.517), Vector2(13.375, 52.521), Vector2(13.350, 52.525),
				Vector2(13.320, 52.528), Vector2(13.290, 52.533), Vector2(13.260, 52.535),
				Vector2(13.230, 52.537), Vector2(13.200, 52.540), Vector2(13.160, 52.548),
				Vector2(13.120, 52.552),
			], berlin_box, 74.0),
			geo_band([
				Vector2(13.375, 52.512), Vector2(13.365, 52.500), Vector2(13.355, 52.490),
				Vector2(13.360, 52.482), Vector2(13.380, 52.480), Vector2(13.400, 52.483),
				Vector2(13.420, 52.490), Vector2(13.415, 52.505),
			], berlin_box, 46.0, false),
			geo_band([
				Vector2(13.100, 52.500), Vector2(13.150, 52.520), Vector2(13.180, 52.550),
				Vector2(13.160, 52.580), Vector2(13.120, 52.600),
			], berlin_box, 70.0),
			geo_band([
				Vector2(13.700, 52.380), Vector2(13.660, 52.410), Vector2(13.620, 52.440),
				Vector2(13.580, 52.460),
			], berlin_box, 50.0),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 3,
	}))

	# 东京：隅田川（北 → 南）+ 荒川（东侧）+ 东京湾
	var tokyo_box := Rect2(139.660, 35.500, 0.340, 0.340)
	cities.append(_make({
		"id": "tokyo",
		"name_zh": "东京",
		"name_en": "Tokyo",
		"rivers": [
			geo_band([
				Vector2(139.800, 35.830), Vector2(139.805, 35.780), Vector2(139.800, 35.730),
				Vector2(139.798, 35.690), Vector2(139.790, 35.660), Vector2(139.780, 35.620),
				Vector2(139.775, 35.580),
			], tokyo_box, 96.0),
			geo_band([
				Vector2(139.840, 35.840), Vector2(139.860, 35.780), Vector2(139.870, 35.720),
				Vector2(139.865, 35.650), Vector2(139.850, 35.600),
			], tokyo_box, 70.0),
			geo_polygon([
				Vector2(139.760, 35.600), Vector2(139.840, 35.580), Vector2(139.920, 35.550),
				Vector2(139.990, 35.500), Vector2(139.950, 35.440), Vector2(139.780, 35.460),
				Vector2(139.700, 35.520),
			], tokyo_box),
		],
		"lines": 3,
		"trains": 3,
		"bridges": 2,
	}))

	# 上海：黄浦江（南 → 北）+ 苏州河 + 川杨河（东侧）+ 淀浦河（南侧）
	var shanghai_box := Rect2(121.240, 31.080, 0.400, 0.400)
	cities.append(_make({
		"id": "shanghai",
		"name_zh": "上海",
		"name_en": "Shanghai",
		"rivers": [
			geo_band([
				Vector2(121.460, 31.100), Vector2(121.465, 31.150), Vector2(121.470, 31.200),
				Vector2(121.475, 31.240), Vector2(121.490, 31.270), Vector2(121.505, 31.300),
				Vector2(121.500, 31.330), Vector2(121.480, 31.370), Vector2(121.460, 31.410),
				Vector2(121.440, 31.460),
			], shanghai_box, 112.0),
			geo_band([
				Vector2(121.280, 31.250), Vector2(121.340, 31.245), Vector2(121.400, 31.245),
				Vector2(121.445, 31.250), Vector2(121.480, 31.253), Vector2(121.505, 31.248),
			], shanghai_box, 52.0),
			geo_band([
				Vector2(121.600, 31.150), Vector2(121.590, 31.200), Vector2(121.560, 31.240),
				Vector2(121.520, 31.260),
			], shanghai_box, 40.0, false),
			geo_band([
				Vector2(121.300, 31.100), Vector2(121.360, 31.120), Vector2(121.420, 31.140),
				Vector2(121.460, 31.160),
			], shanghai_box, 45.0, false),
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