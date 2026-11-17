extends Node
## 全局运行态：一局的模型、种子、模式、倍速。
## 刻意保持很薄：模型逻辑都在 model/ 与 sim/ 里，测试可以完全绕开单例。

var network: MetroNetwork = null
var level: LevelData = null
var run_seed: int = 0
var rng := RandomNumberGenerator.new()
var speed: float = 1.0
var paused: bool = false

## 当前模式（GameMode.Kind）与每日挑战日期。
var mode: int = GameMode.Kind.CLASSIC
var mode_key: String = "classic"
var daily_date: String = ""
## 模式菜单选择后、reload 前暂存的目标模式（-1 = 直接开局）。
var pending_mode: int = -1


func start_run(p_seed: int = 0, p_mode: int = -1) -> void:
	mode = p_mode if p_mode >= 0 else pending_mode
	if mode < 0:
		mode = GameMode.Kind.CLASSIC
	mode_key = GameMode.key(mode)
	daily_date = GameMode.today() if mode == GameMode.Kind.DAILY else ""
	if p_seed != 0:
		run_seed = p_seed
	elif mode == GameMode.Kind.DAILY:
		run_seed = GameMode.daily_seed(daily_date)
	else:
		run_seed = int(Time.get_unix_time_from_system())
	rng.seed = run_seed

	level = LevelData.new()
	level.endless = mode == GameMode.Kind.ENDLESS
	# M4：默认地图带一条河道，把城市切成左右两半，跨河必须造桥/隧道
	if level.rivers.is_empty():
		level.rivers.append(LevelData.default_river(level.world_size))
	network = MetroNetwork.new(level)
	speed = 1.0
	paused = false
	pending_mode = -1


func is_endless() -> bool:
	return mode == GameMode.Kind.ENDLESS


func is_daily() -> bool:
	return mode == GameMode.Kind.DAILY
