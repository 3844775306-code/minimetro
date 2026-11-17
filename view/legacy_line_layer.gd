class_name LegacyLineLayer
extends Node2D
## 被手动编辑过的线路：只要还有列车沿"编辑前的几何"行驶，就把旧线以浅色保留，
## 直到这些列车跑完旧线（完成后再切到新线）。

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
	var drawn := {}
	for line in network.lines:
		for train in line.trains:
			if train.legacy_geometry == null:
				continue
			var geometry := train.legacy_geometry
			# 只画"和改后线路不一样"的那一段旧线
			var key := "%s:%.1f:%.1f" % [
				str(geometry.get_instance_id()), train.legacy_range_start, train.legacy_range_end,
			]
			if drawn.has(key):
				continue
			drawn[key] = true
			var points := geometry.points_between(train.legacy_range_start, train.legacy_range_end)
			if points.size() < 2:
				continue
			draw_polyline(points, Color(line.color, 0.38), 12.0, true)