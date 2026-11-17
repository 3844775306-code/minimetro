class_name RelocationGhostLayer
extends Node2D
## 拖动列车到别处时：在"被拖往的位置"显示一辆浅色车，
## 直到列车完成"靠站下客 → 移动到目标位"的收尾流程。

var network: MetroNetwork = null


func setup(p_network: MetroNetwork) -> void:
	network = p_network
	queue_redraw()


func _process(_delta: float) -> void:
	if network != null:
		queue_redraw()


func _draw() -> void:
	if network == null:
		return
	for line in network.lines:
		for train in line.trains:
			if not train.relocating:
				continue
			var target_line := network.line_by_id(train.relocate_line_id)
			var color: Color = line.color
			if target_line != null:
				color = target_line.color
			var rect := Rect2(train.relocate_pos - Vector2(34.0, 16.0), Vector2(68.0, 32.0))
			var poly := DrawUtil.rounded_rect(rect, 16.0, 8)
			draw_colored_polygon(poly, Color(color, 0.30))
			draw_polyline(DrawUtil.closed(poly), Color(color, 0.70), 2.2, true)
			# 车头方向的浅色小三角
			var nose := PackedVector2Array([
				Vector2(rect.end.x - 4.0, rect.position.y + 6.0),
				Vector2(rect.end.x + 8.0, rect.get_center().y),
				Vector2(rect.end.x - 4.0, rect.end.y - 6.0),
			])
			draw_colored_polygon(nose, Color(color, 0.45))