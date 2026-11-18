class_name TutorialController
extends RefCounted
## 新手教程状态机：基础操作 → 改线/环线 → 第二条线/过河/换乘。
## 只读取现有网络/模拟状态，不修改游戏规则；通过正常接口增发资源。

signal step_changed(index: int)
signal finished

const TOTAL_STEPS := 11

var network: MetroNetwork
var simulation: Simulation
var step := 0
var active := false
var completed := false

var station_a: Station
var station_b: Station
var station_c: Station
var station_d: Station
var station_e: Station
var seed_station: Station
var seed_target: int = Shape.Kind.CIRCLE


func setup(net: MetroNetwork, sim: Simulation, a: Station, b: Station,
		c: Station) -> void:
	network = net
	simulation = sim
	station_a = a
	station_b = b
	station_c = c
	station_d = null
	station_e = null
	step = 0
	active = true
	completed = false
	seed_station = null
	# 教程不允许自动配车，否则第 2/8 步会被系统直接完成
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
		5:
			advance = _has_line_with_stops(4)
		6:
			advance = _has_loop()
		7:
			advance = _second_line() != null
		8:
			advance = _second_line() != null and not _second_line().trains.is_empty()
		9:
			advance = simulation.delivered >= 2
		10:
			advance = not simulation.week_pending
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
			_seed_first_passenger()
		5:
			_add_station_d()
		7:
			_add_station_e()
		8:
			simulation.inventory_trains += 1
		9:
			_seed_transfer_passenger()
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


func _has_loop() -> bool:
	for line in network.lines:
		if line.is_loop and line.stops.size() >= 3:
			return true
	return false


## 第二条线必须同时经过 B 与河对岸的 E。
func _second_line() -> MetroLine:
	if station_b == null or station_e == null:
		return null
	for line in network.lines:
		if line.stops.size() >= 2 and line.stops.has(station_b) \
				and line.stops.has(station_e):
			return line
	return null


func _add_station_d() -> void:
	if station_d != null:
		return
	station_d = network.add_station(Vector2(850, 780), Shape.Kind.PLUS)
	network.touch()


## 第二条线前解锁：多一条线路额度 + 一个桥梁额度 + 河对岸车站 E。
func _add_station_e() -> void:
	if station_e == null:
		station_e = network.add_station(Vector2(1700, 500), Shape.Kind.DIAMOND)
		simulation.level.start_lines = maxi(simulation.level.start_lines, 2)
		simulation.level.start_bridges = maxi(simulation.level.start_bridges, 1)
		network.touch()


## 第 4 步：当前线路首站 → 第二站形状，保证能送达。
func _seed_first_passenger() -> void:
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


## 第 9 步：C 站 → 对岸 E 站，必须经 B 换乘。
func _seed_transfer_passenger() -> void:
	if station_c == null or station_e == null:
		return
	seed_station = station_c
	seed_target = station_e.shape
	station_c.waiting.append(Passenger.new(seed_target, simulation.elapsed))


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
		5:
			return Loc.t("插入第四座车站", "Insert the fourth station")
		6:
			return Loc.t("把线路闭合成环线", "Close the loop")
		7:
			return Loc.t("跨河建第二条线", "Build a second line across the river")
		8:
			return Loc.t("给第二条线发车", "Put a train on line 2")
		9:
			return Loc.t("完成一次换乘", "Make one transfer")
		10:
			return Loc.t("选择一张升级卡", "Choose an upgrade")
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
		5:
			return Loc.t("把新出现的 + 车站拖进线路中段，或从端点接上它。",
				"Drag the new + station into a segment, or extend a line end to it.")
		6:
			return Loc.t("把线路端点拖回起点，闭合成环线。",
				"Drag a line end back to the first station to close a loop.")
		7:
			return Loc.t("已解锁线路 2 与 1 座桥；从河对岸 E 开始画线，接到 B。",
				"Line 2 and one bridge unlocked. Start at E and draw across the river to B.")
		8:
			return Loc.t("左上角「列车」又多了 1 辆，拖到第二条线路上。",
				"Another Train is in stock. Drag it onto line 2.")
		9:
			return Loc.t("C 站乘客要去对岸 E：先坐 1 号线到 B，再换乘 2 号线。",
				"The C passenger needs E: ride line 1 to B, then transfer to line 2.")
		10:
			return Loc.t("每周会暂停并给出两张升级卡；任选一张，熟悉资源循环。",
				"The game pauses for two weekly cards; pick one to learn the upgrade loop.")
		_:
			return Loc.t("你已经掌握了画线、改线、环线、跨河、第二条线、换乘和升级。",
				"You know drawing, editing, loops, bridges, a second line, transfers and upgrades.")


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
		5:
			return Loc.t("提示：拖线段中间可以在两站之间插入新站", "Tip: drop on a segment to insert")
		6:
			return Loc.t("提示：闭合段会多出一个环形段", "Tip: the closing segment joins both ends")
		7:
			return Loc.t("提示：桥 / 隧道额度显示在左上角", "Tip: bridge quota is in the top-left panel")
		8:
			return Loc.t("提示：两条线在 B 站交汇，不需要换乘站也能换乘", "Tip: B is the transfer point")
		9:
			return Loc.t("正在等待换乘乘客送达…", "Waiting for the transfer delivery…")
		10:
			return Loc.t("提示：升级卡会暂停游戏，选完后继续", "Tip: the game pauses until you pick a card")
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
		5:
			if station_d != null:
				result.append(station_d.pos)
		6:
			if network != null and not network.lines.is_empty() \
					and not network.lines[0].stops.is_empty():
				result.append(network.lines[0].stops[0].pos)
		7:
			if station_b != null:
				result.append(station_b.pos)
			if station_e != null:
				result.append(station_e.pos)
		9:
			if station_c != null:
				result.append(station_c.pos)
			if station_e != null:
				result.append(station_e.pos)
	return result


func skip() -> void:
	active = false
