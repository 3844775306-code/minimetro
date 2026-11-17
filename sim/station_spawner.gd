class_name StationSpawner
extends RefCounted
## 站点生成：拒绝采样保证"在陆地内、离河道/其他站/地图边缘足够远"，
## 形状按 LevelData.station_shape_weights 加权（菱形/星形是稀有站）。

var level: LevelData
var rng: RandomNumberGenerator


func _init(p_level: LevelData, p_rng: RandomNumberGenerator) -> void:
	level = p_level
	rng = p_rng


func spawn_initial(network: MetroNetwork, count: int) -> void:
	for i in count:
		try_spawn(network)


func try_spawn(network: MetroNetwork) -> Station:
	if network.stations.size() >= level.max_stations:
		return null
	var pos := _random_land_point(network)
	if pos == Vector2.INF:
		return null
	return network.add_station(pos, _pick_shape())


## 拒绝采样：随机落点，不满足约束就重试。
func _random_land_point(network: MetroNetwork) -> Vector2:
	var margin: float = level.station_margin
	var min_x: float = margin
	var max_x: float = level.world_size.x - margin
	var min_y: float = margin
	var max_y: float = level.world_size.y - margin
	for attempt in 140:
		var p := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
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
func _pick_shape() -> int:
	var weights: Dictionary = level.station_shape_weights
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
