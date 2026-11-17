class_name LineGeometry
extends RefCounted
## 线路的"几何缓存"：圆角折线 + 弧长表 + 每个站点的弧长位置。
## 列车位置、飞线吸附、站点重排都基于这里的弧长，而不是站序。

const CORNER_RADIUS := 16.0
const CORNER_SEGMENTS := 8

## 采样点（已做拐角圆角化，密集点）。
var points := PackedVector2Array()
## 弧长前缀和，长度 = points.size()。
var cumulative := PackedFloat32Array([0.0])
## 每个站点对应在线路上的弧长位置。
var stop_offsets := PackedFloat32Array()
## 折线总长。
var total_length := 0.0


## 按站点顺序重建几何。
func build(stops: Array[Station]) -> void:
	var raw := PackedVector2Array()
	for st in stops:
		raw.append(st.pos)
	points = _round_corners(raw)
	_rebuild_lengths()
	stop_offsets = PackedFloat32Array()
	for st in stops:
		stop_offsets.append(nearest_distance(st.pos))


func is_drawable() -> bool:
	return points.size() >= 2 and total_length > 0.001


## 取弧长 distance 处的位置 + 朝向。
func sample(distance: float) -> Transform2D:
	if points.is_empty():
		return Transform2D(0.0, Vector2.ZERO)
	if points.size() < 2:
		return Transform2D(0.0, points[0])
	var d: float = clampf(distance, 0.0, total_length)
	var i: int = cumulative.bsearch(d) - 1
	i = clampi(i, 0, points.size() - 2)
	var seg_len: float = cumulative[i + 1] - cumulative[i]
	var t: float = 0.0 if seg_len <= 0.0001 else (d - cumulative[i]) / seg_len
	var p1: Vector2 = points[i]
	var p2: Vector2 = points[i + 1]
	var dir: Vector2 = (p2 - p1).normalized()
	return Transform2D(dir.angle(), p1.lerp(p2, t))


## 把点 p 投影到线路上，返回对应弧长。
func nearest_distance(p: Vector2) -> float:
	if points.size() < 2:
		return 0.0
	var best_dist_sq := INF
	var best_d := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var ab: Vector2 = b - a
		var len_sq: float = ab.length_squared()
		var t: float = 0.0 if len_sq <= 0.0001 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest: Vector2 = a + ab * t
		var dist_sq: float = p.distance_squared_to(closest)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_d = cumulative[i] + ab.length() * t
	return best_d


## 端点手柄位置：从端点沿线路外侧延伸 out_distance。
func handle_position(at_start: bool, out_distance: float = 30.0) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() < 2:
		return points[0]
	var xf: Transform2D = sample(0.0) if at_start else sample(total_length)
	var outward: Vector2 = -xf.x if at_start else xf.x
	return xf.origin + outward.normalized() * out_distance


func _rebuild_lengths() -> void:
	cumulative = PackedFloat32Array()
	total_length = 0.0
	if points.is_empty():
		cumulative.append(0.0)
		return
	cumulative.append(0.0)
	for i in range(1, points.size()):
		total_length += points[i - 1].distance_to(points[i])
		cumulative.append(total_length)


## 在拐点用二次贝塞尔替代尖角；站点本身仍留在弧长域里（用投影找回）。
static func _round_corners(raw: PackedVector2Array) -> PackedVector2Array:
	if raw.size() < 3:
		return raw
	var out := PackedVector2Array([raw[0]])
	for i in range(1, raw.size() - 1):
		var prev: Vector2 = raw[i - 1]
		var cur: Vector2 = raw[i]
		var next: Vector2 = raw[i + 1]
		var d1: Vector2 = cur - prev
		var d2: Vector2 = next - cur
		if d1.length() < 0.001 or d2.length() < 0.001:
			out.append(cur)
			continue
		var radius: float = minf(CORNER_RADIUS, minf(d1.length(), d2.length()) * 0.45)
		var a: Vector2 = cur - d1.normalized() * radius
		var b: Vector2 = cur + d2.normalized() * radius
		for s in range(1, CORNER_SEGMENTS + 1):
			var t: float = float(s) / float(CORNER_SEGMENTS)
			out.append(a.lerp(cur, t).lerp(cur.lerp(b, t), t))
	out.append(raw[raw.size() - 1])
	return out
