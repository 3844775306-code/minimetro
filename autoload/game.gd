extends Node
## 全局运行态：一局的模型、种子、模式、城市地图、倍速。
## 刻意保持很薄：模型逻辑都在 model/ 与 sim/ 里，测试可以完全绕开单例。

var network: MetroNetwork = null
var level: LevelData = null
var run_seed: int = 0
var rng := RandomNumberGenerator.new()
var speed: float = 1.0
var paused: bool = false

## 当前模式（GameMode.Kind）、每日挑战日期、城市地图。
var mode: int = GameMode.Kind.CLASSIC
var mode_key: String = "classic"
var daily_date: String = ""
var city: CityMap = null
var city_id: String = "paper"

## 模式/城市菜单选择后、reload 前暂存的目标（-1 / "" = 直接开局）。
var pending_mode: int = -1
var pending_city: String = ""


func start_run(p_seed: int = 0, p_mode: int = -1) -> void:
	mode = p_mode if p_mode >= 0 else pending_mode
	if mode < 0:
		mode = GameMode.Kind.CLASSIC
	mode_key = GameMode.key(mode)
	daily_date = GameMode.today() if mode == GameMode.Kind.DAILY else ""

	city_id = pending_city if pending_city != "" else CityMaps.default_city_id()
	pending_city = ""
	city = CityMaps.get_city(city_id)

	if p_seed != 0:
		run_seed = p_seed
	elif mode == GameMode.Kind.DAILY:
		run_seed = GameMode.daily_seed(daily_date)
	else:
		run_seed = int(Time.get_unix_time_from_system())
	rng.seed = run_seed

	level = LevelData.new()
	level.endless = mode == GameMode.Kind.ENDLESS
	level.start_lines = city.start_lines
	level.start_trains = city.start_trains
	level.start_bridges = city.start_bridges
	if mode == GameMode.Kind.MANAGER:
		# 管理模式：40 站、7 线、5 隧道的固定沙盘
		level.manager_mode = true
		level.no_station_spawn = true
		level.start_lines = 7
		level.start_trains = 7
		level.start_bridges = 5
		level.max_trains = 7
		level.station_margin = 150.0
	level.rivers.clear()
	for river in city.rivers:
		level.rivers.append(river)
	network = MetroNetwork.new(level)
	speed = 1.0
	paused = false
	pending_mode = -1


func is_endless() -> bool:
	return mode == GameMode.Kind.ENDLESS


func is_daily() -> bool:
	return mode == GameMode.Kind.DAILY
