class_name MapView
extends Node2D
## 地图底图：水色背景 + 纸色陆地（圆角矩形）+ 河道（并集填充 + 单条海岸线）。
## 河道填充不做逐条描边，重叠/汇流处不会出现内部接缝；只描合并后的水岸轮廓。

const WATER := Color("#CFE4EA")
const PAPER := Color("#F3EFE6")
const PAPER_EDGE := Color("#E2DAC9")
const RIVER_EDGE := Color("#B7D3DB")
const PAPER_SHADOW := Color(0.10, 0.12, 0.14, 0.07)
## 地图外的"桌面"颜色：相机拉远后看到的是桌面/地图外框，不是海水
const DESK := Color("#D8D0C1")

var level: LevelData = null
var _land := PackedVector2Array()
var _water: Array[PackedVector2Array] = []
## 0 = 白天，1 = 夜晚。只改变地面/水面/桌面颜色，不盖全屏暗色滤镜。
var _night := 0.0
var _grain: Array[Vector2] = []


func set_night_strength(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if not is_equal_approx(next, _night):
		_night = next
		queue_redraw()


func setup(p_level: LevelData) -> void:
	level = p_level
	var rect := Rect2(Vector2.ZERO, level.world_size).grow(-level.land_margin)
	_land = DrawUtil.rounded_rect(rect, level.land_corner_radius)
	_water = merge_rivers(level.rivers)
	# 固定种子的纸面颗粒，增加纸张质感而不影响碰撞/布局
	_grain.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	for i in 140:
		_grain.append(Vector2(rng.randf_range(0.0, level.world_size.x),
			rng.randf_range(0.0, level.world_size.y)))
	queue_redraw()


func _draw() -> void:
	if level == null or _land.is_empty():
		return
	# 夜晚只让地面/桌面变暗；河流始终保持白天的颜色。
	var land_color := PAPER.lerp(Color("#4A4E52"), _night)
	var water_color := WATER
	var desk_color := DESK.lerp(Color("#393C3F"), _night)
	var edge_color := PAPER_EDGE.lerp(Color("#2E3134"), _night)
	var river_edge := RIVER_EDGE
	var shadow := Color(0.10, 0.12, 0.14, lerpf(0.07, 0.18, _night))
	# 相机拉远时看到世界外圈：是桌面/地图外框，不是水
	draw_rect(Rect2(Vector2(-1600.0, -1600.0),
		level.world_size + Vector2(3200.0, 3200.0)), desk_color)
	draw_rect(Rect2(Vector2.ZERO, level.world_size), water_color)
	draw_colored_polygon(DrawUtil.offset(_land, Vector2(9, 11)), shadow)
	draw_colored_polygon(_land, land_color)
	draw_polyline(DrawUtil.closed(_land), edge_color, 3.0, true)
	# 河道：先统一填充，再只描并集的外轮廓（岛/河心岛会作为反向多边形描边）
	for river in level.rivers:
		if river.size() < 3:
			continue
		draw_colored_polygon(river, water_color)
	for polygon in _water:
		if polygon.size() >= 3:
			draw_polyline(DrawUtil.closed(polygon), river_edge, 2.5, true)
	# 纸面微颗粒与内侧暖边，让大面积纸色不再平板
	var grain_color := Color(0.20, 0.18, 0.15, lerpf(0.045, 0.030, _night))
	for point in _grain:
		draw_circle(point, 0.8, grain_color, true, -1.0, true)
	draw_polyline(DrawUtil.closed(_land), Color(1.0, 1.0, 1.0, 0.34), 1.0, true)


## 把多条河道多边形合并成水面并集；重叠或汇流处不会留下内部边界。
## 返回的多边形里，反向绕行的形状代表"水中的岛"，用于描外岸线。
static func merge_rivers(rivers: Array) -> Array[PackedVector2Array]:
	var merged: Array[PackedVector2Array] = []
	for raw in rivers:
		var river: PackedVector2Array = raw
		if river.size() < 3:
			continue
		if merged.is_empty():
			merged.append(river)
			continue
		var combined: Array[PackedVector2Array] = []
		for existing in merged:
			var pieces := Geometry2D.merge_polygons(existing, river)
			for piece in pieces:
				if piece.size() >= 3:
					combined.append(piece)
		if combined.is_empty():
			combined.append(river)
		merged = combined
	return merged