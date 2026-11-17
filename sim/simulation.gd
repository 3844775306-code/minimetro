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
## 主循环每帧写入当前相机 zoom；-1 表示测试/无相机时按目标值
var current_camera_zoom := -1.0
## 设计分辨率下的屏幕尺寸（用于把 HUD 顶部安全区换算到世界坐标）
var screen_size := Vector2(2400.0, 1200.0)
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
var inventory_high_speed: int = 0
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
	_station_spawn_timer = station_interval()
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


func is_weekend() -> bool:
	return (day_index() % 7) >= 5


# ---------------------------------------------------------------------------
# 城镇发展：车站类型解锁、数量增长、相机拉远
# ---------------------------------------------------------------------------

## 0=村庄 1=小镇 2=城市 3=大都市 4=都会
func development_stage() -> int:
	var count := network.stations.size()
	if count < 8:
		return 0
	if count < 14:
		return 1
	if count < 20:
		return 2
	if count < 28:
		return 3
	return 4


func stage_name() -> String:
	match development_stage():
		0:
			return Loc.t("村庄", "Village")
		1:
			return Loc.t("小镇", "Town")
		2:
			return Loc.t("城市", "City")
		3:
			return Loc.t("大都市", "Metropolis")
		_:
			return Loc.t("都会", "Cosmopolis")


## 当前阶段允许出现的车站形状与权重：
## 开局固定为居民区/车站/商务区三种基础地标，之后逐步解锁其余 9 种。
func station_shape_weights() -> Dictionary:
	var stage := development_stage()
	var weights := {
		Shape.Kind.CIRCLE: 6.0,
		Shape.Kind.SQUARE: 4.0,
		Shape.Kind.TRIANGLE: 3.0,
	}
	if stage >= 1:
		weights[Shape.Kind.PENTAGON] = 1.2
		weights[Shape.Kind.PLUS] = 1.2
	if stage >= 2:
		weights[Shape.Kind.STAR] = 1.0
		weights[Shape.Kind.HEXAGON] = 1.2
	if stage >= 3:
		weights[Shape.Kind.DIAMOND] = 1.4
		weights[Shape.Kind.SEMICIRCLE] = 1.0
		weights[Shape.Kind.OCTAGON] = 1.0
	if stage >= 4:
		weights[Shape.Kind.RING] = 1.0
		weights[Shape.Kind.CLOVER] = 0.8
	return weights


## 城镇越大，新车站出现得越快。
func station_interval() -> float:
	var factors := [1.5, 1.25, 1.1, 0.95, 0.8]
	return level.station_spawn_interval * float(factors[development_stage()])


## 相机拉远进度：0=开局（较近），1=最远（看到完整 2400×1200 地图）。
func camera_progress() -> float:
	return clampf((float(network.stations.size()) - 3.0) / 32.0, 0.0, 1.0)


## 相机目标缩放：开局 2.0（近看城镇中央），城镇发展后回到 1.0（地图铺满窗口）。
func camera_zoom_target() -> float:
	return lerpf(2.0, 1.0, camera_progress())


## 当前相机可见的世界范围（用于只生成屏幕内的新车站）。
func visible_world_rect() -> Rect2:
	var zoom := maxf(current_camera_zoom if current_camera_zoom > 0.0
		else camera_zoom_target(), 0.01)
	var view_size := level.world_size / zoom
	var centered := Rect2(level.world_size * 0.5 - view_size * 0.5, view_size)
	return centered.intersection(Rect2(Vector2.ZERO, level.world_size))


## 实际用于生成车站的世界矩形：相机可见范围 + 避开顶部 HUD 安全区。
func spawn_world_rect() -> Rect2:
	var rect := visible_world_rect()
	var zoom := maxf(current_camera_zoom if current_camera_zoom > 0.0
		else camera_zoom_target(), 0.01)
	# 屏幕 y=220 以上是顶部 HUD；换到世界坐标后作为生成下界
	var safe_top := level.world_size.y * 0.5 + (220.0 - screen_size.y * 0.5) / zoom
	var bottom := rect.end.y
	var top := clampf(safe_top, rect.position.y, bottom)
	return Rect2(Vector2(rect.position.x, top), Vector2(rect.size.x, maxf(0.0, bottom - top)))


## 高斯型"时段热度"（小时, 中心, 宽度）。
func _bell(hour: float, center: float, width: float) -> float:
	var delta := (hour - center) / maxf(width, 0.1)
	return exp(-delta * delta)


## 某个地标类型的"出门/来客"活跃度（0.05~2.5），早晚高峰明显。
func origin_activity(kind: int) -> float:
	var h := hour_of_day()
	var weekend := 1.0 if is_weekend() else 0.0
	var night := 1.0 if (h < 5.5 or h >= 22.0) else 0.0
	var morning := _bell(h, 7.5, 1.7)
	var evening := _bell(h, 18.0, 1.9)
	var midday := _bell(h, 13.0, 3.5)
	var value := 0.0
	match kind:
		Shape.Kind.CIRCLE:
			value = 0.55 + 1.6 * morning + 0.7 * evening - 0.25 * night
		Shape.Kind.SQUARE:
			value = 0.9 + 0.5 * morning + 0.5 * evening + 0.25 * midday - 0.2 * night
		Shape.Kind.TRIANGLE:
			value = 0.45 + 0.6 * midday + 1.5 * evening - 0.25 * night
		Shape.Kind.PLUS:
			value = 0.35 + 0.6 * midday + 0.3 * evening - 0.2 * night
		Shape.Kind.DIAMOND:
			value = 0.4 + 0.8 * midday + 1.2 * weekend - 0.2 * night
		Shape.Kind.STAR:
			value = 0.5 + 0.9 * midday + 1.0 * weekend - 0.2 * night
		Shape.Kind.PENTAGON:
			value = 0.6 + 0.4 * morning + 0.5 * midday - 0.2 * night - 0.3 * weekend
		Shape.Kind.HEXAGON:
			value = 0.45 + 1.1 * morning + 0.6 * midday - 0.2 * night - 0.2 * weekend
		Shape.Kind.OCTAGON:
			value = 0.35 + 1.2 * evening + 0.7 * weekend - 0.1 * night
		Shape.Kind.RING:
			value = 0.45 + 0.9 * midday + 0.7 * weekend - 0.2 * night
		Shape.Kind.SEMICIRCLE:
			value = 0.4 + 0.8 * midday + 0.5 * weekend - 0.2 * night
		Shape.Kind.CLOVER:
			value = 0.4 + 0.7 * midday + 0.6 * weekend - 0.2 * night
	return maxf(value, 0.05)


## 目的地的"吸引力"：不同地标在不同时段更值得去。
func _target_attraction(kind: int) -> float:
	var h := hour_of_day()
	var weekend := 1.0 if is_weekend() else 0.0
	var night := 1.0 if (h < 5.5 or h >= 22.0) else 0.0
	var morning := _bell(h, 7.5, 1.7)
	var evening := _bell(h, 18.0, 1.9)
	var midday := _bell(h, 13.0, 3.5)
	var value := 0.5
	match kind:
		Shape.Kind.CIRCLE:
			value = 0.5 + 0.9 * evening + 0.2 * midday
		Shape.Kind.SQUARE:
			value = 0.9 + 0.2 * morning + 0.2 * evening
		Shape.Kind.TRIANGLE:
			value = 0.5 + 1.3 * morning + 0.3 * midday
		Shape.Kind.PLUS:
			value = 0.7 + 0.4 * midday
		Shape.Kind.DIAMOND:
			value = 0.5 + 0.7 * midday + 0.9 * weekend - 0.3 * night
		Shape.Kind.STAR:
			value = 0.6 + 0.7 * midday + 0.8 * weekend - 0.3 * night
		Shape.Kind.PENTAGON:
			value = 0.6 + 0.5 * midday - 0.3 * weekend
		Shape.Kind.HEXAGON:
			value = 0.5 + 1.0 * morning + 0.5 * midday - 0.3 * weekend
		Shape.Kind.OCTAGON:
			value = 0.4 + 1.1 * evening + 0.8 * weekend - 0.2 * night
		Shape.Kind.RING:
			value = 0.6 + 0.7 * midday + 0.8 * weekend - 0.2 * night
		Shape.Kind.SEMICIRCLE:
			value = 0.6 + 0.6 * midday + 0.6 * weekend - 0.2 * night
		Shape.Kind.CLOVER:
			value = 0.55 + 0.5 * midday + 0.7 * weekend - 0.2 * night
	return maxf(value, 0.05)


## 各"起点地标"对各"目的地地标"的基础偏好（现实生活里的出行倾向）。
func _role_affinity() -> Dictionary:
	return {
		"residential": {
			"business": 1.0, "transit": 1.0, "hospital": 0.5, "university": 0.5,
			"park": 0.5, "museum": 0.4, "garden": 0.4, "stadium": 0.3,
			"civic": 0.25, "resort": 0.3, "landmark": 0.4, "residential": 0.2,
		},
		"transit": {
			"residential": 1.0, "business": 0.8, "university": 0.5, "stadium": 0.5,
			"park": 0.4, "museum": 0.4, "garden": 0.3, "hospital": 0.4,
			"civic": 0.3, "resort": 0.5, "landmark": 0.5, "transit": 0.2,
		},
		"business": {
			"residential": 1.0, "transit": 1.0, "hospital": 0.3, "university": 0.3,
			"civic": 0.5, "stadium": 0.4, "museum": 0.4, "park": 0.35,
			"garden": 0.3, "resort": 0.3, "landmark": 0.4, "business": 0.2,
		},
		"hospital": {
			"residential": 1.0, "transit": 0.7, "park": 0.5, "garden": 0.4,
			"museum": 0.3, "university": 0.3, "hospital": 0.2, "civic": 0.3,
			"business": 0.25, "resort": 0.2, "landmark": 0.3,
		},
		"resort": {
			"transit": 1.0, "landmark": 0.8, "park": 0.6, "stadium": 0.4,
			"garden": 0.5, "museum": 0.5, "residential": 0.5, "business": 0.3,
			"hospital": 0.2, "resort": 0.2,
		},
		"landmark": {
			"transit": 1.0, "resort": 0.7, "park": 0.6, "museum": 0.6,
			"garden": 0.5, "residential": 0.5, "business": 0.35, "hospital": 0.2,
			"stadium": 0.4,
		},
		"university": {
			"transit": 1.0, "park": 0.5, "museum": 0.5, "garden": 0.4,
			"residential": 0.5, "business": 0.3, "stadium": 0.4, "civic": 0.25,
			"hospital": 0.2, "resort": 0.3, "landmark": 0.4, "university": 0.2,
		},
		"civic": {
			"transit": 1.0, "museum": 0.5, "park": 0.4, "residential": 0.4,
			"business": 0.5, "hospital": 0.3, "university": 0.3, "stadium": 0.3,
			"garden": 0.35, "landmark": 0.4, "resort": 0.3,
		},
		"stadium": {
			"transit": 1.0, "residential": 0.4, "park": 0.4, "business": 0.35,
			"hospital": 0.2, "university": 0.3, "museum": 0.3, "garden": 0.3,
			"stadium": 0.2, "resort": 0.3, "landmark": 0.4,
		},
		"park": {
			"transit": 1.0, "residential": 0.6, "museum": 0.5, "garden": 0.5,
			"university": 0.4, "business": 0.3, "hospital": 0.25, "stadium": 0.3,
			"landmark": 0.4, "resort": 0.4, "park": 0.2,
		},
		"museum": {
			"transit": 1.0, "park": 0.5, "garden": 0.5, "residential": 0.5,
			"university": 0.4, "business": 0.35, "hospital": 0.2, "landmark": 0.4,
			"stadium": 0.25, "museum": 0.2,
		},
		"garden": {
			"transit": 1.0, "park": 0.7, "museum": 0.5, "residential": 0.4,
			"university": 0.35, "hospital": 0.2, "business": 0.2, "stadium": 0.25,
			"landmark": 0.4, "resort": 0.3, "garden": 0.2,
		},
	}


## 某地标类型的乘客"想去哪"：目的地吸引力 × 起点地标的出行偏好。
func destination_weights(origin_shape: int) -> Dictionary:
	var affinity: Dictionary = _role_affinity().get(Shape.landmark_role(origin_shape), {})
	var weights := {}
	for kind in [
		Shape.Kind.CIRCLE, Shape.Kind.SQUARE, Shape.Kind.TRIANGLE,
		Shape.Kind.PLUS, Shape.Kind.DIAMOND, Shape.Kind.STAR,
		Shape.Kind.PENTAGON, Shape.Kind.HEXAGON, Shape.Kind.OCTAGON,
		Shape.Kind.RING, Shape.Kind.SEMICIRCLE, Shape.Kind.CLOVER,
	]:
		var target_role := Shape.landmark_role(kind)
		var base := float(affinity.get(target_role, 0.25))
		weights[kind] = maxf(0.01, base * _target_attraction(kind))
	if weights.has(origin_shape):
		weights[origin_shape] = 0.0
	return weights
func total_trains_owned() -> int:
	return inventory_trains + inventory_high_speed + network.train_count()


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
		"express":
			inventory_high_speed += 1
		"carriage":
			inventory_carriages += 1
		"bridge":
			level.start_bridges = mini(level.start_bridges + 1, level.max_bridges)
		"interchange":
			inventory_interchanges += 1
		_:
			push_warning("未知的升级卡: " + card_id)


## 从库存拖一辆列车到线路上的任意位置；high_speed=true 时放入新干线。
func place_train(line: MetroLine, pos: Vector2, high_speed: bool = false) -> bool:
	if line == null:
		return false
	if high_speed:
		if inventory_high_speed <= 0:
			return false
	else:
		if inventory_trains <= 0:
			return false
	if line.stops.size() < 2 or not line.geometry.is_drawable():
		return false
	if high_speed:
		inventory_high_speed -= 1
	else:
		inventory_trains -= 1
	_spawn_train_at(line, pos, high_speed)
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


## 把列车放到线路上的任意弧长位置；车头朝向距离最近的站台。
func _place_train_at(train: Train, line: MetroLine, pos: Vector2) -> void:
	var total := line.geometry.total_length
	var d := clampf(line.geometry.nearest_distance(pos), 0.0, total)
	train.dist = d
	train.speed = 0.0
	train.state = Train.State.MOVING
	train.dwell_left = 0.0
	var offsets := line.geometry.stop_offsets
	var nearest := 0
	var best_diff := INF
	for i in offsets.size():
		var diff := absf(offsets[i] - d)
		if diff < best_diff:
			best_diff = diff
			nearest = i
	if line.is_loop and line.stops.size() >= 3:
		var target := offsets[nearest]
		if target <= d:
			target += total
		train.dir = 1
		train.target_index = nearest
		train.target_dist = target
		return
	var station_offset := offsets[nearest]
	if absf(station_offset - d) < 1.0:
		# 正好落在站上：朝向下一站（末站则朝前一站）
		if nearest < line.stops.size() - 1:
			train.dir = 1
			train.target_index = nearest + 1
			train.target_dist = offsets[nearest + 1]
		else:
			train.dir = -1
			train.target_index = nearest - 1
			train.target_dist = offsets[nearest - 1]
	else:
		train.dir = 1 if station_offset > d else -1
		train.target_index = nearest
		train.target_dist = station_offset


func _roll_cards() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if network.lines.size() < level.max_lines:
		pool.append(UpgradeCards.get_card("line"))
	if total_trains_owned() < level.max_trains:
		pool.append(UpgradeCards.get_card("train"))
		pool.append(UpgradeCards.get_card("express"))
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
		_station_spawn_timer = station_interval()
		spawner.spawn_rect = spawn_world_rect()
		spawner.try_spawn(network, station_shape_weights())

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


## 按"地标活跃度"选起点，再按该地标类型在当前时段的出行规律选目的地：
## 居民区早高峰去商务区/车站，商务区晚高峰回居民区，周末更多去度假区/景点。
func _spawn_passenger() -> void:
	var stations := network.stations
	if stations.size() < 2:
		return
	var station_weights: Array[float] = []
	var total := 0.0
	for st in stations:
		var weight := (1.0 + st.line_ids.size() * 2.0) * origin_activity(st.shape)
		station_weights.append(weight)
		total += weight
	if total <= 0.0:
		return
	var r := rng.randf() * total
	var chosen: Station = stations[0]
	for i in stations.size():
		r -= station_weights[i]
		if r <= 0.0:
			chosen = stations[i]
			break

	var counts := {}
	for st in stations:
		counts[st.shape] = int(counts.get(st.shape, 0)) + 1
	var destination := destination_weights(chosen.shape)
	var shapes: Array[int] = []
	var shape_weights: Array[float] = []
	var weight_total := 0.0
	for raw_shape in destination.keys():
		var shape := int(raw_shape)
		if shape == chosen.shape or not counts.has(shape):
			continue
		var weight := maxf(0.0, float(destination[raw_shape]))
		if weight <= 0.0:
			continue
		shapes.append(shape)
		shape_weights.append(weight)
		weight_total += weight
	if weight_total <= 0.0:
		# 兜底：目的地类型尚未在城镇出现时，按现有形状数量加权
		for raw_shape in counts.keys():
			var shape := int(raw_shape)
			if shape == chosen.shape:
				continue
			shapes.append(shape)
			shape_weights.append(float(counts[shape]))
			weight_total += float(counts[shape])
	if weight_total <= 0.0:
		return
	var pick := rng.randf() * weight_total
	for i in shapes.size():
		pick -= shape_weights[i]
		if pick <= 0.0:
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


func _spawn_train_at(line: MetroLine, pos: Vector2, high_speed: bool = false) -> void:
	var train := Train.new()
	train.id = _train_id
	_train_id += 1
	train.line_id = line.id
	train.line_version = line.version
	train.high_speed = high_speed
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
		train.speed = 0.0
		_begin_stop(train, line, line.stops[nearest])
		train.state = Train.State.DWELL


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
	if train.relocating:
		_update_relocating_train(train, line, dt)
		return
	if train.legacy_active:
		_update_legacy_train(train, line, dt)
		return
	if train.line_version != line.version or train.stop_index >= line.stops.size():
		if train.line_version >= 0 and train.line_version != line.version \
				and line.edit_legacy_valid and line.edit_legacy_geometry != null:
			_start_legacy(train, line)
		else:
			_remap_train(train, line)
		return

	if train.state == Train.State.DWELL:
		var station: Station = line.stops[train.stop_index] \
			if train.stop_index >= 0 and train.stop_index < line.stops.size() else null
		if station != null and not train.stop_actions.is_empty():
			train.action_timer -= dt
			if train.action_timer <= 0.0:
				_perform_next_stop_action(train, station)
				train.action_timer += train.action_interval
		train.dwell_left -= dt
		if train.dwell_left <= 0.0 and train.stop_actions.is_empty():
			_depart(train, line)
		return

	var delta := _target_gap(train)
	if delta <= 0.001:
		_arrive(train, line)
		return
	# 目标速度：最高速 / 前方弯道限速 / 需要停站时的刹车曲线，取最小
	var desired := train.speed_limit()
	var lookahead := train.speed * train.speed / (2.0 * Train.DECEL) + 40.0
	for entry in line.geometry.curve_entries_ahead(train.dist, train.dir, lookahead):
		var limit := entry.y * train.speed_limit()
		var allowed := sqrt(limit * limit + 2.0 * Train.DECEL * maxf(entry.x, 0.0))
		desired = minf(desired, allowed)
	if _need_stop(train, line) or _is_terminal(train, line):
		desired = minf(desired, sqrt(maxf(2.0 * Train.DECEL * delta, 0.0)))

	# 速度不能突变：只按 ACCEL / DECEL 变化
	if desired < train.speed:
		train.speed = maxf(desired, train.speed - Train.DECEL * dt)
	else:
		train.speed = minf(desired, train.speed + Train.ACCEL * dt)
	train.speed = maxf(train.speed, 0.0)

	var step := train.speed * dt
	if step >= delta:
		train.dist = train.target_dist
		_arrive(train, line)
	else:
		train.dist += float(train.dir) * step


## 到下一个目标站还有多远（正值；环线 target 可能已加大过全长）。
func _target_gap(train: Train) -> float:
	return (train.target_dist - train.dist) * float(train.dir)


## 到站：需要停车就上下客并停 0.5s×人数；无人上下车则保持速度直接驶过。
func _arrive(train: Train, line: MetroLine) -> void:
	train.stop_index = train.target_index
	var station: Station = line.stops[train.stop_index]
	var terminal := _is_terminal(train, line)
	var needed := _need_stop(train, line)
	if line.is_loop and line.geometry.total_length > 0.001:
		train.dist = fmod(train.dist, line.geometry.total_length)
	if needed or terminal:
		train.speed = 0.0
		_begin_stop(train, line, station)
		train.state = Train.State.DWELL
	else:
		# 无人上下车：不停站，保持当前速度继续开往下一站
		_depart(train, line)


## 终点站（开放线路的首/末站）必须停一下好掉头；环线没有终点。
func _is_terminal(train: Train, line: MetroLine) -> bool:
	if line.is_loop:
		return false
	return train.target_index == 0 or train.target_index == line.stops.size() - 1


## 从"当前站 + 方向"取下一个停靠站的站序；到端点时自动反向（对应掉头）。
func _next_station_index(line: MetroLine, station_index: int, dir: int) -> int:
	if line.is_loop and line.stops.size() >= 3:
		return (station_index + 1) % line.stops.size()
	var next := station_index + dir
	if next < 0 or next >= line.stops.size():
		next = station_index - dir
	if next < 0 or next >= line.stops.size():
		return -1
	return next


## 预测在某个站会不会有人上下车（用于提前刹车/决定是否驶过）。
func _need_stop(train: Train, line: MetroLine) -> bool:
	if train.target_index < 0 or train.target_index >= line.stops.size():
		return true
	return _station_activity(train, line, train.target_index) > 0


func _station_activity(train: Train, line: MetroLine, station_index: int) -> int:
	var station: Station = line.stops[station_index]
	var next_index := _next_station_index(line, station_index, train.dir)
	var next_id := -1 if next_index < 0 else line.stops[next_index].id
	var alight := 0
	for passenger in train.riders:
		if passenger.target_shape == station.shape:
			alight += 1
			continue
		if next_id < 0:
			alight += 1
			continue
		var stay := routing.stay_cost(train.line_id, station.id, next_id, passenger.target_shape)
		var leave := routing.board_cost(station.id, passenger.target_shape)
		if stay > leave:
			alight += 1
	var activity := alight
	var capacity_left := train.capacity - (train.riders.size() - alight)
	if capacity_left > 0 and next_id >= 0:
		for waiting in station.waiting:
			var choice := routing.next_for(station.id, waiting.target_shape)
			if int(choice.get("line", -1)) == train.line_id \
					and int(choice.get("station", -1)) == next_id:
				activity += 1
				capacity_left -= 1
				if capacity_left <= 0:
					break
	return activity


func _depart(train: Train, line: MetroLine) -> void:
	if train.stop_index >= 0 and train.stop_index < line.stops.size():
		line.stops[train.stop_index].boarding = false
	train.stop_actions.clear()
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
		return
	train.target_index = next
	train.target_dist = line.geometry.stop_offsets[next]
	train.state = Train.State.MOVING


## 到站：先下（含送达/换乘），再上；把每个动作排进 0.5s 队列逐个执行。
func _begin_stop(train: Train, line: MetroLine, station: Station) -> void:
	var next_departure := _next_departure_station_id(train, line)
	train.stop_actions.clear()
	# 换乘枢纽的上下客更快：每人 0.3s，普通站 0.5s
	var interval := Train.DWELL_PER_PASSENGER_INTERCHANGE if station.capacity > 6 \
		else Train.DWELL_PER_PASSENGER
	train.action_interval = interval
	train.action_timer = interval
	station.boarding = false

	var staying: Array[Passenger] = []
	for passenger in train.riders:
		if passenger.target_shape == station.shape:
			train.stop_actions.append({"kind": "deliver", "passenger": passenger})
			continue
		# 继续坐 vs 下车换乘：取剩余代价更小的那条路
		var stay := routing.stay_cost(train.line_id, station.id, next_departure, passenger.target_shape)
		var leave := routing.board_cost(station.id, passenger.target_shape)
		if stay <= leave:
			staying.append(passenger)
		else:
			train.stop_actions.append({"kind": "transfer", "passenger": passenger})

	# 先下后上：容量按"下完客后仍在车上的人"预留
	var capacity_left := train.capacity - staying.size()
	if capacity_left > 0 and not station.waiting.is_empty():
		for passenger in station.waiting:
			if capacity_left <= 0:
				break
			if _passenger_claimed_elsewhere(passenger, train):
				continue
			var choice := routing.next_for(station.id, passenger.target_shape)
			if not choice.is_empty() \
					and int(choice["line"]) == train.line_id \
					and int(choice["station"]) == next_departure:
				train.stop_actions.append({"kind": "board", "passenger": passenger})
				capacity_left -= 1

	train.dwell_left = float(train.stop_actions.size()) * interval
	if not train.stop_actions.is_empty():
		station.boarding = true
		# 第一名立刻上下，之后每 0.5s（换乘枢纽 0.3s）一名
		_perform_next_stop_action(train, station)
		train.action_timer = interval
	if train.stop_actions.is_empty() and train.dwell_left <= 0.0:
		station.boarding = false


## 执行一名的下车/送达/上车；视图会随着等待队列与车内乘客数量逐个变化。
func _perform_next_stop_action(train: Train, station: Station) -> void:
	if train.stop_actions.is_empty():
		return
	var action: Dictionary = train.stop_actions.pop_front()
	var passenger: Passenger = action["passenger"]
	match String(action["kind"]):
		"deliver":
			_remove_rider(train, passenger)
			score += 1
			delivered += 1
			passengers_delivered.emit(station, 1)
		"transfer":
			_remove_rider(train, passenger)
			station.waiting.append(passenger)
		"board":
			var index := station.waiting.find(passenger)
			if index >= 0:
				station.waiting.remove_at(index)
			train.riders.append(passenger)


func _remove_rider(train: Train, passenger: Passenger) -> void:
	var index := train.riders.find(passenger)
	if index >= 0:
		train.riders.remove_at(index)


## 同一名等待乘客可能被同时到站的两列车选中；上下客改成逐个后需要做占用标记。
func _passenger_claimed_elsewhere(passenger: Passenger, except_train: Train) -> bool:
	for line in network.lines:
		for other in line.trains:
			if other == except_train:
				continue
			for action in other.stop_actions:
				if String(action["kind"]) == "board" and action["passenger"] == passenger:
					return true
	return false


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
	train.stop_actions.clear()
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
# 拖动列车到别处：先停靠最近站下客，再移动到目标位置（目标位置显示浅色车）
# ---------------------------------------------------------------------------

func request_train_relocation(train: Train, from_line: MetroLine, to_line: MetroLine,
		pos: Vector2) -> bool:
	if train == null or from_line == null or to_line == null:
		return false
	if train.relocating or train.legacy_active:
		return false
	if to_line.stops.size() < 2 or not to_line.geometry.is_drawable():
		return false
	if to_line == from_line and absf(to_line.geometry.nearest_distance(pos) - train.dist) < 20.0:
		return false
	train.relocating = true
	train.relocate_line_id = to_line.id
	train.relocate_pos = pos
	train.relocate_docked = false
	train.speed = 0.0
	train.stop_actions.clear()
	if train.stop_index >= 0 and train.stop_index < from_line.stops.size():
		from_line.stops[train.stop_index].boarding = false
	train.dwell_left = 0.0
	train.state = Train.State.MOVING
	# 先在当前线路上找最近站
	var offsets := from_line.geometry.stop_offsets
	var nearest := 0
	var best := INF
	var clamped := clampf(train.dist, 0.0, from_line.geometry.total_length)
	for i in offsets.size():
		var diff := absf(offsets[i] - clamped)
		if diff < best:
			best = diff
			nearest = i
	train.stop_index = nearest
	var station_offset := offsets[nearest]
	if best <= 1.0:
		_unload_for_relocation(train, from_line, nearest)
	else:
		train.dir = 1 if station_offset > train.dist else -1
		train.target_index = nearest
		train.target_dist = station_offset
	return true


func _update_relocating_train(train: Train, line: MetroLine, dt: float) -> void:
	if train.relocate_docked:
		train.dwell_left -= dt
		if train.dwell_left <= 0.0:
			_finish_relocation(train, line)
		return
	var delta := _target_gap(train)
	if delta <= 0.001:
		_unload_for_relocation(train, line, train.target_index)
		return
	var desired := minf(train.speed_limit(), sqrt(maxf(2.0 * Train.DECEL * delta, 0.0)))
	var lookahead := train.speed * train.speed / (2.0 * Train.DECEL) + 40.0
	for entry in line.geometry.curve_entries_ahead(train.dist, train.dir, lookahead):
		var limit := entry.y * train.speed_limit()
		var allowed := sqrt(limit * limit + 2.0 * Train.DECEL * maxf(entry.x, 0.0))
		desired = minf(desired, allowed)
	if desired < train.speed:
		train.speed = maxf(desired, train.speed - Train.DECEL * dt)
	else:
		train.speed = minf(desired, train.speed + Train.ACCEL * dt)
	var step := train.speed * dt
	if step >= delta:
		train.dist = train.target_dist
		_unload_for_relocation(train, line, train.target_index)
	else:
		train.dist += float(train.dir) * step


## 到最近站：所有乘客下车进站台队列（换乘/重新排队由路由处理）。
func _unload_for_relocation(train: Train, line: MetroLine, station_index: int) -> void:
	var station: Station = line.stops[station_index]
	var count := train.riders.size()
	for passenger in train.riders:
		station.waiting.append(passenger)
	train.riders.clear()
	train.speed = 0.0
	train.stop_index = station_index
	train.state = Train.State.DWELL
	train.dwell_left = float(count) * Train.DWELL_PER_PASSENGER
	train.relocate_docked = true


func _finish_relocation(train: Train, from_line: MetroLine) -> void:
	var target_line := network.line_by_id(train.relocate_line_id)
	train.relocating = false
	train.relocate_docked = false
	if from_line != null:
		from_line.trains.erase(train)
	if target_line == null or target_line.stops.size() < 2 \
			or not target_line.geometry.is_drawable():
		if from_line != null:
			from_line.trains.append(train)
			_remap_train(train, from_line)
		return
	target_line.trains.append(train)
	train.line_id = target_line.id
	train.line_version = target_line.version
	_place_train_at(train, target_line, train.relocate_pos)
	network.touch()


# ---------------------------------------------------------------------------
# 手动编辑线路后的"旧线收尾"：列车沿编辑前的线路行驶完，旧线画淡
# ---------------------------------------------------------------------------

## 编辑发生时：只有"旧线与新线不一样的那一段"上的列车才进入旧线收尾。
func _start_legacy(train: Train, line: MetroLine) -> void:
	var geometry := line.edit_legacy_geometry
	var old_stops := line.edit_legacy_stops
	if geometry == null or old_stops.size() < 2 or not geometry.is_drawable():
		_remap_train(train, line)
		return
	var ranges := _legacy_changed_ranges(geometry, old_stops, line.edit_legacy_flips,
		line.stops, line.bend_flips, line.is_loop)
	var found := Vector2(-1.0, -1.0)
	for candidate in ranges:
		if train.dist > candidate.x + 1.0 and train.dist < candidate.y - 1.0:
			found = candidate
			break
	if found.x < 0.0:
		# 列车在没变的那一段上（或线路没有实质变化）：直接按新线重映射
		_remap_train(train, line)
		return
	var start_offset: float = found.x
	var end_offset: float = found.y
	train.legacy_geometry = geometry
	train.legacy_stops = old_stops.duplicate()
	train.legacy_active = true
	train.legacy_finishing = false
	train.legacy_range_start = start_offset
	train.legacy_range_end = end_offset
	train.line_version = line.version
	train.dist = clampf(train.dist, 0.0, geometry.total_length)
	train.speed = 0.0
	train.dwell_left = 0.0
	train.state = Train.State.MOVING
	var offsets := geometry.stop_offsets
	var next := -1
	if train.dir >= 0:
		for i in offsets.size():
			if offsets[i] >= train.dist - 1.0:
				next = i
				break
	else:
		for i in range(offsets.size() - 1, -1, -1):
			if offsets[i] <= train.dist + 1.0:
				next = i
				break
	if next < 0:
		_finish_legacy(train, line)
		return
	train.stop_index = next
	train.target_index = next
	train.target_dist = offsets[next]
	if geometry.is_loop_geometry and train.target_dist < train.dist:
		train.target_dist += geometry.total_length
	train.legacy_lap_remaining = old_stops.size() if geometry.is_loop_geometry else 0


## 对比每条"相邻站对"是否在新线里仍是同一段（含弯曲方向一致），
## 返回旧几何上真正变化的若干弧长区间（可处理改弯曲方向、增删站、换序）。
func _legacy_changed_ranges(geometry: LineGeometry, old_stops: Array[Station],
		old_flips: Dictionary, new_stops: Array[Station], new_flips: Dictionary,
		loop: bool) -> Array[Vector2]:
	var new_pairs := {}
	var new_size := new_stops.size()
	for i in range(new_size - 1):
		var key := _pair_key(new_stops[i], new_stops[i + 1])
		new_pairs[key] = new_flips.has(key)
	if loop and new_size >= 3:
		var key := _pair_key(new_stops[new_size - 1], new_stops[0])
		new_pairs[key] = new_flips.has(key)
	var changed: Array[Vector2] = []
	var old_size := old_stops.size()
	for i in range(old_size - 1):
		var key := _pair_key(old_stops[i], old_stops[i + 1])
		var same := new_pairs.has(key) and bool(new_pairs[key]) == old_flips.has(key)
		if not same:
			changed.append(Vector2(geometry.stop_offsets[i], geometry.stop_offsets[i + 1]))
	if loop and old_size >= 3:
		var key := _pair_key(old_stops[old_size - 1], old_stops[0])
		var same := new_pairs.has(key) and bool(new_pairs[key]) == old_flips.has(key)
		if not same:
			changed.append(Vector2(geometry.stop_offsets[old_size - 1], geometry.total_length))
	if changed.is_empty():
		return changed
	changed.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for segment in changed:
		if merged.is_empty():
			merged.append(segment)
			continue
		var last: Vector2 = merged[merged.size() - 1]
		if segment.x <= last.y + 1.0:
			merged[merged.size() - 1] = Vector2(last.x, maxf(last.y, segment.y))
		else:
			merged.append(segment)
	return merged


static func _pair_key(a: Station, b: Station) -> String:
	return "%d>%d" % [a.id, b.id]


func _legacy_at_boundary(train: Train, offset: float) -> bool:
	return offset <= train.legacy_range_start + 1.0 or offset >= train.legacy_range_end - 1.0


func _update_legacy_train(train: Train, line: MetroLine, dt: float) -> void:
	var geometry := train.legacy_geometry
	if geometry == null:
		_finish_legacy(train, line)
		return
	if train.state == Train.State.DWELL:
		train.dwell_left -= dt
		if train.dwell_left <= 0.0:
			if train.legacy_finishing:
				_finish_legacy(train, line)
			else:
				_legacy_depart(train, line)
		return

	var delta := _target_gap(train)
	if delta <= 0.001:
		_legacy_arrive(train, line)
		return
	var desired := train.speed_limit()
	var lookahead := train.speed * train.speed / (2.0 * Train.DECEL) + 40.0
	for entry in geometry.curve_entries_ahead(train.dist, train.dir, lookahead):
		var limit := entry.y * train.speed_limit()
		var allowed := sqrt(limit * limit + 2.0 * Train.DECEL * maxf(entry.x, 0.0))
		desired = minf(desired, allowed)
	if _legacy_need_stop(train) or _legacy_terminal(train, geometry):
		desired = minf(desired, sqrt(maxf(2.0 * Train.DECEL * delta, 0.0)))
	if desired < train.speed:
		train.speed = maxf(desired, train.speed - Train.DECEL * dt)
	else:
		train.speed = minf(desired, train.speed + Train.ACCEL * dt)
	train.speed = maxf(train.speed, 0.0)
	var step := train.speed * dt
	if step >= delta:
		train.dist = train.target_dist
		_legacy_arrive(train, line)
	else:
		train.dist += float(train.dir) * step


func _legacy_terminal(train: Train, geometry: LineGeometry) -> bool:
	if geometry.is_loop_geometry:
		return false
	return train.target_index == 0 or train.target_index == train.legacy_stops.size() - 1


func _legacy_need_stop(train: Train) -> bool:
	if train.legacy_stops.is_empty():
		return true
	var station: Station = train.legacy_stops[train.target_index]
	if not train.legacy_geometry.is_loop_geometry:
		var offset := train.legacy_geometry.stop_offsets[train.target_index]
		if _legacy_at_boundary(train, offset):
			return true
	for passenger in train.riders:
		if passenger.target_shape == station.shape:
			return true
	return false


func _legacy_arrive(train: Train, line: MetroLine) -> void:
	var geometry := train.legacy_geometry
	if geometry == null:
		_finish_legacy(train, line)
		return
	train.stop_index = train.target_index
	var station: Station = train.legacy_stops[train.stop_index]
	if geometry.is_loop_geometry and geometry.total_length > 0.001:
		train.dist = fmod(train.dist, geometry.total_length)
	var terminal := _legacy_terminal(train, geometry)
	var boundary := false
	if not geometry.is_loop_geometry:
		boundary = _legacy_at_boundary(train, geometry.stop_offsets[train.stop_index])
	var delivered_count := _legacy_deliver(train, station)
	if geometry.is_loop_geometry:
		train.legacy_lap_remaining = maxi(train.legacy_lap_remaining - 1, 0)
		if train.legacy_lap_remaining <= 0:
			train.legacy_finishing = true
	if terminal or boundary:
		train.legacy_finishing = true
	if delivered_count > 0 or terminal or boundary or train.legacy_finishing:
		train.speed = 0.0
		train.state = Train.State.DWELL
		train.dwell_left = float(delivered_count) * Train.DWELL_PER_PASSENGER
		if train.legacy_finishing and delivered_count == 0:
			train.dwell_left = 0.0
	else:
		_legacy_depart(train, line)


## 旧线行驶期间只做"到站送达"：不再接新客/换乘（线路已经改过，路由表也变了）。
func _legacy_deliver(train: Train, station: Station) -> int:
	var staying: Array[Passenger] = []
	var delivered_count := 0
	for passenger in train.riders:
		if passenger.target_shape == station.shape:
			score += 1
			delivered += 1
			delivered_count += 1
		else:
			staying.append(passenger)
	train.riders = staying
	if delivered_count > 0:
		passengers_delivered.emit(station, delivered_count)
	return delivered_count


func _legacy_depart(train: Train, line: MetroLine) -> void:
	var geometry := train.legacy_geometry
	if geometry == null:
		_finish_legacy(train, line)
		return
	if geometry.is_loop_geometry:
		train.dir = 1
		var next := (train.stop_index + 1) % train.legacy_stops.size()
		train.target_index = next
		var target := geometry.stop_offsets[next]
		if target <= train.dist:
			target += geometry.total_length
		train.target_dist = target
		train.state = Train.State.MOVING
		return
	var next := train.stop_index + train.dir
	if next < 0 or next >= train.legacy_stops.size():
		_finish_legacy(train, line)
		return
	train.target_index = next
	train.target_dist = geometry.stop_offsets[next]
	train.state = Train.State.MOVING


func _finish_legacy(train: Train, line: MetroLine) -> void:
	train.legacy_active = false
	train.legacy_finishing = false
	train.legacy_geometry = null
	train.legacy_stops = []
	train.legacy_lap_remaining = 0
	train.line_version = line.version
	train.speed = 0.0
	train.state = Train.State.DWELL
	train.dwell_left = 0.0
	var offsets := line.geometry.stop_offsets
	var nearest := 0
	var best := INF
	for i in offsets.size():
		var diff := absf(offsets[i] - clampf(train.dist, 0.0, line.geometry.total_length))
		if diff < best:
			best = diff
			nearest = i
	if offsets.size() > 0:
		train.stop_index = nearest
		train.target_index = nearest
		train.dist = offsets[nearest]
		train.target_dist = train.dist


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
