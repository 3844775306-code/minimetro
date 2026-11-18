class_name Passenger
extends RefCounted
## 乘客：只记"目的地形状"，不持有站点/列车引用（避免引用环，也方便对象池）。

var target_shape: int = Shape.Kind.CIRCLE
var spawn_time: float = 0.0
## 出发站位置（用于发展模式按里程计价的票价；手工测试乘客可为 ZERO）
var origin_pos: Vector2 = Vector2.ZERO


func _init(p_target_shape: int = Shape.Kind.CIRCLE, p_spawn_time: float = 0.0,
		p_origin_pos: Vector2 = Vector2.ZERO) -> void:
	target_shape = p_target_shape
	spawn_time = p_spawn_time
	origin_pos = p_origin_pos
