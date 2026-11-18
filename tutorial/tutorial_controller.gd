class_name TutorialController
extends RefCounted
## 新手教程的轻量状态机：只读取现有网络/模拟状态，不修改游戏规则。
## 第 0 步画线、第 1 步接第三站、第 2 步拖列车、第 3 步挂车厢、第 4 步送客。

signal step_changed(index: int)
signal finished

const TOTAL_STEPS := 5

var network: MetroNetwork
var simulation: Simulation
var step := 0
var active := false
var completed := false

var station_a: Station
var station_b: Station
var station_c: Station
var seed_station: Station
var seed_target: int = Shape.Kind.CIRCLE


func setup(net: MetroNetwork, sim: Simulation, a: Station, b: Station,
		c: Station) -> void:
	network = net
	simulation = sim
	station_a = a
	station_b = b
	station_c = c
	step = 0
	active = true
	completed = false
	seed_station = null
	# 教程不允许自动配车，否则第 2 步会直接被系统完成
	simulation.auto_assign_lines = false


func update() -> void:
	if not active or completed or network == null or simulation == null:
		return
	var advance := false
	match step:
		0:
			advance = _has_line_with_stops(2)
		1:
			advance = _has_line_with_stops(3)
		2:
			advance = _has_train_on_line()
		3:
			advance = _has_carriage()
		4:
			advance = simulation.delivered >= 1
	if advance:
		_advance()


func _advance() -> void:
	step += 1
	match step:
		2:
			simulation.inventory_trains += 1
		3:
			simulation.inventory_carriages += 1
		4:
			_seed_passenger()
	if step >= TOTAL_STEPS:
		completed = true
		active = false
		finished.emit()
	else:
		step_changed.emit(step)


func _has_line_with_stops(count: int) -> bool:
	for line in network.lines:
		if line.stops.size() >= count and line.geometry.is_drawable():
			return true
	return false


func _has_train_on_line() -> bool:
	for line in network.lines:
		if not line.trains.is_empty():
			return true
	return false


func _has_carriage() -> bool:
	for line in network.lines:
		for train in line.trains:
			if train.carriages > 0:
				return true
	return false


## 第 4 步生成一名“从当前线路首站去第二站形状”的乘客，保证一定能送达。
func _seed_passenger() -> void:
	if network.lines.is_empty():
		return
	var line: MetroLine = network.lines[0]
	if line.stops.size() < 2:
		return
	seed_station = line.stops[0]
	seed_target = line.stops[1].shape
	for i in range(1, line.stops.size()):
		if line.stops[i].shape != seed_station.shape:
			seed_target = line.stops[i].shape
			break
	seed_station.waiting.append(Passenger.new(seed_target, simulation.elapsed))


func title() -> String:
	match step:
		0:
			return Loc.t("画一条线路", "Draw a line")
		1:
			return Loc.t("接入第三座车站", "Connect the third station")
		2:
			return Loc.t("把列车放上线路", "Put a train on the line")
		3:
			return Loc.t("给列车加挂车厢", "Add a carriage")
		4:
			return Loc.t("送达第一位乘客", "Deliver one passenger")
		_:
			return Loc.t("教程完成", "Tutorial complete")


func body() -> String:
	match step:
		0:
			return Loc.t("按住一座车站，拖到另一座车站后松手。",
				"Press a station, drag to another station and release.")
		1:
			return Loc.t("从线路端点继续拖到第三座车站；也可以拖线段插站。",
				"Drag from a line end to the third station, or drag a segment.")
		2:
			return Loc.t("左上角「列车」现在有 1 辆，拖到刚画好的线路上。",
				"The Train card has 1. Drag it onto your new line.")
		3:
			return Loc.t("左上角「车厢」现在有 1 节，拖到正在运行的列车上。",
				"The Carriage card has 1. Drag it onto a running train.")
		4:
			return Loc.t("车会自己上下客；把这名乘客送到目的地即可完成。",
				"The train will board and deliver; deliver this passenger.")
		_:
			return Loc.t("你已经掌握了画线、发车、挂车厢和送客。",
				"You know how to draw, run, add carriages and deliver.")


func hint() -> String:
	match step:
		0:
			return Loc.t("提示：线路至少需要两座车站", "Tip: a line needs at least 2 stations")
		1:
			return Loc.t("提示：三座车站都接上后，列车才会覆盖全图", "Tip: connect all three stations")
		2:
			return Loc.t("提示：列车会自动在站台上下客", "Tip: trains stop automatically")
		3:
			return Loc.t("提示：车厢只增加容量，不增加速度", "Tip: carriages add capacity, not speed")
		4:
			return Loc.t("正在等待第一位乘客送达…", "Waiting for the first delivery…")
		_:
			return ""


func highlights() -> Array[Vector2]:
	var result: Array[Vector2] = []
	match step:
		0:
			if station_a != null:
				result.append(station_a.pos)
			if station_b != null:
				result.append(station_b.pos)
		1:
			if station_c != null:
				result.append(station_c.pos)
		4:
			if seed_station != null:
				result.append(seed_station.pos)
	return result


func skip() -> void:
	active = false
