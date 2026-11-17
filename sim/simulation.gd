class_name Simulation
extends RefCounted
## 固定步长模拟：1/60s tick 内推进所有逻辑（列车 / 乘客 / 溢出 / 生成）。
## 视图层只做表现，配置全部来自 LevelData，方便 M3 抽卡时换参数。

signal game_over(station: Station)

const STEP := 1.0 / 60.0

var network: MetroNetwork
var level: LevelData
var spawner: StationSpawner
var routing := Routing.new()
var rng: RandomNumberGenerator

var elapsed: float = 0.0
var paused: bool = false
var auto_spawn: bool = true
var is_over: bool = false

var score: int = 0
var delivered: int = 0

var _accum: float = 0.0
var _station_spawn_timer: float = 0.0
var _passenger_spawn_timer: float = 0.0
var _train_id: int = 0


func _init(p_network: MetroNetwork, p_level: LevelData, p_rng: RandomNumberGenerator) -> void:
	network = p_network
	level = p_level
	rng = p_rng
	spawner = StationSpawner.new(level, rng)
	_station_spawn_timer = level.station_spawn_interval
	_passenger_spawn_timer = level.passenger_spawn_start


## 由主循环每帧调用；speed 为倍速（倍速 = 多跑 tick，而不是放大 delta）。
func advance(frame_delta: float, speed: float = 1.0) -> void:
	if paused or is_over:
		return
	_accum += minf(frame_delta, 0.25) * maxf(speed, 0.0)
	var guard := 0
	while _accum >= STEP and guard < 120:
		tick(STEP)
		_accum -= STEP
		guard += 1


func tick(dt: float) -> void:
	if is_over:
		return
	elapsed += dt
	if routing.version != network.version:
		routing.rebuild(network)
	if auto_spawn:
		_update_spawns(dt)
	_ensure_trains()
	_update_trains(dt)
	_update_stations(dt)


# ---------------------------------------------------------------------------
# 生成
# ---------------------------------------------------------------------------

func _update_spawns(dt: float) -> void:
	_station_spawn_timer -= dt
	if _station_spawn_timer <= 0.0:
		_station_spawn_timer = level.station_spawn_interval
		spawner.try_spawn(network)

	if network.stations.is_empty():
		return
	_passenger_spawn_timer -= dt
	if _passenger_spawn_timer > 0.0:
		return
	_passenger_spawn_timer = _passenger_interval()
	_spawn_passenger()


func _passenger_interval() -> float:
	var t: float = clampf(elapsed / maxf(level.passenger_ramp_seconds, 1.0), 0.0, 1.0)
	return lerpf(level.passenger_spawn_start, level.passenger_spawn_end, t)


## 加权选站 + 按形状占比选目的地。
func _spawn_passenger() -> void:
	var stations := network.stations
	var total := 0
	for st in stations:
		total += 1 + st.line_ids.size() * 2
	if total <= 0:
		return
	var r := rng.randi_range(0, total - 1)
	var chosen: Station = stations[0]
	for st in stations:
		r -= 1 + st.line_ids.size() * 2
		if r < 0:
			chosen = st
			break

	var counts := {}
	for st in stations:
		counts[st.shape] = int(counts.get(st.shape, 0)) + 1
	var shapes: Array[int] = []
	var weights: Array[int] = []
	var weight_total := 0
	var keys: Array = counts.keys()
	for i in keys.size():
		var shape: int = int(keys[i])
		if shape == chosen.shape:
			continue
		shapes.append(shape)
		weights.append(int(counts[shape]))
		weight_total += int(counts[shape])
	if weight_total <= 0:
		return
	var pick := rng.randi_range(0, weight_total - 1)
	for i in shapes.size():
		pick -= weights[i]
		if pick < 0:
			chosen.waiting.append(Passenger.new(shapes[i], elapsed))
			return


# ---------------------------------------------------------------------------
# 列车
# ---------------------------------------------------------------------------

func _ensure_trains() -> void:
	var used := network.train_count()
	for line in network.lines:
		if line.stops.size() < 2 or not line.geometry.is_drawable():
			_drop_trains(line)
			continue
		if not line.trains.is_empty():
			continue
		if used >= level.start_trains:
			continue
		var train := Train.new()
		train.id = _train_id
		_train_id += 1
		train.line_id = line.id
		train.dir = 1
		train.stop_index = 0
		train.dist = line.geometry.stop_offsets[0]
		train.state = Train.State.DWELL
		train.dwell_left = 0.6
		train.line_version = line.version
		line.trains.append(train)
		used += 1
		_on_station(train, line, line.stops[0])


func _drop_trains(line: MetroLine) -> void:
	if line.trains.is_empty():
		return
	for train in line.trains:
		_rescue_riders(train, line)
	line.trains.clear()


func _rescue_riders(train: Train, line: MetroLine) -> void:
	if train.riders.is_empty():
		return
	var pos: Vector2 = line.geometry.sample(train.dist).origin
	var target := network.nearest_station(pos)
	if target == null:
		return
	for passenger in train.riders:
		target.waiting.append(passenger)
	train.riders.clear()


func _update_trains(dt: float) -> void:
	for line in network.lines:
		if line.stops.size() < 2 or not line.geometry.is_drawable():
			continue
		for train in line.trains:
			_update_train(train, line, dt)


func _update_train(train: Train, line: MetroLine, dt: float) -> void:
	if train.line_version != line.version or train.stop_index >= line.stops.size():
		_remap_train(train, line)

	if train.state == Train.State.DWELL:
		train.dwell_left -= dt
		if train.dwell_left <= 0.0:
			_depart(train, line)
		return

	var remaining := absf(train.target_dist - train.dist)
	var step := Train.SPEED * dt
	if remaining <= step:
		train.dist = train.target_dist
		train.stop_index = train.target_index
		train.state = Train.State.DWELL
		train.dwell_left = Train.DWELL_TIME
		_on_station(train, line, line.stops[train.stop_index])
	else:
		train.dist += signf(train.target_dist - train.dist) * step


func _depart(train: Train, line: MetroLine) -> void:
	var next := train.stop_index + train.dir
	if next < 0 or next >= line.stops.size():
		train.dir = -train.dir
		next = train.stop_index + train.dir
	if next < 0 or next >= line.stops.size():
		train.dwell_left = Train.DWELL_TIME
		return
	train.target_index = next
	train.target_dist = line.geometry.stop_offsets[next]
	train.state = Train.State.MOVING


## 到站：先下（含送达/换乘），再上。
func _on_station(train: Train, line: MetroLine, station: Station) -> void:
	var next_departure := _next_departure_station_id(train, line)

	var staying: Array[Passenger] = []
	for passenger in train.riders:
		if passenger.target_shape == station.shape:
			score += 1
			delivered += 1
			continue
		# 继续坐 vs 下车换乘：取剩余代价更小的那条路
		var stay := routing.stay_cost(train.line_id, station.id, next_departure, passenger.target_shape)
		var leave := routing.board_cost(station.id, passenger.target_shape)
		if stay <= leave:
			staying.append(passenger)
		else:
			station.waiting.append(passenger)
	train.riders = staying

	var capacity_left := train.capacity - train.riders.size()
	if capacity_left <= 0 or station.waiting.is_empty():
		return
	var keep: Array[Passenger] = []
	for passenger in station.waiting:
		if capacity_left > 0:
			var choice := routing.next_for(station.id, passenger.target_shape)
			if not choice.is_empty() \
					and int(choice["line"]) == train.line_id \
					and int(choice["station"]) == next_departure:
				train.riders.append(passenger)
				capacity_left -= 1
				continue
		keep.append(passenger)
	station.waiting = keep


func _next_departure_station_id(train: Train, line: MetroLine) -> int:
	var next := train.stop_index + train.dir
	if next < 0 or next >= line.stops.size():
		next = train.stop_index - train.dir
	if next < 0 or next >= line.stops.size():
		return -1
	return line.stops[next].id


## 线路被玩家编辑后：按最近站重新落位，避免列车卡在线外。
func _remap_train(train: Train, line: MetroLine) -> void:
	train.line_version = line.version
	train.dist = clampf(train.dist, 0.0, line.geometry.total_length)
	var best := 0
	var best_d := INF
	for i in line.geometry.stop_offsets.size():
		var d := absf(line.geometry.stop_offsets[i] - train.dist)
		if d < best_d:
			best_d = d
			best = i
	train.stop_index = best
	train.target_index = clampi(train.target_index, 0, line.stops.size() - 1)
	train.target_dist = line.geometry.stop_offsets[train.target_index]


# ---------------------------------------------------------------------------
# 站点压力
# ---------------------------------------------------------------------------

func _update_stations(dt: float) -> void:
	for st in network.stations:
		if not st.waiting.is_empty():
			var keep: Array[Passenger] = []
			for passenger in st.waiting:
				if passenger.target_shape == st.shape:
					score += 1
					delivered += 1
				else:
					keep.append(passenger)
			st.waiting = keep

		if st.waiting.size() > st.capacity:
			st.overload_timer += dt
			if st.overload_timer >= level.overload_grace and not is_over:
				is_over = true
				game_over.emit(st)
				return
		else:
			st.overload_timer = maxf(0.0, st.overload_timer - dt * 1.5)
