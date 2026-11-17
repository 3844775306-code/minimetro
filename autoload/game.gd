extends Node
## 全局运行态：一局的模型、种子、倍速。
## 刻意保持很薄：模型逻辑都在 model/ 与 sim/ 里，测试可以完全绕开单例。

var network: MetroNetwork = null
var level: LevelData = null
var run_seed: int = 0
var rng := RandomNumberGenerator.new()
var speed: float = 1.0
var paused: bool = false


func start_run(p_seed: int = 0) -> void:
	run_seed = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = run_seed
	level = LevelData.new()
	# M4：默认地图带一条河道，把城市切成左右两半，跨河必须造桥/隧道
	if level.rivers.is_empty():
		level.rivers.append(LevelData.default_river(level.world_size))
	network = MetroNetwork.new(level)
	speed = 1.0
	paused = false
