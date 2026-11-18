extends Node
## 全局运行态：一局的模型、种子、模式、城市地图、倍速。
## 刻意保持很薄：模型逻辑都在 model/ 与 sim/ 里，测试可以完全绕开单例。

var network: MetroNetwork = null
var level: LevelData = null
var run_seed: int = 0
var rng := RandomNumberGenerator.new()
var speed: float = 1.0
var paused: bool = false
## 本次程序启动是否已经播放过启动动画（返回菜单不重复播放）
var intro_played: bool = false

## 当前运行配置（资源获取 × 无尽 × 管理；特殊模式 daily/tutorial）。
var config: RunConfig = RunConfig.classic()
## 兼容旧代码的派生值（每日/教程/发展/无尽/管理）
var mode: int = GameMode.Kind.CLASSIC
var mode_key: String = "classic"
var daily_date: String = ""
var city: CityMap = null
var city_id: String = "paper"

## 模式/城市菜单选择后、reload 前暂存的目标（-1 / "" = 直接开局）。
var pending_mode: int = -1
var pending_config: RunConfig = null
var pending_city: String = ""


func start_run(p_seed: int = 0, p_mode: int = -1) -> void:
	var cfg: RunConfig
	if p_mode >= 0:
		cfg = RunConfig.from_legacy_mode(p_mode)
	elif pending_config != null:
		cfg = pending_config.duplicate_config()
	else:
		cfg = config.duplicate_config()
	config = cfg
	if config.is_daily():
		mode = GameMode.Kind.DAILY
	elif config.is_tutorial():
		mode = GameMode.Kind.TUTORIAL
	elif config.is_development():
		mode = GameMode.Kind.DEVELOPMENT
	elif config.endless:
		mode = GameMode.Kind.ENDLESS
	elif config.manager:
		mode = GameMode.Kind.MANAGER
	else:
		mode = GameMode.Kind.CLASSIC
	mode_key = config.key()
	daily_date = GameMode.today() if config.is_daily() else ""

	city_id = pending_city if pending_city != "" else CityMaps.default_city_id()
	pending_city = ""
	if config.is_daily():
		# 每日挑战随机抽一张官方地图，不跟随菜单里选的城市
		var official: Array[CityMap] = []
		for candidate in CityMaps.all():
			if not candidate.is_custom:
				official.append(candidate)
		if not official.is_empty():
			city_id = official[GameMode.daily_city_index(daily_date, official.size())].id
	if config.is_tutorial():
		city_id = CityMaps.default_city_id()
	city = CityMaps.get_city(city_id)
	if config.is_daily() and has_node("/root/Save"):
		get_node("/root/Save").mark_daily_attempt(daily_date)

	if p_seed != 0:
		run_seed = p_seed
	elif config.is_daily():
		run_seed = GameMode.daily_seed(daily_date)
	else:
		run_seed = int(Time.get_unix_time_from_system())
	rng.seed = run_seed

	level = LevelData.new()
	level.endless = config.endless
	level.start_lines = city.start_lines
	level.start_trains = city.start_trains
	level.start_bridges = city.start_bridges
	if config.is_development():
		# 发展资源：靠送达收入买资源，不发周奖励；是否判负由无尽轴决定
		level.development_mode = true
		level.start_coins = 30
		level.week_seconds = 999999.0
	if config.manager:
		# 管理开局：40 站、7 线、5 隧道的固定沙盘
		level.manager_mode = true
		level.no_station_spawn = true
		level.start_lines = 7
		level.start_trains = 7
		level.start_bridges = 5
		level.max_trains = 7
		level.station_margin = 150.0
	if config.is_tutorial():
		# 新手教程：固定站、无随机生成、无周结算、不会因拥堵结束
		level.start_lines = 1
		level.start_trains = 0
		level.start_carriages = 0
		level.start_bridges = 0
		level.max_lines = 2
		level.max_trains = 6
		level.max_carriages = 1
		level.max_bridges = 2
		level.max_stations = 5
		level.no_station_spawn = true
		level.station_spawn_interval = 999999.0
		level.passenger_spawn_start = 999999.0
		level.passenger_spawn_end = 999999.0
		level.week_seconds = 999999.0
		level.overload_grace = 999999.0
	level.rivers.clear()
	if config.is_tutorial():
		# 教程用一条简单竖向河流，后面用桥跨过去
		level.rivers.append(CityMaps.editor_band(PackedVector2Array([
			Vector2(1560, 180), Vector2(1560, 1020),
		]), 130.0))
	else:
		for river in city.rivers:
			level.rivers.append(river)
	network = MetroNetwork.new(level)
	speed = 1.0
	paused = false
	pending_mode = -1
	pending_config = null


func is_endless() -> bool:
	return config.endless


func is_daily() -> bool:
	return config.is_daily()


func is_tutorial() -> bool:
	return config.is_tutorial()


func is_manager() -> bool:
	return config.manager


func is_development() -> bool:
	return config.is_development()


## 本局主分数：无尽取最高 30 秒指标，发展非无尽取累计金币，其余取送达人数。
func score_value(sim: Simulation) -> int:
	if sim == null:
		return 0
	if config.endless:
		return sim.endless_best_value()
	if config.is_development():
		return sim.coins_earned
	return sim.score
