class_name Shape
extends RefCounted
## 站点形状：枚举 + 多边形顶点表，全部程序化绘制，不依赖贴图。

enum Kind {
	CIRCLE,
	TRIANGLE,
	SQUARE,
	DIAMOND,
	STAR,
	PLUS,
	PENTAGON,
	HEXAGON,
	OCTAGON,
	RING,
	SEMICIRCLE,
	CLOVER,
}

## 站点图标的基准半径（@1920x1080 设计分辨率）。
const STATION_RADIUS := 26.0

## 等待乘客图标的半径（M2 使用）。
const PASSENGER_RADIUS := 7.0


## 返回形状的多边形顶点（CIRCLE 返回空数组，由视图用 draw_circle 处理）。
static func polygon(kind: int, radius: float = STATION_RADIUS) -> PackedVector2Array:
	match kind:
		Kind.TRIANGLE:
			return _regular(3, radius, -PI / 2.0)
		Kind.SQUARE:
			var r: float = radius * 0.84
			return PackedVector2Array([
				Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r),
			])
		Kind.DIAMOND:
			return PackedVector2Array([
				Vector2(0.0, -radius), Vector2(radius, 0.0),
				Vector2(0.0, radius), Vector2(-radius, 0.0),
			])
		Kind.STAR:
			return _star(5, radius, radius * 0.46)
		Kind.PLUS:
			return _plus(radius)
		Kind.PENTAGON:
			return _regular(5, radius, -PI / 2.0)
		Kind.HEXAGON:
			return _regular(6, radius, -PI / 2.0)
		Kind.OCTAGON:
			return _regular(8, radius, PI / 8.0)
		Kind.RING:
			return PackedVector2Array()
		Kind.SEMICIRCLE:
			return _semicircle(radius)
		Kind.CLOVER:
			return _clover(radius)
		_:
			return PackedVector2Array()


static func shape_name(kind: int) -> String:
	match kind:
		Kind.CIRCLE: return "圆形"
		Kind.TRIANGLE: return "三角"
		Kind.SQUARE: return "方形"
		Kind.DIAMOND: return "菱形"
		Kind.STAR: return "星形"
		Kind.PLUS: return "十字"
		Kind.PENTAGON: return "五边形"
		Kind.HEXAGON: return "六边形"
		Kind.OCTAGON: return "八边形"
		Kind.RING: return "圆环"
		Kind.SEMICIRCLE: return "半圆"
		Kind.CLOVER: return "四叶草"
		_: return "未知"


## 车站形状对应的"城镇地标"语义（故事化说明，双语）。
static func landmark_name(kind: int) -> String:
	match kind:
		Kind.CIRCLE: return Loc.t("居民区", "Residential")
		Kind.SQUARE: return Loc.t("车站", "Transit hub")
		Kind.TRIANGLE: return Loc.t("商务区", "Business district")
		Kind.PLUS: return Loc.t("医院", "Hospital")
		Kind.DIAMOND: return Loc.t("度假区", "Resort")
		Kind.STAR: return Loc.t("景点", "Landmark")
		Kind.PENTAGON: return Loc.t("市政厅", "Civic hall")
		Kind.HEXAGON: return Loc.t("大学", "University")
		Kind.OCTAGON: return Loc.t("体育场", "Stadium")
		Kind.RING: return Loc.t("公园", "Park")
		Kind.SEMICIRCLE: return Loc.t("博物馆", "Museum")
		Kind.CLOVER: return Loc.t("花园", "Garden")
		_: return Loc.t("未知地标", "Unknown")


## 乘客生成用的地标角色名（用于说明/调试）。
static func landmark_role(kind: int) -> String:
	match kind:
		Kind.CIRCLE: return "residential"
		Kind.SQUARE: return "transit"
		Kind.TRIANGLE: return "business"
		Kind.PLUS: return "hospital"
		Kind.DIAMOND: return "resort"
		Kind.STAR: return "landmark"
		Kind.PENTAGON: return "civic"
		Kind.HEXAGON: return "university"
		Kind.OCTAGON: return "stadium"
		Kind.RING: return "park"
		Kind.SEMICIRCLE: return "museum"
		Kind.CLOVER: return "garden"
		_: return "unknown"


static func _semicircle(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var a := PI + PI * float(i) / float(steps)  # 上半圆
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


static func _clover(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps:
		var a := TAU * float(i) / float(steps)
		var petal := 0.62 + 0.38 * absf(cos(a * 2.0))
		pts.append(Vector2(cos(a), sin(a)) * radius * petal)
	return pts


static func _regular(sides: int, radius: float, start_angle: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a: float = start_angle + TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


static func _star(points: int, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var r: float = outer if i % 2 == 0 else inner
		var a: float = -PI / 2.0 + PI * float(i) / float(points)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


static func _plus(radius: float) -> PackedVector2Array:
	var w: float = radius * 0.42
	return PackedVector2Array([
		Vector2(-w, -radius), Vector2(w, -radius), Vector2(w, -w), Vector2(radius, -w),
		Vector2(radius, w), Vector2(w, w), Vector2(w, radius), Vector2(-w, radius),
		Vector2(-w, w), Vector2(-radius, w), Vector2(-radius, -w), Vector2(-w, -w),
	])
