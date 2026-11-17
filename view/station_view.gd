class_name StationView
extends Node2D
## 单个站点的表现：白色形状 + 深色描边 + 悬停环 + 出现弹出动画。

const FILL := Color("#FFFFFF")
const STROKE := Color("#2B2B2B")
const SHADOW := Color(0.10, 0.11, 0.13, 0.10)
const HOVER_RING := Color(0.16, 0.17, 0.19, 0.42)

var station: Station = null
var hovered: bool = false


func setup(st: Station) -> void:
	station = st
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


func _draw() -> void:
	if station == null:
		return
	var r := Shape.STATION_RADIUS
	var shadow_offset := Vector2(2.5, 3.5)
	if station.shape == Shape.Kind.CIRCLE:
		draw_circle(shadow_offset, r, SHADOW, true, -1.0, true)
		draw_circle(Vector2.ZERO, r, FILL, true, -1.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, STROKE, 3.0, true)
	else:
		var pts := Shape.polygon(station.shape, r)
		draw_colored_polygon(DrawUtil.offset(pts, shadow_offset), SHADOW)
		draw_colored_polygon(pts, FILL)
		draw_polyline(DrawUtil.closed(pts), STROKE, 3.0, true)
	if hovered:
		draw_arc(Vector2.ZERO, r + 13.0, 0.0, TAU, 48, HOVER_RING, 2.5, true)
