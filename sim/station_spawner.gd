class_name StationSpawner
extends RefCounted
## 站点生成：拒绝采样保证"在陆地内、离其他站/地图边缘足够远"，
## 形状按"当前数量越少权重越高"挑选，避免某种形状绝迹。

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
	return network.add_station(pos, _pick_shape(network))


## 拒绝采样：随机落点，不满足最小间距就重试。
func _random_land_point(network: MetroNetwork) -> Vector2:
	var margin: float = level.station_margin
	var min_x: float = margin
	var max_x: float = level.world_size.x - margin
	var min_y: float = margin
	var max_y: float = level.world_size.y - margin
	for attempt in 120:
		var p := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
		var too_close := false
		for st in network.stations:
			if st.pos.distance_to(p) < level.station_min_distance:
				too_close = true
				break
		if not too_close:
			return p
	return Vector2.INF


## 逆数量加权：某形状越少，越容易被选中。
func _pick_shape(network: MetroNetwork) -> int:
	var shapes: Array[int] = level.station_shapes
	if shapes.is_empty():
		return Shape.Kind.CIRCLE
	var counts := {}
	for kind in shapes:
		counts[kind] = 0
	for st in network.stations:
		if counts.has(st.shape):
			counts[st.shape] += 1
	var total := 0
	var weights: Array[int] = []
	for kind in shapes:
		var w: int = 1 + maxi(0, 6 - int(counts[kind])) * 3
		weights.append(w)
		total += w
	var r: int = rng.randi_range(0, total - 1)
	for i in shapes.size():
		r -= weights[i]
		if r < 0:
			return shapes[i]
	return shapes[0]
