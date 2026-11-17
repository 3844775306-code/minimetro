class_name Passenger
extends RefCounted
## 乘客：只记"目的地形状"，不持有站点/列车引用（避免引用环，也方便对象池）。

var target_shape: int = Shape.Kind.CIRCLE
var spawn_time: float = 0.0


func _init(p_target_shape: int = Shape.Kind.CIRCLE, p_spawn_time: float = 0.0) -> void:
	target_shape = p_target_shape
	spawn_time = p_spawn_time
