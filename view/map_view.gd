class_name MapView
extends Node2D
## 地图底图：水色背景 + 纸色陆地（圆角矩形）+ 河道（并集填充 + 单条海岸线）。
## 河道填充不做逐条描边，重叠/汇流处不会出现内部接缝；只描合并后的水岸轮廓。

const WATER := Color("#CFE4EA")
const PAPER := Color("#F3EFE6")
const PAPER_EDGE := Color("#E2DAC9")
const RIVER_EDGE := Color("#B7D3DB")
const PAPER_SHADOW := Color(0.10, 0.12, 0.14, 0.07)

var level: LevelData = null
var _land := PackedVector2Array()
var _water: Array[PackedVector2Array] = []


func setup(p_level: LevelData) -> void:
	level = p_level
	var rect := Rect2(Vector2.ZERO, level.world_size).grow(-level.land_margin)
	_land = DrawUtil.rounded_rect(rect, level.land_corner_radius)
	_water = merge_rivers(level.rivers)
	queue_redraw()


func _draw() -> void:
	if level == null or _land.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, level.world_size), WATER)
	# 相机拉远时会看到世界外圈，继续铺水色，避免露出空背景
	draw_rect(Rect2(Vector2(-1400.0, -1400.0),
		level.world_size + Vector2(2800.0, 2800.0)), WATER)
	draw_colored_polygon(DrawUtil.offset(_land, Vector2(9, 11)), PAPER_SHADOW)
	draw_colored_polygon(_land, PAPER)
	draw_polyline(DrawUtil.closed(_land), PAPER_EDGE, 3.0, true)
	# 河道：先统一填充，再只描并集的外轮廓（岛/河心岛会作为反向多边形描边）
	for river in level.rivers:
		if river.size() < 3:
			continue
		draw_colored_polygon(river, WATER)
	for polygon in _water:
		if polygon.size() >= 3:
			draw_polyline(DrawUtil.closed(polygon), RIVER_EDGE, 2.5, true)


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