class_name TrainLayer
extends Node2D
## 列车视图容器：按 Train 实例轮询同步，线路删除/撤销后自动回收。

var network: MetroNetwork = null
var _views := {}


func setup(net: MetroNetwork) -> void:
	network = net


func _process(_delta: float) -> void:
	if network != null:
		_sync()


func _sync() -> void:
	var alive := {}
	for line in network.lines:
		var trains: Array = line.trains
		for i in trains.size():
			var train: Train = trains[i]
			var key: int = train.get_instance_id()
			alive[key] = train
			var view: TrainView = _views.get(key)
			if view == null:
				view = TrainView.new()
				add_child(view)
				_views[key] = view
			view.update_from(train, line)

	var ids: Array = _views.keys()
	for i in ids.size():
		var key: int = int(ids[i])
		if not alive.has(key):
			var dead: TrainView = _views[key]
			_views.erase(key)
			dead.queue_free()
