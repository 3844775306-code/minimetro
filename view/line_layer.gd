class_name LineLayer
extends Node2D
## 线路视图容器：每条线路一个 Line2D。
## 轮询 line.version，版本变化才重建点集；线路对象被 undo 重建时按 id 自动替换。

var network: MetroNetwork = null
var _views := {}

const LINE_WIDTH := 12.0


func setup(net: MetroNetwork) -> void:
	network = net
	_sync()


func _process(_delta: float) -> void:
	if network != null:
		_sync()


func _sync() -> void:
	var live := {}
	for line in network.lines:
		live[line.id] = line
	for id in _views.keys().duplicate():
		if not live.has(id):
			var dead: Line2D = _views[id]
			dead.queue_free()
			_views.erase(id)
	for line in network.lines:
		var view: Line2D = _views.get(line.id)
		if view == null:
			view = _make_view(line)
			_views[line.id] = view
		var cached: Variant = view.get_meta("line_ref") if view.has_meta("line_ref") else null
		var cached_version: int = int(view.get_meta("geometry_version")) if view.has_meta("geometry_version") else -1
		if cached != line or cached_version != line.version:
			view.set_meta("line_ref", line)
			view.set_meta("geometry_version", line.version)
			view.default_color = line.color
			view.points = line.geometry.points


func _make_view(line: MetroLine) -> Line2D:
	var view := Line2D.new()
	view.name = "Line%d" % line.id
	view.width = LINE_WIDTH
	view.joint_mode = Line2D.LINE_JOINT_ROUND
	view.begin_cap_mode = Line2D.LINE_CAP_ROUND
	view.end_cap_mode = Line2D.LINE_CAP_ROUND
	view.round_precision = 16
	view.antialiased = true
	view.default_color = line.color
	add_child(view)
	return view
