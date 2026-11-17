class_name DemoSetup
extends RefCounted
## 确定性演示布局：不经过玩家手势，直接生成一张"已经在运营"的网。
## 只用于截图/回归对比，不参与正式玩法。

const STATION_POINTS := [
	Vector2(300, 300), Vector2(620, 250), Vector2(950, 300), Vector2(1420, 240), Vector2(1590, 380),
	Vector2(420, 640), Vector2(760, 560), Vector2(1000, 620), Vector2(1470, 720),
	Vector2(900, 870), Vector2(560, 900),
]

const STATION_SHAPES := [
	Shape.Kind.CIRCLE, Shape.Kind.TRIANGLE, Shape.Kind.SQUARE, Shape.Kind.CIRCLE, Shape.Kind.TRIANGLE,
	Shape.Kind.SQUARE, Shape.Kind.CIRCLE, Shape.Kind.TRIANGLE, Shape.Kind.SQUARE, Shape.Kind.CIRCLE,
	Shape.Kind.TRIANGLE,
]

## 线路 = 站点索引序列
const LINES := [
	[0, 1, 2, 3, 4],
	[5, 6, 7, 8],
	[9, 10, 6, 2],
]


static func build(network: MetroNetwork, level: LevelData, line_count: int = 3) -> void:
	var stations: Array[Station] = []
	for i in STATION_POINTS.size():
		stations.append(network.add_station(STATION_POINTS[i], STATION_SHAPES[i]))
	for i in mini(line_count, LINES.size()):
		var line := network.create_line()
		for index in LINES[i]:
			line.add_stop(stations[index])
	network.touch()
	level.start_station_count = stations.size()


static func build_adaptive(network: MetroNetwork, level: LevelData, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spawner := StationSpawner.new(level, rng)
	spawner.spawn_initial(network, 11)
	var stations := network.stations.duplicate()
	if stations.size() < 4:
		return
	var lengths := [mini(5, stations.size()), mini(4, stations.size()), mini(4, stations.size())]
	# 起点尽量分散（左 / 中 / 右），让三条线覆盖整张地图
	var sorted := stations.duplicate()
	sorted.sort_custom(func(a: Station, b: Station) -> bool: return a.pos.x < b.pos.x)
	var start_indexes := [0, sorted.size() / 2, sorted.size() - 1]
	for li in 3:
		var start: Station = sorted[start_indexes[li]]
		var chain := _nearest_chain(stations, start, lengths[li])
		if chain.size() < 2:
			continue
		var line := network.create_line()
		for st in chain:
			line.add_stop(st)
	network.touch()
	level.start_bridges = maxi(level.start_bridges, network.used_bridges())
	level.start_lines = maxi(level.start_lines, 3)
	level.start_trains = maxi(level.start_trains, 3)
	level.start_station_count = network.stations.size()


## 从 start 出发，每次接最近且本线未用过的站。
static func _nearest_chain(stations: Array, start: Station, length: int) -> Array[Station]:
	var chain: Array[Station] = [start]
	var used := {start.id: true}
	var current := start
	while chain.size() < length:
		var best_station: Station = null
		var best_distance := INF
		for st in stations:
			if used.has(st.id):
				continue
			var d := current.pos.distance_squared_to(st.pos)
			if d < best_distance:
				best_distance = d
				best_station = st
		if best_station == null:
			break
		chain.append(best_station)
		used[best_station.id] = true
		current = best_station
	return chain


## 给每座站预置若干"去别的形状"的乘客，让截图里能看到等待图标与车内乘客。
static func seed_passengers(network: MetroNetwork, per_station: int = 1) -> void:
	var shapes: Array[int] = []
	for st in network.stations:
		if not shapes.has(st.shape):
			shapes.append(st.shape)
	shapes.sort()
	if shapes.size() < 2:
		return
	var fallback: int = shapes[0]
	for st in network.stations:
		var target := fallback
		for candidate in shapes:
			if candidate != st.shape:
				target = candidate
				break
		for i in per_station:
			st.waiting.append(Passenger.new(target))
