class_name NearLineMarkerLayer
extends Node2D
## "靠近线路但没接上"的视觉标记：
## 对每条线、每个不在该线上的站点，若它离线路很近，就在线路上最近的投影点画一个
## 空心中继标记，并用虚线连到该站，避免玩家误以为这个站已经接上了。

const NEAR_DISTANCE := 30.0
## 标记从站台图标外缘开始，沿线路向两边各画一段白线
const SPAN_GAP := 6.0
const SPAN_LENGTH := 46.0
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
			markers.append({
				"line": line,
				"geometry": line.geometry,
				"offset": offset,
				"station": station,
				"distance": distance,
			})
	return markers


func _draw() -> void:
	for marker in _markers:
		var geometry: LineGeometry = marker["geometry"]
		var offset: float = marker["offset"]
		# 两条白线都"贴在线路上"，随线路走向拐弯（折线也画成折线）
		var inner := Shape.STATION_RADIUS + SPAN_GAP
		var spans := [
			Vector2(offset - inner - SPAN_LENGTH, offset - inner),
			Vector2(offset + inner, offset + inner + SPAN_LENGTH),
		]
		for raw_span in spans:
			var span: Vector2 = raw_span
			var from := clampf(span.x, 0.0, geometry.total_length)
			var to := clampf(span.y, 0.0, geometry.total_length)
			if to - from < 6.0:
				continue
			var points := geometry.points_between(from, to)
			if points.size() < 2:
				continue
			draw_polyline(points, WHITE_SHADOW, 4.6, true)
			draw_polyline(points, WHITE, 2.6, true)