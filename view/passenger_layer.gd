class_name PassengerLayer
extends Node2D
## 站内等待乘客：围绕站点画小图标（形状 = 目的地形状）。
## 车厢内乘客不绘制——与原作一致，也保证大量乘客时渲染量恒定。

const INK := Color("#2B2B2B")
const RING_COUNT := 8
const MAX_DRAWN := 16

var network: MetroNetwork = null
var _signature := -1


func setup(net: MetroNetwork) -> void:
	network = net
	_signature = -1


func _process(_delta: float) -> void:
	if network == null:
		return
	var signature := _make_signature()
	if signature != _signature:
		_signature = signature
		queue_redraw()


func _make_signature() -> int:
	var signature := 0
	for st in network.stations:
		signature = signature * 31 + st.waiting.size()
		signature = signature * 7 + st.shape
	return signature


func _draw() -> void:
	if network == null:
		return
	for st in network.stations:
		var count := mini(st.waiting.size(), MAX_DRAWN)
		for i in count:
			var passenger: Passenger = st.waiting[i]
			_draw_icon(st.pos + _slot_offset(i), passenger.target_shape)


## 固定槽位：第一圈 8 个、半径 32（跟随缩小后的车站收紧），往外每圈 +18。
func _slot_offset(index: int) -> Vector2:
	var ring := index / RING_COUNT
	var slot := index % RING_COUNT
	var radius := 32.0 + float(ring) * 18.0
	var angle := -PI * 0.5 + TAU * float(slot) / float(RING_COUNT)
	return Vector2(cos(angle), sin(angle)) * radius


func _draw_icon(pos: Vector2, shape_kind: int) -> void:
	var radius := Shape.PASSENGER_RADIUS
	if shape_kind == Shape.Kind.CIRCLE:
		draw_circle(pos, radius, INK, true, -1.0, true)
		return
	if shape_kind == Shape.Kind.RING:
		draw_arc(pos, radius * 0.9, 0.0, TAU, 20, INK, 2.4, true)
		return
	var poly := Shape.polygon(shape_kind, radius * 1.15)
	if poly.is_empty():
		draw_circle(pos, radius, INK, true, -1.0, true)
		return
	var shifted := DrawUtil.offset(poly, pos)
	draw_colored_polygon(shifted, INK)
	draw_polyline(DrawUtil.closed(shifted), INK, 2.0, true)
