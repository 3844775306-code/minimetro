class_name TrainView
extends Node2D
## 列车表现：纸色描边的圆角胶囊车身 + 车头（驾驶室/挡风玻璃）+ 车内乘客图标 + 尾部车厢。
## 车身放大 1.5 倍便于拖动；车厢永远挂在车尾（按行进方向翻转朝向）。

const BODY := Vector2(69.0, 33.0)
const OUTLINE := 4.5
const PAPER := Color("#F3EFE6")
const INK := Color("#2B2B2B")
const MAX_RIDER_ICONS := 6
const SEAT_RADIUS := 5.0
## 车厢和车体一样是圆角胶囊，只是没有车头；每节最多画 6 名乘客。
const CARRIAGE_BODY := Vector2(46.0, 27.0)
const CARRIAGE_OUTLINE := 4.0
## 第一节车厢中心偏移；之后按车厢长度 + 间隙排列
const CARRIAGE_FIRST_OFFSET := 60.5
const CARRIAGE_SPACING := 49.0

var _line_color := Color.WHITE
var _drawn_color := Color.TRANSPARENT
var _riders: Array[Passenger] = []
var _rider_signature := -1
var _carriages := 0
var _high_speed := false


func update_from(train: Train, line: MetroLine) -> void:
	var xf := line.geometry.sample(train.dist)
	position = xf.origin
	# 车头朝向行进方向：反向行驶时整体转 180°，车厢才始终在车尾
	var angle := xf.x.angle()
	if train.dir < 0:
		angle += PI
	rotation = angle
	_riders = train.riders
	_carriages = train.carriages
	_high_speed = train.high_speed
	var signature := _make_rider_signature(train)
	if line.color != _drawn_color or signature != _rider_signature:
		_drawn_color = line.color
		_rider_signature = signature
		queue_redraw()


func _make_rider_signature(train: Train) -> int:
	var count := mini(train.riders.size(), train.capacity)
	var signature := count * 131 + train.carriages * 7 + (1 if train.high_speed else 0)
	for i in count:
		signature = (signature * 31 + train.riders[i].target_shape) & 0x7fffffff
	return signature


func _draw() -> void:
	_capsule(Vector2.ZERO, BODY + Vector2(OUTLINE * 2.0, OUTLINE * 2.0), PAPER)
	_capsule(Vector2.ZERO, BODY, _drawn_color)
	_draw_cab()
	_draw_riders()
	_draw_carriages()


## 车头：纸色鼻锥 + 深色驾驶室 + 挡风玻璃 + 车灯，能明显看出行进方向。
func _draw_cab() -> void:
	var half := BODY * 0.5
	var tip := 10.0 if _high_speed else 3.0
	var nose := PackedVector2Array([
		Vector2(half.x - 7.0, -half.y + 3.0),
		Vector2(half.x + tip, 0.0),
		Vector2(half.x - 7.0, half.y - 3.0),
	])
	draw_colored_polygon(nose, PAPER)
	draw_polyline(DrawUtil.closed(nose), Color(0.10, 0.11, 0.12, 0.25), 1.2, true)
	var cab := _drawn_color.darkened(0.30)
	draw_rect(Rect2(Vector2(half.x - 23.0, -half.y + 4.0), Vector2(14.0, BODY.y - 8.0)), cab)
	draw_rect(Rect2(Vector2(half.x - 20.0, -7.5), Vector2(8.0, 15.0)),
		Color(1.0, 1.0, 1.0, 0.85))
	draw_circle(Vector2(half.x - 6.0, 0.0), 3.2, Color(1.0, 1.0, 0.86, 0.95))
	if _high_speed:
		# 新干线涂装：两侧白色速度线 + 更深色的车顶
		draw_line(Vector2(-half.x + 10.0, -half.y + 6.0),
			Vector2(half.x - 10.0, -half.y + 6.0), Color(1.0, 1.0, 1.0, 0.55), 2.0, true)
		draw_line(Vector2(-half.x + 14.0, half.y - 7.0),
			Vector2(half.x - 8.0, half.y - 7.0), Color(1.0, 1.0, 1.0, 0.45), 2.0, true)


## 车厢：和车体同款的圆角胶囊（纸色描边 + 线路色），没有车头；车内也画乘客。
func _draw_carriages() -> void:
	for i in _carriages:
		var center := Vector2(-(CARRIAGE_FIRST_OFFSET + CARRIAGE_SPACING * float(i)), 0.0)
		_capsule(center, CARRIAGE_BODY + Vector2(CARRIAGE_OUTLINE * 2.0, CARRIAGE_OUTLINE * 2.0), PAPER)
		_capsule(center, CARRIAGE_BODY, _drawn_color)
		# 车顶一道浅色高光，和车头的挡风玻璃呼应
		draw_line(center + Vector2(-CARRIAGE_BODY.x * 0.28, -CARRIAGE_BODY.y * 0.28),
			center + Vector2(CARRIAGE_BODY.x * 0.28, -CARRIAGE_BODY.y * 0.28),
			Color(1.0, 1.0, 1.0, 0.25), 2.0, true)
		var from := Train.BASE_CAPACITY + i * Train.CARRIAGE_CAPACITY
		if from >= _riders.size():
			continue
		var count := mini(_riders.size() - from, Train.CARRIAGE_CAPACITY)
		for j in count:
			_draw_rider_icon(
				center + _carriage_seat_position(j, count),
				_riders[from + j].target_shape,
				SEAT_RADIUS * 0.82
			)


func _carriage_seat_position(index: int, count: int) -> Vector2:
	if count <= 3:
		var x := (float(index) - (float(count) - 1.0) * 0.5) * 13.0
		return Vector2(x, 0.0)
	var row := index / 3
	var col := index % 3
	return Vector2((float(col) - 1.0) * 13.0, -5.5 if row == 0 else 5.5)


## 车内乘客：最多画 6 个（两排三列），用小图标表示目的地形状。
func _draw_riders() -> void:
	var count := mini(_riders.size(), MAX_RIDER_ICONS)
	for i in count:
		_draw_rider_icon(_seat_position(i, count), _riders[i].target_shape)


## 座位布局：1~3 人排一行居中；4~6 人排两行三列。
func _seat_position(index: int, count: int) -> Vector2:
	if count <= 3:
		var x := (float(index) - (float(count) - 1.0) * 0.5) * 18.0
		return Vector2(x, 0.0)
	var row := index / 3
	var col := index % 3
	return Vector2((float(col) - 1.0) * 18.0, -8.0 if row == 0 else 8.0)


func _draw_rider_icon(pos: Vector2, shape_kind: int, radius: float = SEAT_RADIUS) -> void:
	if shape_kind == Shape.Kind.CIRCLE:
		draw_circle(pos, radius, PAPER, true, -1.0, true)
		draw_arc(pos, radius, 0.0, TAU, 14, INK, 1.4, true)
		return
	if shape_kind == Shape.Kind.RING:
		draw_arc(pos, radius * 0.9, 0.0, TAU, 14, INK, 1.5, true)
		return
	var poly := Shape.polygon(shape_kind, radius * 1.45)
	if poly.is_empty():
		draw_circle(pos, radius, PAPER, true, -1.0, true)
		return
	var shifted := DrawUtil.offset(poly, pos)
	draw_colored_polygon(shifted, PAPER)
	draw_polyline(DrawUtil.closed(shifted), INK, 1.4, true)


func _capsule(center: Vector2, size: Vector2, color: Color) -> void:
	var half := size * 0.5
	var radius := half.y
	var a := center - Vector2(half.x - radius, 0.0)
	var b := center + Vector2(half.x - radius, 0.0)
	draw_line(a, b, color, size.y, true)
	draw_circle(a, radius, color, true, -1.0, true)
	draw_circle(b, radius, color, true, -1.0, true)
