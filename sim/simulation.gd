class_name Simulation
extends RefCounted
## 固定步长模拟：1/60s tick 内推进所有逻辑（生成 / 列车 / 上下车 / 溢出 / 周循环）。
## 视图层只做表现，配置全部来自 LevelData。

signal game_over(station: Station)
## 每周结算：cards 为 1~2 张升级卡（Dictionary），week 为第几周。
signal week_completed(cards: Array, week: int)
## 到站送达：一次停靠送走若干乘客（用于飘字与音效）。
signal passengers_delivered(station: Station, count: int)
## 站点第一次超过容量（红色计时环出现）。
signal overload_started(station: Station)

const STEP := 1.0 / 60.0
## 时间换算：1 现实秒 = 1 游戏小时。
const HOURS_PER_DAY := 24.0

var network: MetroNetwork
var level: LevelData
var spawner: StationSpawner
var routing := Routing.new()
var rng: RandomNumberGenerator

## 已过去的游戏小时（= 现实秒数）。
var elapsed: float = 0.0
var paused: bool = false
var auto_spawn: bool = true
var is_over: bool = false

var score: int = 0
var delivered: int = 0

## 周循环状态
var week_index: int = 1
var week_pending: bool = false
var pending_cards: Array[Dictionary] = []

## 可用库存（从图标拖到地图上使用）
var inventory_trains: int = 0
var inventory_carriages: int = 0
var inventory_interchanges: int = 0

var _accum: float = 0.0
var _station_spawn_timer: float = 0.0
var _passenger_spawn_timer: float = 0.0
## 下一次周结算对应的游戏小时。
var _week_end_hour: float = 0.0
var _train_id: int = 0
## 已经做过"新线自动配车"判定的线路 id
var _auto_lines := {}


func _init(p_network: MetroNetwork, p_level: LevelData, p_rng: RandomNumberGenerator) -> void:
	network = p_network
	level = p_level
	rng = p_rng
	spawner = StationSpawner.new(level, rng)
	_station_spawn_timer = level.station_spawn_interval
	_passenger_spawn_timer = level.passenger_spawn_start
	_week_end_hour = level.week_seconds
	inventory_trains = level.start_trains
	inventory_carriages = level.start_carriages
	inventory_interchanges = level.start_interchanges


## 由主循环每帧调用；speed 为倍速（倍速 = 多跑 tick，而不是放大 delta）。
func advance(frame_delta: float, speed: float = 1.0) -> void:
	if paused or is_over or week_pending:
		return
	_accum += minf(frame_delta, 0.25) * maxf(speed, 0.0)
	var guard := 0
	while _accum >= STEP and guard < 120:
		tick(STEP)
		_accum -= STEP
		guard += 1


func tick(dt: float) -> void:
	if is_over or week_pending:
		return
	elapsed += dt
	if routing.version != network.version:
		routing.rebuild(network)
	if auto_spawn:
		_update_spawns(dt)
	_auto_assign_new_lines()
	_update_trains(dt)
	_update_stations(dt)
	if is_over:
		return
	_update_week()


## 当前游戏时刻（0~24 小时）。
func hour_of_day() -> float:
	return fmod(level.start_hour + elapsed, HOURS_PER_DAY)


## 白天 06:00~18:00；其余为夜晚（给 HUD 的时钟用）。
func is_night() -> bool:
	return night_strength(hour_of_day()) >= 0.5


## 夜色浓度：18:00~20:00 渐入、05:00~07:00 渐出，其余夜晚为 1、白天为 0。
static func night_strength(hour: float) -> float:
	var h := fmod(hour, 24.0)
	if h >= 20.0 or h < 5.0:
		return 1.0
	if h >= 18.0:
		return (h - 18.0) / 2.0
	if h < 7.0:
		return (7.0 - h) / 2.0
	return 0.0


func hour_12() -> int:
	var h := int(floor(hour_of_day() + 0.0001)) % 24
	h = h % 12
	return 12 if h == 0 else h


func is_pm() -> bool:
	return hour_of_day() >= 12.0


func day_index() -> int:
	return int(floor(elapsed / HOURS_PER_DAY + 0.0001))


## 星期几（第 0 天 = 周一）。
func weekday_name() -> String:
	var zh := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
	var en := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
	var index := day_index() % 7
	return Loc.t(zh[index], en[index])


func total_trains_owned() -> int:
	return inventory_trains + network.train_count()


func total_carriages_owned() -> int:
	return inventory_carriages + network.total_carriages()


func total_interchanges_owned() -> int:
	var upgraded := 0
	for st in network.stations:
		if st.capacity > 6:
			upgraded += 1
	return inventory_interchanges + upgraded


# ---------------------------------------------------------------------------
# 周循环 / 升级
# ---------------------------------------------------------------------------

func _update_week() -> void:
	if elapsed < _week_end_hour:
		return
	_week_end_hour += level.week_seconds
	var cards := _roll_cards()
	if cards.is_empty():
		# 所有资源都满了：跳过这一周
		week_index += 1
		return
	week_pending = true
	pending_cards.clear()
	for card in cards:
		pending_cards.append(card)
	week_completed.emit(pending_cards, week_index)


## 选择本周末的升级卡（暂停状态下由 UI 调用）。
## 列车/车厢/换乘中心都只是入库，玩家之后从 HUD 图标拖到地图上使用。
func choose_upgrade(index: int) -> void:
	if not week_pending:
		return
	if index < 0 or index >= pending_cards.size():
		return
	var card_id := String(pending_cards[index]["id"])
	pending_cards = []
	apply_upgrade(card_id)
	_finish_week()


func _finish_week() -> void:
	week_pending = false
	pending_cards = []
	week_index += 1
	_accum = 0.0


## 直接应用一张升级卡（测试 / 调试也走这里）。
func apply_upgrade(card_id: String) -> void:
	match card_id:
		"line":
			level.start_lines = mini(level.start_lines + 1, level.max_lines)
		"train":
			inventory_trains += 1
		"carriage":
			inventory_carriages += 1
		"bridge":
			level.start_bridges = mini(level.start_bridges + 1, level.max_bridges)
		"interchange":
			inventory_interchanges += 1
		_:
			push_warning("未知的升级卡: " + card_id)


## 从库存拖一辆列车到线路上的任意位置；成功返回 true。
func place_train(line: MetroLine, pos: Vector2) -> bool:
	if inventory_trains <= 0 or line == null:
		return false
	if line.stops.size() < 2 or not line.geometry.is_drawable():
		return false
	inventory_trains -= 1
	_spawn_train_at(line, pos)
	return true


## 从库存拖一节车厢：挂到光标附近（或目标线路上）的列车上。
func place_carriage(pos: Vector2) -> bool:
	if inventory_carriages <= 0:
		return false
	var train := _train_near(pos)
	if train == null:
		return false
	if train.carriages >= level.max_carriages:
		return false
	inventory_carriages -= 1
	train.carriages += 1
	train.refresh_capacity()
	return true


## 从库存拖一个换乘中心：放在容量 6 的车站上，容量提到 12。
func place_interchange(station: Station) -> bool:
	if inventory_interchanges <= 0 or station == null:
		return false
	if station.capacity > 6:
		return false
	inventory_interchanges -= 1
	station.capacity = 12
	return true


## 光标附近最近的一列车（先看列车位置，其次看所在线路）。
func _train_near(pos: Vector2) -> Train:
	var best: Train = null
	var best_dist := 56.0
	for line in network.lines:
		if not line.geometry.is_drawable():
			continue
		for train in line.trains:
			var d := line.geometry.sample(train.dist).origin.distance_to(pos)
			if d < best_dist:
				best_dist = d
				best = train
	if best != null:
		return best
	var line := nearest_line(pos)
	if line == null:
		return null
	best = null
	best_dist = INF
	for train in line.trains:
		var d := line.geometry.sample(train.dist).origin.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = train
	return best


## 距离 pos 最近、且在拾取半径内的线路（供拖放资源用）。
func nearest_line(pos: Vector2, max_dist: float = 24.0) -> MetroLine:
	var best: MetroLine = null
	var best_dist := max_dist
	for line in network.lines:
		if line.stops.size() < 2 or not line.geometry.is_drawable():
			continue
		var offset := line.geometry.nearest_distance(pos)
		var d := line.geometry.sample(offset).origin.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = line
	return best


## 把列车放到线路上的任意弧长位置：朝最近的前方站行驶（环线自动回绕）。
func _place_train_at(train: Train, line: MetroLine, pos: Vector2) -> void:
	var total := line.geometry.total_length
	var d := clampf(line.geometry.nearest_distance(pos), 0.0, total)
	train.dist = d
	train.state = Train.State.MOVING
	train.dwell_left = 0.0
	var best := 0
	var best_diff := INF
	for i in line.geometry.stop_offsets.size():
		var diff := absf(line.geometry.stop_offsets[i] - d)
		if diff < best_diff:
			best_diff = diff
			best = i
	train.stop_index = best
	if line.is_loop and line.stops.size() >= 3:
		train.dir = 1
		var next := (best + 1) % line.stops.size()
		train.target_index = next
		var target := line.geometry.stop_offsets[next]
		if target <= d:
			target += total
		train.target_dist = target
		return
	var next := best + 1
	if next < line.stops.size() and line.geometry.stop_offsets[next] >= d:
		train.dir = 1
		train.target_index = next
		train.target_dist = line.geometry.stop_offsets[next]
	else:
		var prev := maxi(best - 1, 0)
		train.dir = -1
		train.target_index = prev
		train.target_dist = line.geometry.stop_offsets[prev]


func _roll_cards() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if network.lines.size() < level.max_lines:
		pool.append(UpgradeCards.get_card("line"))
	if total_trains_owned() < level.max_trains:
		pool.append(UpgradeCards.get_card("train"))
	if total_carriages_owned() < level.max_carriages * 3:
		pool.append(UpgradeCards.get_card("carriage"))
	if level.start_bridges < level.max_bridges:
		pool.append(UpgradeCards.get_card("bridge"))
	if total_interchanges_owned() < level.max_interchanges and _interchange_station() != null:
		pool.append(UpgradeCards.get_card("interchange"))

	var picked: Array[Dictionary] = []
	while picked.size() < 2 and not pool.is_empty():
		var index := _weighted_pick(pool)
		if index < 0:
			break
		picked.append(pool[index])
		pool.remove_at(index)
	return picked


## 容量 6 的车站（换乘中心的目标）。
func _interchange_station() -> Station:
	for st in network.stations:
		if st.capacity <= 6:
			return st
	return null


func _weighted_pick(pool: Array[Dictionary]) -> int:
	var total := 0.0
	for card in pool:
		total += float(card["weight"])
	if total <= 0.0:
		return -1
	var r := rng.randf() * total
	for i in pool.size():
		r -= float(pool[i]["weight"])
		if r <= 0.0:
			return i
	return pool.size() - 1


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

## 只有"新开的线路"才会自动配 1 列车（且库存里还有车）；其余都要玩家手动拖。
func _auto_assign_new_lines() -> void:
	# 清理已经删除的线路标记
	var live := {}
	for line in network.lines:
		live[line.id] = true
	for id in _auto_lines.keys().duplicate():
		if not live.has(id):
			_auto_lines.erase(id)
	for line in network.lines:
		if line.stops.size() < 2 or not line.geometry.is_drawable():
			_drop_trains(line)
			continue
		if _auto_lines.has(line.id):
			continue
		_auto_lines[line.id] = true
		if inventory_trains > 0:
			inventory_trains -= 1
			_spawn_train_at(line, line.stops[0].pos)


func _spawn_train_at(line: MetroLine, pos: Vector2) -> void:
	var train := Train.new()
	train.id = _train_id
	_train_id += 1
	train.line_id = line.id
	train.line_version = line.version
	train.carriages = 0
	train.refresh_capacity()
	line.trains.append(train)
	_place_train_at(train, line, pos)
	# 正好放在站点上：立即停靠一次，自动配车/拖到站台都能马上上下客
	var nearest := 0
	var best_diff := INF
	for i in line.geometry.stop_offsets.size():
		var diff := absf(line.geometry.stop_offsets[i] - train.dist)
		if diff < best_diff:
			best_diff = diff
			nearest = i
	if best_diff <= 1.0:
		train.stop_index = nearest
		train.state = Train.State.DWELL
		train.dwell_left = 0.6
		_on_station(train, line, line.stops[nearest])


func _drop_trains(line: MetroLine) -> void:
	if line.trains.is_empty():
		return
	for train in line.trains:
		_rescue_riders(train, line)
	line.trains.clear()


func _rescue_riders(train: Train, line: MetroLine) -> void:
	if train.riders.is_empty():
		return
	if not line.geometry.is_drawable():
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
		# 环线到站后把弧长折回 [0, total)，便于继续从首站出发
		if line.is_loop and line.geometry.total_length > 0.001:
			train.dist = fmod(train.dist, line.geometry.total_length)
		train.state = Train.State.DWELL
		train.dwell_left = Train.DWELL_TIME
		_on_station(train, line, line.stops[train.stop_index])
	else:
		train.dist += signf(train.target_dist - train.dist) * step


func _depart(train: Train, line: MetroLine) -> void:
	if line.is_loop and line.stops.size() >= 3:
		# 环线：单向循环，末站下一站是首站（弧长回绕到全长）
		train.dir = 1
		var next := (train.stop_index + 1) % line.stops.size()
		train.target_index = next
		var target := line.geometry.stop_offsets[next]
		if target <= train.dist:
			target += line.geometry.total_length
		train.target_dist = target
		train.state = Train.State.MOVING
		return
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
	var delivered_here := 0
	for passenger in train.riders:
		if passenger.target_shape == station.shape:
			score += 1
			delivered += 1
			delivered_here += 1
			continue
		# 继续坐 vs 下车换乘：取剩余代价更小的那条路
		var stay := routing.stay_cost(train.line_id, station.id, next_departure, passenger.target_shape)
		var leave := routing.board_cost(station.id, passenger.target_shape)
		if stay <= leave:
			staying.append(passenger)
		else:
			station.waiting.append(passenger)
	train.riders = staying
	if delivered_here > 0:
		passengers_delivered.emit(station, delivered_here)

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
	if line.is_loop and line.stops.size() >= 3:
		return line.stops[(train.stop_index + 1) % line.stops.size()].id
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
			var was_overloading := st.overload_timer > 0.0
			st.overload_timer += dt
			if not was_overloading:
				overload_started.emit(st)
			if level.endless:
				# 无尽模式：计时环会顶满，但不会判负
				st.overload_timer = minf(st.overload_timer, level.overload_grace)
			elif st.overload_timer >= level.overload_grace and not is_over:
				is_over = true
				game_over.emit(st)
				return
		else:
			st.overload_timer = maxf(0.0, st.overload_timer - dt * 1.5)
