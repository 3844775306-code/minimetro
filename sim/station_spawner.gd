class_name StationSpawner
extends RefCounted
## 站点生成：拒绝采样保证"在陆地内、离河道/其他站/地图边缘足够远"，
## 形状按 LevelData.station_shape_weights 加权（菱形/星形是稀有站）。

var level: LevelData
var rng: RandomNumberGenerator
## 当前相机可见的世界范围；非空时新站只在这个范围内生成
var spawn_rect := Rect2()


## 开局三站的最大彼此距离：围绕第一座站生成，避免一开局就散得太远
const INITIAL_MAX_DISTANCE := 280.0


func _init(p_level: LevelData, p_rng: RandomNumberGenerator) -> void:
	level = p_level
	rng = p_rng


func spawn_initial(network: MetroNetwork, count: int, weights: Dictionary = {}) -> void:
	for i in count:
		try_spawn(network, weights)


## 开局固定三座基础地标：圆形居民区、三角形商务区、方形车站。
## 后两座围绕第一座生成，三站尽量靠近。
func spawn_starting_trio(network: MetroNetwork) -> void:
	var first := _random_land_point(network)
	if first == Vector2.INF:
		return
	network.add_station(first, Shape.Kind.CIRCLE)
	for kind in [Shape.Kind.TRIANGLE, Shape.Kind.SQUARE]:
		var pos := _random_land_point(network, first, INITIAL_MAX_DISTANCE)
		if pos == Vector2.INF:
			pos = _random_land_point(network)
		if pos == Vector2.INF:
			continue
		network.add_station(pos, int(kind))


func try_spawn(network: MetroNetwork, weights: Dictionary = {}) -> Station:
	if network.stations.size() >= level.max_stations:
		return null
	var pos := _random_land_point(network)
	if pos == Vector2.INF:
		return null
	return network.add_station(pos, _pick_shape(weights))


## 拒绝采样：随机落点，不满足约束就重试。
## anchor != INF 时只在 anchor 周围 max_radius 范围内取样（开局三站使用）。
func _random_land_point(network: MetroNetwork, anchor: Vector2 = Vector2.INF,
		max_radius: float = 0.0) -> Vector2:
	var margin: float = level.station_margin
	var min_x: float = margin
	var max_x: float = level.world_size.x - margin
	var min_y: float = margin
	var max_y: float = level.world_size.y - margin
	if spawn_rect.size.x > 0.0 and spawn_rect.size.y > 0.0:
		min_x = maxf(min_x, spawn_rect.position.x)
		max_x = minf(max_x, spawn_rect.end.x)
		min_y = maxf(min_y, spawn_rect.position.y)
		max_y = minf(max_y, spawn_rect.end.y)
	if anchor != Vector2.INF and max_radius > 0.0:
		min_x = maxf(min_x, anchor.x - max_radius)
		max_x = minf(max_x, anchor.x + max_radius)
		min_y = maxf(min_y, anchor.y - max_radius)
		max_y = minf(max_y, anchor.y + max_radius)
	if max_x < min_x or max_y < min_y:
		return Vector2.INF
	for attempt in 140:
		var p := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
		if anchor != Vector2.INF and max_radius > 0.0 and p.distance_to(anchor) > max_radius:
			continue
		if network.is_point_in_water(p):
			continue
		if network.water_distance(p) < level.station_water_clearance:
			continue
		var too_close := false
		for st in network.stations:
			if st.pos.distance_to(p) < level.station_min_distance:
				too_close = true
				break
		if not too_close:
			return p
	return Vector2.INF


## 按形状权重加权随机（权重 <= 0 的形状不会被选中）。
func _pick_shape(override_weights: Dictionary = {}) -> int:
	var weights: Dictionary = override_weights
	if weights.is_empty():
		weights = level.station_shape_weights
	if weights.is_empty():
		return Shape.Kind.CIRCLE
	var kinds: Array = weights.keys()
	var total := 0.0
	for i in kinds.size():
		total += maxf(0.0, float(weights[kinds[i]]))
	if total <= 0.0:
		return Shape.Kind.CIRCLE
	var r := rng.randf() * total
	for i in kinds.size():
		r -= maxf(0.0, float(weights[kinds[i]]))
		if r <= 0.0:
			return int(kinds[i])
	return int(kinds[kinds.size() - 1])
