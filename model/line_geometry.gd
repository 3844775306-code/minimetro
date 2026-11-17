class_name LineGeometry
extends RefCounted
## 线路的"几何缓存"：八向（水平 / 垂直 / 45°）折线 + 圆角 + 弧长表 + 站点弧长位置。
##
## 八向约束统一在这里实现：任意两站之间都被拆成「45° 斜段 + 剩余水平/竖直段」，
## 默认「先 45° 后水平/竖直」；每个线段可以翻转成「先水平/竖直后 45°」，
## 翻转状态由 MetroLine.bend_flips 维护（按有序站点 id 对存 key）。
##
## 列车位置、飞线预览、站点重排都基于这里的弧长，而不是站序。

const CORNER_RADIUS := 16.0
const CORNER_SEGMENTS := 8
## 判定"已经是水平 / 垂直 / 45°"的容差（像素）。
const OCTILINEAR_EPS := 0.5

## 采样点（已做拐角圆角化，密集点）。
var points := PackedVector2Array()
## 弧长前缀和，长度 = points.size()。
var cumulative := PackedFloat32Array([0.0])
## 每个站点对应在线路上的弧长位置。
var stop_offsets := PackedFloat32Array()
## 折线总长。
var total_length := 0.0
## 弯道限速点：x = 弧长位置，y = 限速系数（0.3~1.0，乘以列车最高速就是该弯的限速）。
var curve_entries: Array[Vector2] = []
var is_loop_geometry := false


## 按站点顺序重建几何。loop=true 时把末站到首站也连起来，形成闭合环线。
## flips 的 key 形如 "3>7"（线段起点站 id > 终点站 id）。
func build(stops: Array[Station], flips: Dictionary = {}, loop: bool = false) -> void:
	var raw := octilinear_route(stops, flips, loop)
	points = _round_corners(raw)
	_rebuild_lengths()
	stop_offsets = PackedFloat32Array()
	for st in stops:
		stop_offsets.append(nearest_distance(st.pos))
	is_loop_geometry = loop
	_build_curve_entries(raw, loop)


## 从八向折线的每个拐点算"转角 → 限速系数"，供列车弯道减速用。
func _build_curve_entries(raw: PackedVector2Array, loop: bool) -> void:
	curve_entries.clear()
	if raw.size() < 3:
		return
	for i in range(1, raw.size() - 1):
		var previous := raw[i - 1]
		var current := raw[i]
		var next := raw[i + 1]
		var incoming := current - previous
		var outgoing := next - current
		if incoming.length() < 0.001 or outgoing.length() < 0.001:
			continue
		var angle := absf(incoming.angle_to(outgoing))
		if angle < 0.03:
			continue
		curve_entries.append(Vector2(nearest_distance(current), _angle_to_factor(angle)))
	# 环线在接缝处还有一个转角（首站位置）
	if loop and raw.size() >= 3:
		var last_dir := raw[raw.size() - 1] - raw[raw.size() - 2]
		var first_dir := raw[1] - raw[0]
		if last_dir.length() > 0.001 and first_dir.length() > 0.001:
			var angle := absf(last_dir.angle_to(first_dir))
			if angle >= 0.03:
				curve_entries.append(Vector2(0.0, _angle_to_factor(angle)))


## 转角（行进方向的变化量）→ 限速系数：
## 45° 是缓弯、90° 是直角弯、135° 是急弯、180° 是掉头；越接近掉头越慢。
const CURVE_FACTORS := {
	45.0: 0.9,
	90.0: 0.7,
	135.0: 0.5,
	180.0: 0.3,
}


static func _angle_to_factor(angle: float) -> float:
	var degrees := rad_to_deg(angle)
	var bucket := 45.0
	if degrees >= 157.5:
		bucket = 180.0
	elif degrees >= 112.5:
		bucket = 135.0
	elif degrees >= 67.5:
		bucket = 90.0
	return float(CURVE_FACTORS[bucket])

## 沿行进方向前方 distance 内的弯道限速点，返回 Vector2(距离, 限速系数)。
func curve_entries_ahead(offset: float, dir: int, distance: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if distance <= 0.0 or curve_entries.is_empty():
		return result
	var total := total_length
	for entry in curve_entries:
		var gap := 0.0
		if dir >= 0:
			gap = entry.x - offset
			if gap < -1.0 and is_loop_geometry:
				gap += total
		else:
			gap = offset - entry.x
			if gap < -1.0 and is_loop_geometry:
				gap += total
		if gap >= -1.0 and gap <= distance:
			result.append(Vector2(maxf(gap, 0.0), entry.y))
	return result


func is_drawable() -> bool:
	return points.size() >= 2 and total_length > 0.001


# ---------------------------------------------------------------------------
# 八向折线
# ---------------------------------------------------------------------------

## 线段 key：按"站序方向"区分，保证翻转状态不会串到反方向。
static func segment_key(a_id: int, b_id: int) -> String:
	return "%d>%d" % [a_id, b_id]


## 完整八向折线（含站点与折点，未圆角）。loop=true 时闭合回首站。
static func octilinear_route(stops: Array[Station], flips: Dictionary = {},
		loop: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	if stops.is_empty():
		return out
	out.append(stops[0].pos)
	var count := stops.size()
	for i in range(count - 1):
		_append_pair(out, stops[i], stops[i + 1], flips)
	if loop and count >= 3:
		_append_pair(out, stops[count - 1], stops[0], flips)
	return out


static func _append_pair(out: PackedVector2Array, a_station: Station, b_station: Station,
		flips: Dictionary) -> void:
	var a: Vector2 = a_station.pos
	var b: Vector2 = b_station.pos
	var flipped: bool = flips.has(segment_key(a_station.id, b_station.id))
	for bend in bends_between(a, b, flipped):
		out.append(bend)
	out.append(b)


## 两站之间需要插入的折点（0 或 1 个）。
## flipped=false：从 a 出发先走 45° 斜段，再走剩余的水平/竖直段进 b。
## flipped=true ：先水平/竖直，再走 45° 斜段进 b。
static func bends_between(a: Vector2, b: Vector2, flipped: bool = false) -> PackedVector2Array:
	var d := b - a
	var adx := absf(d.x)
	var ady := absf(d.y)
	if adx < OCTILINEAR_EPS or ady < OCTILINEAR_EPS:
		return PackedVector2Array()          # 已是水平 / 垂直
	if absf(adx - ady) < OCTILINEAR_EPS:
		return PackedVector2Array()          # 已是 45°
	var bend: Vector2
	if adx > ady:
		if flipped:
			bend = a + Vector2(signf(d.x) * (adx - ady), 0.0)
		else:
			bend = a + Vector2(signf(d.x) * ady, d.y)
	else:
		if flipped:
			bend = a + Vector2(0.0, signf(d.y) * (ady - adx))
		else:
			bend = a + Vector2(d.x, signf(d.y) * adx)
	if bend.distance_to(a) < 1.0 or bend.distance_to(b) < 1.0:
		return PackedVector2Array()
	return PackedVector2Array([bend])


## 单段八向折线（用于画线时的飞线预览）：[a, 折点?, b]
static func octilinear_segment(a: Vector2, b: Vector2, flipped: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array([a])
	for bend in bends_between(a, b, flipped):
		out.append(bend)
	out.append(b)
	return out


## 判断一段折线是否严格满足八向约束（测试/调试用）。
static func is_octilinear(points_in: PackedVector2Array) -> bool:
	for i in range(points_in.size() - 1):
		var d: Vector2 = points_in[i + 1] - points_in[i]
		if d.length() < OCTILINEAR_EPS:
			continue
		var adx := absf(d.x)
		var ady := absf(d.y)
		var axis_aligned := adx < OCTILINEAR_EPS or ady < OCTILINEAR_EPS
		var diagonal := absf(adx - ady) < OCTILINEAR_EPS
		if not (axis_aligned or diagonal):
			return false
	return true


# ---------------------------------------------------------------------------
# 重叠线路的视觉错开
# ---------------------------------------------------------------------------

## 每条线在渲染时沿法线偏移一点，避免完全重叠；返回世界像素偏移。
static func render_offset(index: int, count: int) -> float:
	if count <= 1:
		return 0.0
	return (float(index) - float(count - 1) * 0.5) * 6.0


## 与线段方向无关的“规范法线”：反向绘制同一段时法线同向，
## 这样不同线号取不同偏移时，反向线路也会分到两侧。
static func canonical_normal(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.000001:
		return Vector2.ZERO
	var n := Vector2(-direction.y, direction.x).normalized()
	if direction.x < -0.0001 or (absf(direction.x) <= 0.0001 and direction.y < 0.0):
		n = -n
	return n


## 按平均法线偏移整条折线；闭合折线保持首尾重合。
static func offset_points(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	if points.size() < 2 or absf(amount) < 0.05:
		return points
	var closed := points[0].distance_to(points[points.size() - 1]) < 0.01
	var count := points.size() - 1 if closed else points.size()
	var out := PackedVector2Array()
	for i in count:
		var previous := points[(i - 1 + count) % count] if closed \
			else points[maxi(i - 1, 0)]
		var following := points[(i + 1) % count] if closed \
			else points[mini(i + 1, points.size() - 1)]
		var n_previous := canonical_normal(points[i] - previous)
		var n_following := canonical_normal(following - points[i])
		var normal := n_previous + n_following
		if normal.length_squared() < 0.000001:
			normal = n_following if n_following.length_squared() > 0.0 else n_previous
		if normal.length_squared() < 0.000001:
			out.append(points[i])
		else:
			out.append(points[i] + normal.normalized() * amount)
	if closed:
		out.append(out[0])
	return out


# ---------------------------------------------------------------------------
# 弧长采样（列车 / 拾取 / 手柄都用这一套）
# ---------------------------------------------------------------------------

## 取弧长 distance 处的位置 + 朝向。
func sample(distance: float) -> Transform2D:
	if points.is_empty():
		return Transform2D(0.0, Vector2.ZERO)
	if points.size() < 2:
		return Transform2D(0.0, points[0])
	var d: float = distance
	if is_loop_geometry and total_length > 0.001:
		d = fposmod(distance, total_length)
	else:
		d = clampf(distance, 0.0, total_length)
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


## 取 [start_offset, end_offset] 之间的采样点（用于只画"变化过的那段旧线"）。
func points_between(start_offset: float, end_offset: float) -> PackedVector2Array:
	if points.size() < 2:
		return PackedVector2Array()
	var from := clampf(minf(start_offset, end_offset), 0.0, total_length)
	var to := clampf(maxf(start_offset, end_offset), 0.0, total_length)
	var result := PackedVector2Array()
	result.append(sample(from).origin)
	for i in points.size():
		var offset := cumulative[i]
		if offset > from and offset < to:
			result.append(points[i])
	result.append(sample(to).origin)
	return result


## 深拷贝（编辑前保存旧几何用；MetroLine.rebuild 会原地重建，不能只存引用）。
func clone() -> LineGeometry:
	var copy := LineGeometry.new()
	copy.points = points.duplicate()
	copy.cumulative = cumulative.duplicate()
	copy.stop_offsets = stop_offsets.duplicate()
	copy.total_length = total_length
	copy.curve_entries = curve_entries.duplicate()
	copy.is_loop_geometry = is_loop_geometry
	return copy


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
