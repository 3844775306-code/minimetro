class_name MapView
extends Node2D
## 地图底图：水色背景 + 纸色陆地（圆角矩形）+ 淡淡的地图边缘。
## 后续 M4 会把陆地/河道换成 LevelData 里的多边形，绘制接口不变。

const WATER := Color("#CFE4EA")
const PAPER := Color("#F3EFE6")
const PAPER_EDGE := Color("#E2DAC9")
const RIVER_EDGE := Color("#B7D3DB")
const PAPER_SHADOW := Color(0.10, 0.12, 0.14, 0.07)

var level: LevelData = null
var _land := PackedVector2Array()


func setup(p_level: LevelData) -> void:
	level = p_level
	var rect := Rect2(Vector2.ZERO, level.world_size).grow(-level.land_margin)
	_land = DrawUtil.rounded_rect(rect, level.land_corner_radius)
	queue_redraw()


func _draw() -> void:
	if level == null or _land.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, level.world_size), WATER)
	draw_colored_polygon(DrawUtil.offset(_land, Vector2(9, 11)), PAPER_SHADOW)
	draw_colored_polygon(_land, PAPER)
	draw_polyline(DrawUtil.closed(_land), PAPER_EDGE, 3.0, true)
	# 河道画在陆地之上
	for river in level.rivers:
		if river.size() < 3:
			continue
		draw_colored_polygon(river, WATER)
		draw_polyline(DrawUtil.closed(river), RIVER_EDGE, 2.5, true)
