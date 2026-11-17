extends RefCounted
## 城市地图：注册表完整性、河道几何合法、每张图都能正常生成站点。

static func run(h: TestHarness) -> void:
	_test_registry(h)
	_test_geometry(h)
	_test_geo_projection(h)
	_test_water_merge(h)
	_test_spawnable(h)


static func _test_registry(h: TestHarness) -> void:
	h.section("cities/registry")
	var cities := CityMaps.all()
	h.check(cities.size() >= 7, "至少 7 张城市地图（实际 %d）" % cities.size())
	var ids := {}
	for city in cities:
		h.check(city.id != "", "城市有 id")
		h.check(not ids.has(city.id), "城市 id 唯一：" + city.id)
		ids[city.id] = true
		h.check(city.name_zh != "", "城市有中文名：" + city.id)
		h.check(city.name_en != "", "城市有英文名：" + city.id)
		h.check(not city.rivers.is_empty(), "城市有河道：" + city.id)
		h.check(city.start_lines >= 1, "初始线路数合法：" + city.id)
		h.check(city.start_trains >= 1, "初始列车数合法：" + city.id)
		h.check(city.start_bridges >= 1, "初始桥隧数合法：" + city.id)

	h.eq(CityMaps.default_city_id(), "paper", "默认城市是纸城")
	h.eq(CityMaps.get_city("london").id, "london", "按 id 取城市")
	h.eq(CityMaps.get_city("nope").id, "paper", "未知 id 回退默认城市")
	h.eq(CityMaps.index_of("tokyo"), 5, "城市顺序稳定")
	h.eq(CityMaps.index_of("nope"), 0, "未知 id 索引回退 0")


static func _test_geometry(h: TestHarness) -> void:
	h.section("cities/geometry")
	for city in CityMaps.all():
		for river in city.rivers:
			h.check(river.size() >= 3, "河道至少 3 个点：" + city.id)
			var inside := true
			for point in river:
				# 干流两端会故意延长出画面，这里只要求不要飞出得太离谱
				if point.x < -900.0 or point.x > 3300.0 or point.y < -900.0 or point.y > 2100.0:
					inside = false
			h.check(inside, "河道在画布范围内（允许穿出画面）：" + city.id)


static func _test_geo_projection(h: TestHarness) -> void:
	h.section("cities/geo")
	var bbox := Rect2(13.240, 52.460, 0.360, 0.090)
	var latitude := bbox.position.y + bbox.size.y * 0.5
	var target := CityMaps.fit_geo(bbox, latitude)
	h.check(target.size.x > 0.0 and target.size.y > 0.0, "2400×1200 大地图有合法投影")
	h.near(target.size.x / target.size.y, (bbox.size.x * cos(deg_to_rad(latitude))) / bbox.size.y,
		0.01, "投影保持真实宽高比")
	h.check(target.position.x >= CityMaps.MAP_AREA.position.x - 0.5, "投影在绘图区内（左）")
	h.check(target.end.x <= CityMaps.MAP_AREA.end.x + 0.5, "投影在绘图区内（右）")
	h.check(target.position.y >= CityMaps.MAP_AREA.position.y - 0.5, "投影在绘图区内（上）")
	h.check(target.end.y <= CityMaps.MAP_AREA.end.y + 0.5, "投影在绘图区内（下）")

	var projected := CityMaps.project([
		Vector2(13.40, 52.460), Vector2(13.40, 52.550), Vector2(13.30, 52.460),
	], bbox, target)
	h.near(projected[0].x, projected[1].x, 0.01, "同经度映射到同一 x")
	h.check(projected[0].y > projected[1].y, "纬度越高越靠上（y 越小）")
	h.check(projected[2].x < projected[0].x, "经度越大越靠右")


static func _test_water_merge(h: TestHarness) -> void:
	h.section("cities/water_merge")
	var a := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100),
	])
	var b := PackedVector2Array([
		Vector2(50, 0), Vector2(150, 0), Vector2(150, 100), Vector2(50, 100),
	])
	var merged := MapView.merge_rivers([a, b])
	h.eq(merged.size(), 1, "两条重叠河道合并成一块水面")
	h.near(_polygon_area(merged[0]), 15000.0, 1.0, "合并后的面积等于并集面积")

	var far := PackedVector2Array([
		Vector2(300, 0), Vector2(400, 0), Vector2(400, 100), Vector2(300, 100),
	])
	var separate := MapView.merge_rivers([a, far])
	h.eq(separate.size(), 2, "不相交的河道保持两块水面")


static func _polygon_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		total += p.x * q.y - q.x * p.y
	return absf(total) * 0.5


static func _test_spawnable(h: TestHarness) -> void:
	h.section("cities/spawnable")
	for city in CityMaps.all():
		var level := LevelData.new()
		level.rivers.clear()
		for river in city.rivers:
			level.rivers.append(river)
		level.start_lines = city.start_lines
		level.start_trains = city.start_trains
		level.start_bridges = city.start_bridges
		level.station_spawn_interval = 99999.0
		level.passenger_spawn_start = 99999.0
		level.passenger_spawn_end = 99999.0
		var net := MetroNetwork.new(level)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2026
		var spawner := StationSpawner.new(level, rng)
		spawner.spawn_initial(net, 8)
		h.check(net.stations.size() >= 5,
			"城市能生成足够站点：" + city.id + "（%d）" % net.stations.size())
		for st in net.stations:
			h.check(not net.is_point_in_water(st.pos), "站点不在水里：" + city.id)