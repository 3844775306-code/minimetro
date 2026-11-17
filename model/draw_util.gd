class_name DrawUtil
extends RefCounted
## 绘制相关的小工具：多边形平移 / 闭合 / 圆角矩形。

static func offset(poly: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = poly[i] + delta
	return out


static func closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(poly)
	if poly.size() > 1:
		out.append(poly[0])
	return out


## 生成圆角矩形多边形（顺时针，从左上角弧开始）。
static func rounded_rect(rect: Rect2, radius: float, segments: int = 10) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y
	var pts := PackedVector2Array()
	# [圆心, 起始角, 结束角]
	var corners := [
		[Vector2(x + r, y + r), PI, 1.5 * PI],
		[Vector2(x + w - r, y + r), 1.5 * PI, TAU],
		[Vector2(x + w - r, y + h - r), 0.0, 0.5 * PI],
		[Vector2(x + r, y + h - r), 0.5 * PI, PI],
	]
	for corner in corners:
		var center: Vector2 = corner[0]
		var a0: float = corner[1]
		var a1: float = corner[2]
		for i in range(segments + 1):
			var a: float = a0 + (a1 - a0) * float(i) / float(segments)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
