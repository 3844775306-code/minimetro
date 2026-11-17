class_name Train
extends RefCounted
## 列车：在所属线路的弧长域上往返。
## 只存 line_id 不存 line 引用 —— 否则 MetroLine.trains 与 Train.line 会成环。

const SPEED := 170.0
const DWELL_TIME := 0.45

enum State { MOVING, DWELL }

var id: int = 0
var line_id: int = 0

## 当前弧长位置。
var dist: float = 0.0
## 行进方向：+1 表示弧长增大方向。
var dir: int = 1
var state: int = State.DWELL
var dwell_left: float = 0.0

## 当前所在站（DWELL）或目标站（MOVING）在下行线的站序。
var stop_index: int = 0
var target_index: int = 0
var target_dist: float = 0.0

var capacity: int = 6
var riders: Array[Passenger] = []

## 用于线路被编辑后重映射（几何版本号）。
var line_version: int = -1


func is_full() -> bool:
	return riders.size() >= capacity


func seat_count() -> int:
	return riders.size()
