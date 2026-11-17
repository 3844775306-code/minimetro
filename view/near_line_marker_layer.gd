class_name NearLineMarkerLayer
extends Node2D
## "靠近线路但没接上"的视觉标记：
## 对每条线、每个不在该线上的站点，若它离线路很近，就在线路上最近的投影点画一个
## 空心中继标记，并用虚线连到该站，避免玩家误以为这个站已经接上了。

const NEAR_DISTANCE := 92.0
const MARKER_RADIUS := 8.0
const STATION_CLEARANCE := 16.0
const MUTED := Color("#7C7568")
const PAPER := Color("#F3EFE6")

var network: MetroNetwork = null
var _version := -1
var _markers: Array = []


func setup(p_network: MetroNetwork) -> void:
	network = p_network
	_version = -1
	_rebuild()


func _process(_delta: float) -> void:
	if network != null and network.version != _version:
		_rebuild()


func _rebuild() -> void:
	_markers = collect_markers(network)
	_version = -1 if network == null else network.version
	queue_redraw()


## 收集"靠线但未接入"的标记（供绘制与测试共用）。
static func collect_markers(p_network: MetroNetwork) -> Array:
	var markers: Array = []
	if p_network == null:
		return markers
	for line in p_network.lines:
		if line.stops.size() < 2 or not line.geometry.is_drawable():
			continue
		for station in p_network.stations:
			if line.has_station(station):
				continue
			var offset := line.geometry.nearest_distance(station.pos)
			var on_line := line.geometry.sample(offset).origin
			var distance := on_line.distance_to(station.pos)
			if distance < 3.0 or distance > NEAR_DISTANCE:
				continue
			var marker_point := on_line
			# 站点图标会盖住线路上的标记：把标记沿线挪到站台图标之外
			if distance < Shape.STATION_RADIUS + STATION_CLEARANCE:
				var tangent := line.geometry.sample(offset).x
				var step := Shape.STATION_RADIUS + STATION_CLEARANCE
				var forward := on_line + tangent.normalized() * step
				var backward := on_line - tangent.normalized() * step
				marker_point = forward if forward.distance_to(station.pos) > backward.distance_to(station.pos) else backward
			markers.append({
				"line": line,
				"on_line": marker_point,
				"station": station,
				"distance": distance,
			})
	return markers


func _draw() -> void:
	for marker in _markers:
		var line: MetroLine = marker["line"]
		var point: Vector2 = marker["on_line"]
		var station: Station = marker["station"]
		# 从线路上的标记虚线指向站台（停在站台图标边缘，避免盖住站名/形状）
		var direction := (station.pos - point).normalized()
		var edge := station.pos - direction * (Shape.STATION_RADIUS + 2.0)
		draw_dashed_line(point, edge, Color(MUTED, 0.7), 1.8, 5.0, true)
		# 白底 + 断续圆环 + 叉号：明确表示"这里有站，但没接上这条线"
		draw_circle(point, MARKER_RADIUS + 1.0, Color(PAPER, 0.96), true, -1.0, true)
		var arc_color := Color(line.color, 0.92)
		for i in 8:
			var start := TAU * float(i) / 8.0
			draw_arc(point, MARKER_RADIUS, start, start + TAU / 8.0 * 0.62, 8, arc_color, 2.4, true)
		var slash_a := point + Vector2(-4.2, 4.2)
		var slash_b := point + Vector2(4.2, -4.2)
		draw_line(slash_a, slash_b, Color(MUTED, 0.95), 2.4, true)