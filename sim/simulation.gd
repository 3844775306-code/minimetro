class_name Simulation
extends RefCounted
## 固定步长模拟驱动：所有游戏逻辑只在这里以 1/60s 推进，视图层只做表现。
## M2 起列车/乘客/溢出计时都挂到 tick() 里；M1 只有站点周期性生成。

const STEP := 1.0 / 60.0

var network: MetroNetwork
var level: LevelData
var spawner: StationSpawner
var elapsed: float = 0.0
var paused: bool = false

var _accum: float = 0.0
var _spawn_timer: float = 0.0


func _init(p_network: MetroNetwork, p_level: LevelData, p_rng: RandomNumberGenerator) -> void:
	network = p_network
	level = p_level
	spawner = StationSpawner.new(level, p_rng)
	_spawn_timer = level.station_spawn_interval


## 由主循环每帧调用；speed 为倍速（倍速 = 多跑 tick，而不是放大 delta）。
func advance(frame_delta: float, speed: float = 1.0) -> void:
	if paused:
		return
	_accum += minf(frame_delta, 0.25) * maxf(speed, 0.0)
	var guard := 0
	while _accum >= STEP and guard < 60:
		tick(STEP)
		_accum -= STEP
		guard += 1


func tick(dt: float) -> void:
	elapsed += dt
	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		_spawn_timer = level.station_spawn_interval
		spawner.try_spawn(network)
