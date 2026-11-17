class_name BridgeLayer
extends Node2D
## 桥 / 隧道标记：线路穿过河道的每一处都画一段"桥面"记号（纸色描边 + 线段色）。
## 只做表现，资源计数在 MetroNetwork.used_bridges()。

var network: MetroNetwork = null
var _version := -1
var _marks: Array[Dictionary] = []


func setup(net: MetroNetwork) -> void:
	network = net
	_version = -1


func _process(_delta: float) -> void:
	if network == null:
		return
	if network.version != _version:
		_version = network.version
		_rebuild()
		queue_redraw()


func _rebuild() -> void:
	_marks.clear()
	if network.level == null or network.level.rivers.is_empty():
		return
	for line in network.lines:
		for i in range(line.stops.size() - 1):
			var a: Vector2 = line.stops[i].pos
			var b: Vector2 = line.stops[i + 1].pos
			var path := LineGeometry.octilinear_segment(a, b, line.is_segment_flipped(i))
			for j in range(path.size() - 1):
				var seg_a: Vector2 = path[j]
				var seg_b: Vector2 = path[j + 1]
				_collect(seg_a, seg_b, line.color)


func _collect(a: Vector2, b: Vector2, color: Color) -> void:
	var dir := (b - a).normalized()
	for river in network.level.rivers:
		if river.size() < 3:
			continue
		for i in river.size():
			var c: Vector2 = river[i]
			var d: Vector2 = river[(i + 1) % river.size()]
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if hit != null:
				_marks.append({"pos": hit, "dir": dir, "color": color})


func _draw() -> void:
	for mark in _marks:
		var pos: Vector2 = mark["pos"]
		var dir: Vector2 = mark["dir"]
		var perp := Vector2(-dir.y, dir.x)
		# 纸色粗底 + 线路色细线，像一段横跨河面的桥面
		draw_line(pos - perp * 14.0, pos + perp * 14.0, Color("#F3EFE6"), 6.0, true)
		draw_line(pos - perp * 13.0, pos + perp * 13.0, mark["color"], 2.5, true)
