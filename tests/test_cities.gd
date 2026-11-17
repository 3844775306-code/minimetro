extends RefCounted
## 城市地图：注册表完整性、河道几何合法、每张图都能正常生成站点。

static func run(h: TestHarness) -> void:
	_test_registry(h)
	_test_geometry(h)
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
				if point.x < -120.0 or point.x > 2040.0 or point.y < -120.0 or point.y > 1200.0:
					inside = false
			h.check(inside, "河道在画布范围内：" + city.id)


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