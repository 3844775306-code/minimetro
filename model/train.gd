class_name Train
extends RefCounted
## 列车：在所属线路的弧长域上往返；车厢挂在单列车上（每节 +6 容量）。
## 只存 line_id 不存 line 引用 —— 否则 MetroLine.trains 与 Train.line 会成环。
##
## 运动学：带加速度/减速度的速度模型。进站前按剩余距离刹车，出站逐渐加速；
## 弯道按转角比例限速；无人上下车时保持速度直接驶过车站。

const MAX_SPEED := 210.0
const ACCEL := 150.0
const DECEL := 240.0
## 停站时间与上下车人数成正比：每人 0.5 秒。
const DWELL_PER_PASSENGER := 0.5
const BASE_CAPACITY := 6
const CARRIAGE_CAPACITY := 6

enum State { MOVING, DWELL }

var id: int = 0
var line_id: int = 0

## 当前弧长位置与速度（速度不会突变，按 ACCEL/DECEL 变化）。
var dist: float = 0.0
var speed: float = 0.0
## 行进方向：+1 表示弧长增大方向。
var dir: int = 1
var state: int = State.DWELL
var dwell_left: float = 0.0

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


func refresh_capacity() -> void:
	capacity = BASE_CAPACITY + CARRIAGE_CAPACITY * carriages


func is_full() -> bool:
	return riders.size() >= capacity


func seat_count() -> int:
	return riders.size()
