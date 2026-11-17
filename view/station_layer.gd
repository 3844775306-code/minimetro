class_name StationLayer
extends Node2D
## 站点视图容器：监听 station_added 创建视图，并提供悬停切换。

var network: MetroNetwork = null
var _views := {}


func setup(net: MetroNetwork) -> void:
	network = net
	network.station_added.connect(_on_station_added)
	for st in network.stations:
		_ensure_view(st)


func _on_station_added(st: Station) -> void:
	_ensure_view(st)


func _ensure_view(st: Station) -> void:
	if _views.has(st.id):
		return
	var view := StationView.new()
	view.name = "Station%d" % st.id
	add_child(view)
	view.setup(st, network.level.overload_grace if network.level != null else 30.0)
	_views[st.id] = view


## 只让传入站点处于悬停态；传 null 清空所有悬停。
func set_hover(st: Station) -> void:
	var ids: Array = _views.keys()
	for i in ids.size():
		var view: StationView = _views[ids[i]]
		view.set_hovered(view.station == st)
