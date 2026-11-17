class_name Routing
extends RefCounted
## 换乘寻路：把网络建成「站点节点 S + (站点, 线路) 节点 L」二部图，
## 以目标形状的所有站点为多源跑反向 Dijkstra。
##
## 代价设计：
##   上车 / 换乘   1.0     —— 逼玩家少折腾换乘
##   乘车一段      0.01    —— 同样可达时选站数更少的路
##   下车          0.0
##
## 网络 version 变化时重建；乘客决策只查表，不重算。

const BOARD_COST := 1.0
const RIDE_COST := 0.01
const INF := 1.0e20

var version: int = -1

var _node_count: int = 0
var _station_count: int = 0
var _station_index := {}
var _station_shapes := {}
var _station_of_node: PackedInt32Array = PackedInt32Array()
var _station_lnodes := {}
var _line_nodes := {}
var _radj: Array = []
var _routes := {}


func rebuild(network: MetroNetwork) -> void:
	version = network.version
	_routes.clear()
	_node_count = 0
	_station_count = 0
	_station_index.clear()
	_station_shapes.clear()
	_station_of_node = PackedInt32Array()
	_station_lnodes.clear()
	_line_nodes.clear()
	_radj.clear()

	# 1) 站点节点 S
	for st in network.stations:
		_station_index[st.id] = _node_count
		_station_shapes[st.id] = st.shape
		_station_of_node.append(st.id)
		var empty: Array[int] = []
		_station_lnodes[st.id] = empty
		_radj.append([])
		_node_count += 1
	_station_count = _node_count

	# 2) (站点, 线路) 节点 L
	for line in network.lines:
		if line.stops.size() < 2:
			continue
		var nodes: Array[int] = []
		for st in line.stops:
			if not _station_index.has(st.id):
				continue
			nodes.append(_node_count)
			_station_of_node.append(st.id)
			var station_nodes: Array[int] = _station_lnodes[st.id]
			station_nodes.append(_node_count)
			_station_lnodes[st.id] = station_nodes
			_radj.append([])
			_node_count += 1
		_line_nodes[line.id] = nodes

	# 3) 反向图边（从目标侧反推）
	for st in network.stations:
		var s_node: int = int(_station_index[st.id])
		var lnodes: Array[int] = _station_lnodes[st.id]
		for lnode in lnodes:
			# 正向 S->L 是"上车"，反向 L->S 权重 BOARD_COST
			var ln_edges: Array = _radj[lnode]
			ln_edges.append([s_node, BOARD_COST])
			_radj[lnode] = ln_edges
			# 正向 L->S 是"下车"，反向 S->L 权重 0
			var s_edges: Array = _radj[s_node]
			s_edges.append([lnode, 0.0])
			_radj[s_node] = s_edges
	for line in network.lines:
		if not _line_nodes.has(line.id):
			continue
		var nodes: Array[int] = _line_nodes[line.id]
		for i in range(nodes.size() - 1):
			var a: int = nodes[i]
			var b: int = nodes[i + 1]
			var ea: Array = _radj[a]
			ea.append([b, RIDE_COST])
			_radj[a] = ea
			var eb: Array = _radj[b]
			eb.append([a, RIDE_COST])
			_radj[b] = eb
		# 环线：末站与首站也要连起来
		if line.is_loop and nodes.size() >= 3:
			var first: int = nodes[0]
			var last: int = nodes[nodes.size() - 1]
			var ef: Array = _radj[first]
			ef.append([last, RIDE_COST])
			_radj[first] = ef
			var el: Array = _radj[last]
			el.append([first, RIDE_COST])
			_radj[last] = el

	# 4) 每个存在的形状跑一次多源 Dijkstra
	var shapes: Array[int] = []
	for st in network.stations:
		if not shapes.has(st.shape):
			shapes.append(st.shape)
	for shape in shapes:
		_routes[shape] = _solve(network, shape)


## 站在 station_id、想去 target_shape：返回 {"line": 线路 id, "station": 下一站 id}；
## 无路可走、或已经处于目标形状站点时返回空字典。
func next_for(station_id: int, target_shape: int) -> Dictionary:
	if int(_station_shapes.get(station_id, -1)) == target_shape:
		return {}
	if not _routes.has(target_shape):
		return {}
	if not _station_index.has(station_id):
		return {}
	var route: Dictionary = _routes[target_shape]
	var s_node: int = int(_station_index[station_id])
	var line_id: int = route["board_line"][s_node]
	var station_next: int = route["board_next"][s_node]
	if line_id < 0 or station_next < 0:
		return {}
	return {"line": line_id, "station": station_next}


func has_route(station_id: int, target_shape: int) -> bool:
	return not next_for(station_id, target_shape).is_empty()


## 坐在 line_id 的列车上、计划在 next_station_id 继续：剩余代价（含一段乘车代价）。
func stay_cost(line_id: int, station_id: int, next_station_id: int, target_shape: int) -> float:
	if not _routes.has(target_shape):
		return INF
	var route: Dictionary = _routes[target_shape]
	var dist: PackedFloat32Array = route["dist"]
	var node := _node_of(line_id, next_station_id)
	if node < 0:
		return INF
	var d: float = dist[node]
	if d >= INF * 0.5:
		return INF
	return d + RIDE_COST


## 在该站下车重新等车的最小剩余代价（含一次上车/换乘代价）。
func board_cost(station_id: int, target_shape: int) -> float:
	if not _routes.has(target_shape):
		return INF
	var route: Dictionary = _routes[target_shape]
	var dist: PackedFloat32Array = route["dist"]
	var lnodes: Array[int] = _station_lnodes.get(station_id, [])
	var best := INF
	for lnode in lnodes:
		var d: float = dist[lnode]
		if d < best:
			best = d
	if best >= INF * 0.5:
		return INF
	return best + BOARD_COST


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _solve(network: MetroNetwork, target_shape: int) -> Dictionary:
	var n := _node_count
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var done := PackedByteArray()
	done.resize(n)

	for st in network.stations:
		if st.shape == target_shape:
			dist[int(_station_index[st.id])] = 0.0

	# O(V^2) Dijkstra：节点规模 <= 400，比堆实现更简单且足够快
	for _iter in n:
		var u := -1
		var best := INF
		for k in n:
			if done[k] == 0 and dist[k] < best:
				best = dist[k]
				u = k
		if u < 0:
			break
		done[u] = 1
		var edges: Array = _radj[u]
		for edge in edges:
			var pair: Array = edge
			var v: int = int(pair[0])
			var nd: float = best + float(pair[1])
			if nd < dist[v]:
				dist[v] = nd

	var board_line := PackedInt32Array()
	board_line.resize(_station_count)
	board_line.fill(-1)
	var board_next := PackedInt32Array()
	board_next.resize(_station_count)
	board_next.fill(-1)
	var ride_next_table := PackedInt32Array()
	ride_next_table.resize(n)
	ride_next_table.fill(-1)

	for st in network.stations:
		if st.shape == target_shape:
			continue
		var s_node: int = int(_station_index[st.id])
		var best_cost := INF
		var best_line := -1
		var best_next := -1
		for line in network.lines:
			var lnode := _lnode_at(line, st.id)
			if lnode < 0:
				continue
			var cost: float = dist[lnode] + BOARD_COST
			if cost >= best_cost:
				continue
			var nxt := _best_neighbor_station(line, lnode, dist)
			if nxt < 0:
				continue
			best_cost = cost
			best_line = line.id
			best_next = nxt
		board_line[s_node] = best_line
		board_next[s_node] = best_next

	for line in network.lines:
		if not _line_nodes.has(line.id):
			continue
		var nodes: Array[int] = _line_nodes[line.id]
		for node in nodes:
			ride_next_table[node] = _best_neighbor_station(line, node, dist)

	return {
		"board_line": board_line,
		"board_next": board_next,
		"ride_next": ride_next_table,
		"dist": dist,
	}


func _lnode_at(line: MetroLine, station_id: int) -> int:
	if not _line_nodes.has(line.id):
		return -1
	var nodes: Array[int] = _line_nodes[line.id]
	for node in nodes:
		if _station_of_node[node] == station_id:
			return node
	return -1


func _node_of(line_id: int, station_id: int) -> int:
	if not _line_nodes.has(line_id):
		return -1
	var nodes: Array[int] = _line_nodes[line_id]
	for node in nodes:
		if _station_of_node[node] == station_id:
			return node
	return -1


## L 节点沿线相邻节点里 dist 更小的那个站（决定"继续坐往哪边"）。
func _best_neighbor_station(line: MetroLine, node: int, dist: PackedFloat32Array) -> int:
	if not _line_nodes.has(line.id):
		return -1
	var nodes: Array[int] = _line_nodes[line.id]
	var pos := nodes.find(node)
	if pos < 0:
		return -1
	var best := INF
	var best_station := -1
	var loop := line.is_loop and nodes.size() >= 3
	for step in [-1, 1]:
		var j: int = pos + step
		if loop:
			j = (j + nodes.size()) % nodes.size()
		elif j < 0 or j >= nodes.size():
			continue
		var d: float = dist[nodes[j]]
		if d < best:
			best = d
			best_station = _station_of_node[nodes[j]]
	if best >= INF * 0.5:
		return -1
	return best_station
