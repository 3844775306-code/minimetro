class_name TrainView
extends Node2D
## 列车表现：纸色描边的圆角胶囊车身 + 车内乘客小图标。
## 纸色描边让列车从同色线路里"抠"出来，始终可辨认。

const BODY := Vector2(46.0, 22.0)
const OUTLINE := 3.0
const PAPER := Color("#F3EFE6")
const INK := Color("#2B2B2B")
const MAX_RIDER_ICONS := 6
const SEAT_RADIUS := 3.6

var _line_color := Color.WHITE
var _drawn_color := Color.TRANSPARENT
var _riders: Array[Passenger] = []
var _rider_signature := -1


func update_from(train: Train, line: MetroLine) -> void:
	var xf := line.geometry.sample(train.dist)
	position = xf.origin
	rotation = xf.x.angle()
	_riders = train.riders
	var signature := _make_rider_signature(train)
	if line.color != _drawn_color or signature != _rider_signature:
		_drawn_color = line.color
		_rider_signature = signature
		queue_redraw()


func _make_rider_signature(train: Train) -> int:
	var count := mini(train.riders.size(), MAX_RIDER_ICONS)
	var signature := count
	for i in count:
		signature = signature * 7 + train.riders[i].target_shape
	return signature


func _draw() -> void:
	_capsule(Vector2.ZERO, BODY + Vector2(OUTLINE * 2.0, OUTLINE * 2.0), PAPER)
	_capsule(Vector2.ZERO, BODY, _drawn_color)
	# 车顶浅色带：提示车头朝向
	draw_line(Vector2(-11.0, -4.5), Vector2(9.0, -4.5), Color(1.0, 1.0, 1.0, 0.30), 3.0, true)
	_draw_riders()


## 车内乘客：最多画 6 个（两排三列），用小图标表示目的地形状。
func _draw_riders() -> void:
	var count := mini(_riders.size(), MAX_RIDER_ICONS)
	for i in count:
		_draw_rider_icon(_seat_position(i, count), _riders[i].target_shape)


## 座位布局：1~3 人排一行居中；4~6 人排两行三列。
func _seat_position(index: int, count: int) -> Vector2:
	if count <= 3:
		var x := (float(index) - (float(count) - 1.0) * 0.5) * 12.0
		return Vector2(x, 0.0)
	var row := index / 3
	var col := index % 3
	return Vector2((float(col) - 1.0) * 12.0, -5.5 if row == 0 else 5.5)


func _draw_rider_icon(pos: Vector2, shape_kind: int) -> void:
	if shape_kind == Shape.Kind.CIRCLE:
		draw_circle(pos, SEAT_RADIUS, PAPER, true, -1.0, true)
		draw_arc(pos, SEAT_RADIUS, 0.0, TAU, 12, INK, 1.0, true)
		return
	var poly := Shape.polygon(shape_kind, SEAT_RADIUS * 1.35)
	if poly.is_empty():
		draw_circle(pos, SEAT_RADIUS, PAPER, true, -1.0, true)
		return
	var shifted := DrawUtil.offset(poly, pos)
	draw_colored_polygon(shifted, PAPER)
	draw_polyline(DrawUtil.closed(shifted), INK, 1.0, true)


func _capsule(center: Vector2, size: Vector2, color: Color) -> void:
	var half := size * 0.5
	var radius := half.y
	var a := center - Vector2(half.x - radius, 0.0)
	var b := center + Vector2(half.x - radius, 0.0)
	draw_line(a, b, color, size.y, true)
	draw_circle(a, radius, color, true, -1.0, true)
	draw_circle(b, radius, color, true, -1.0, true)
