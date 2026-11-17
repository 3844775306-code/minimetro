class_name NearLineMarkerLayer
extends Node2D
## "靠近线路但没接上"的视觉标记：
## 对每条线、每个不在该线上的站点，若它离线路很近，就在线路上最近的投影点画一个
## 空心中继标记，并用虚线连到该站，避免玩家误以为这个站已经接上了。

const NEAR_DISTANCE := 20.0
const LINE_HALF_LENGTH := 34.0
const LINE_OFFSET := 10.0
const STATION_CLEARANCE := 14.0
const WHITE := Color("#FFFFFF")
const WHITE_SHADOW := Color(0.28, 0.28, 0.28, 0.55)

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
			if distance < 2.0 or distance > NEAR_DISTANCE:
				continue
			var tangent := line.geometry.sample(offset).x
			var marker_point := on_line
			# 站台图标会盖住白线：把标记沿线挪到站台图标之外
			if distance < Shape.STATION_RADIUS + STATION_CLEARANCE:
				var step := Shape.STATION_RADIUS + STATION_CLEARANCE
				var forward := on_line + tangent.normalized() * step
				var backward := on_line - tangent.normalized() * step
				marker_point = forward if forward.distance_to(station.pos) > backward.distance_to(station.pos) else backward
			markers.append({
				"line": line,
				"on_line": marker_point,
				"tangent": tangent,
				"station": station,
				"distance": distance,
			})
	return markers


func _draw() -> void:
	for marker in _markers:
		var point: Vector2 = marker["on_line"]
		var tangent: Vector2 = (marker["tangent"] as Vector2).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		# 沿着线路方向、在线路两侧各画一条细白线，末端小白圆：
		# 像"这两段还没接上"的夹子标记
		for side in [-1.0, 1.0]:
			var side_value := float(side)
			var center: Vector2 = point + normal * LINE_OFFSET * side_value
			var a: Vector2 = center - tangent * LINE_HALF_LENGTH
			var b: Vector2 = center + tangent * LINE_HALF_LENGTH
			# 先画一层浅灰阴影，白线在纸色背景上也看得清
			draw_line(a, b, WHITE_SHADOW, 4.6, true)
			draw_line(a, b, WHITE, 2.6, true)