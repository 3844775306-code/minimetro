class_name StationView
extends Node2D
## 单个站点的表现：白色形状 + 深色描边 + 悬停环 + 出现弹出 + 超载计时环。
## 超载时描边变红、外圈出现红色计时环——玩家一眼能看出"这站要炸了"。

const FILL := Color("#FFFFFF")
const STROKE := Color("#2B2B2B")
const SHADOW := Color(0.10, 0.11, 0.13, 0.10)
const HOVER_RING := Color(0.16, 0.17, 0.19, 0.42)
const OVERLOAD_RING := Color("#D64545")
const OVERLOAD_TINT := Color(0.84, 0.27, 0.27, 0.10)

var station: Station = null
var hovered: bool = false
## 超载宽限时长（来自 LevelData），默认与设计值一致。
var overload_grace: float = 30.0

var _last_waiting := -1


func setup(st: Station, grace: float = 30.0) -> void:
	station = st
	overload_grace = grace
	position = st.pos
	scale = Vector2(0.25, 0.25)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func set_hovered(value: bool) -> void:
	if hovered == value:
		return
	hovered = value
	queue_redraw()


func _process(_delta: float) -> void:
	if station == null:
		return
	if station.overload_timer > 0.0 or station.waiting.size() != _last_waiting:
		_last_waiting = station.waiting.size()
		queue_redraw()


func _draw() -> void:
	if station == null:
		return
	# 换乘站（容量 12）画得更大，和普通站一眼区分
	var r := Shape.STATION_RADIUS * (1.18 if station.capacity > 6 else 1.0)
	var overloading := station.overload_timer > 0.0
	var progress: float = 0.0
	if overloading:
		progress = clampf(station.overload_timer / maxf(overload_grace, 0.001), 0.0, 1.0)
		draw_circle(Vector2.ZERO, r + 15.0, Color(OVERLOAD_TINT, 0.10 + 0.14 * progress), true, -1.0, true)

	var shadow_offset := Vector2(2.5, 3.5)
	var stroke := OVERLOAD_RING if overloading else STROKE
	if station.shape == Shape.Kind.CIRCLE:
		draw_circle(shadow_offset, r, SHADOW, true, -1.0, true)
		draw_circle(Vector2.ZERO, r, FILL, true, -1.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, stroke, 3.0, true)
	else:
		var pts := Shape.polygon(station.shape, r)
		draw_colored_polygon(DrawUtil.offset(pts, shadow_offset), SHADOW)
		draw_colored_polygon(pts, FILL)
		draw_polyline(DrawUtil.closed(pts), stroke, 3.0, true)
	if hovered:
		draw_arc(Vector2.ZERO, r + 13.0, 0.0, TAU, 48, HOVER_RING, 2.5, true)
	if station.capacity > 6:
		# 换乘站再加一圈细描边，和普通站的"更大"一起构成视觉区别
		draw_arc(Vector2.ZERO, r + 7.0, 0.0, TAU, 48, Color(STROKE, 0.22), 1.5, true)
	if overloading:
		draw_arc(Vector2.ZERO, r + 11.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 64,
			OVERLOAD_RING, 5.0, true)
