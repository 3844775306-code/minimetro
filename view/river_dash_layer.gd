class_name RiverDashLayer
extends Node2D
## 河道上的线路用虚线表现：在实线之上按"水色"间隔涂掉一段，
## 视觉上留下彩色的虚线与水面间隙（桥梁刻度仍由 BridgeLayer 绘制）。

const WATER_COLOR := Color("#CFE4EA")
const WATER_WIDTH := 16.0
const PERIOD := 22.0
const GAP := 11.0

var network: MetroNetwork = null
var _version := -1
var _dashes: Array[PackedVector2Array] = []


func setup(p_network: MetroNetwork) -> void:
	network = p_network
	_version = -1
	_rebuild()


func _process(_delta: float) -> void:
	if network != null and network.version != _version:
		_rebuild()


func _rebuild() -> void:
	_dashes.clear()
	_version = -1 if network == null else network.version
	if network == null:
		return
	for line in network.lines:
		var points := line.geometry.points
		if points.size() < 2:
			continue
		var phase := 0.0
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var length := a.distance_to(b)
			if length <= 0.001:
				continue
			var dir := (b - a) / length
			for interval in _water_intervals(a, b):
				var s0: float = phase + interval.x * length
				var s1: float = phase + interval.y * length
				var cycle := int(floor(s0 / PERIOD))
				while cycle * PERIOD < s1:
					var seg_a := maxf(cycle * PERIOD + (PERIOD - GAP), s0)
					var seg_b := minf((cycle + 1) * PERIOD, s1)
					if seg_b > seg_a:
						_dashes.append(PackedVector2Array([
							a + dir * (seg_a - phase),
							a + dir * (seg_b - phase),
						]))
					cycle += 1
			phase += length
	queue_redraw()


## 一条线段上"在水里"的区间（用 4px 步长采样近似），返回 [t0, t1] 列表。
func _water_intervals(a: Vector2, b: Vector2) -> Array:
	var length := a.distance_to(b)
	var steps := maxi(int(length / 4.0), 1)
	var intervals: Array = []
	var inside := false
	var start := 0.0
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var now := network.is_point_in_water(a.lerp(b, t))
		if now and not inside:
			inside = true
			start = t
		elif not now and inside:
			inside = false
			intervals.append(Vector2(start, t))
	if inside:
		intervals.append(Vector2(start, 1.0))
	return intervals


func _draw() -> void:
	for dash in _dashes:
		draw_line(dash[0], dash[1], WATER_COLOR, WATER_WIDTH, true)
