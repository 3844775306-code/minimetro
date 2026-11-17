class_name Station
extends RefCounted
## 站点模型（纯数据，不依赖 Node）。
## 渲染、拾取、模拟都只读它；改结构走 MetroNetwork。

var id: int = 0
var shape: int = Shape.Kind.CIRCLE
var pos: Vector2 = Vector2.ZERO

## 容量：普通站 6，换乘站升级后 12（M4）。
var capacity: int = 6

## 等待上车的乘客（Arrival 顺序即上车优先级）。
var waiting: Array[Passenger] = []

## 派生缓存：经过本站的线路 id（由 MetroNetwork._rebuild_station_lines 维护）。
## 只存 id 不存对象：若直接持有 MetroLine，会与 MetroLine.stops 形成引用环，RefCounted 永远不释放。
var line_ids: Array[int] = []

## M2：>0 表示正在溢出倒计时。
var overload_timer: float = 0.0


func _init(p_id: int = 0, p_shape: int = Shape.Kind.CIRCLE, p_pos: Vector2 = Vector2.ZERO) -> void:
	id = p_id
	shape = p_shape
	pos = p_pos


func display_name() -> String:
	return "站 %d" % (id + 1)
