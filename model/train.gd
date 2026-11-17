class_name Train
extends RefCounted
## 列车：在所属线路的弧长域上往返；车厢挂在单列车上（每节 +6 容量）。
## 只存 line_id 不存 line 引用 —— 否则 MetroLine.trains 与 Train.line 会成环。
##
## 运动学：带加速度/减速度的速度模型。进站前按剩余距离刹车，出站逐渐加速；
## 弯道按转角比例限速；无人上下车时保持速度直接驶过车站。

## 最高速度 / 加速度 / 减速度都比初版下调 40%，让行驶更慢、更易看清。
const MAX_SPEED := 126.0
const ACCEL := 90.0
const DECEL := 144.0
## 停站时间与上下车人数成正比：每人 0.5 秒；换乘枢纽（容量 12）每人 0.3 秒。
const DWELL_PER_PASSENGER := 0.5
const DWELL_PER_PASSENGER_INTERCHANGE := 0.3
const BASE_CAPACITY := 6
const CARRIAGE_CAPACITY := 6

enum State { MOVING, DWELL }

var id: int = 0
var line_id: int = 0
## 新干线：最高速度是一般列车的 2 倍
var high_speed := false

## 当前弧长位置与速度（速度不会突变，按 ACCEL/DECEL 变化）。
var dist: float = 0.0
var speed: float = 0.0
## 行进方向：+1 表示弧长增大方向。
var dir: int = 1
var state: int = State.DWELL
var dwell_left: float = 0.0
## 到站后的上下客队列：每人 0.5s（换乘枢纽 0.3s），依次执行（视觉上逐个上下）
var stop_actions: Array[Dictionary] = []
var action_timer: float = 0.0
var action_interval: float = DWELL_PER_PASSENGER

## 当前所在站（DWELL）或目标站（MOVING）在下行线的站序。
var stop_index: int = 0
var target_index: int = 0
var target_dist: float = 0.0

## 挂在这列车上的车厢数（每节 +6 容量）。
var carriages: int = 0
var capacity: int = BASE_CAPACITY
var riders: Array[Passenger] = []

## 用于线路被编辑后重映射（几何版本号）。
var line_version: int = -1

## 编辑线路后"沿原线路行驶完"的旧几何与旧站序；完成后为 null。
var legacy_geometry: LineGeometry = null
var legacy_stops: Array[Station] = []
var legacy_active := false
var legacy_finishing := false
var legacy_lap_remaining := 0
## 旧线里"和改后线路不一样"的那一段（旧几何弧长范围），只有这段要收尾/画浅色
var legacy_range_start := 0.0
var legacy_range_end := 0.0

## 拖到别处时的"回库"过程：先停靠最近站放客，再移动到目标位置
var relocating := false
var relocate_line_id := 0
var relocate_pos := Vector2.ZERO
var relocate_docked := false


func refresh_capacity() -> void:
	capacity = BASE_CAPACITY + CARRIAGE_CAPACITY * carriages


## 本列车的最高速度（新干线 = 一般车 ×2）。
func speed_limit() -> float:
	return MAX_SPEED * (2.0 if high_speed else 1.0)


func is_full() -> bool:
	return riders.size() >= capacity


func seat_count() -> int:
	return riders.size()
