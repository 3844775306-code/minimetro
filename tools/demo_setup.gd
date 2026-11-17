class_name DemoSetup
extends RefCounted
## 确定性演示布局：不经过玩家手势，直接生成一张"已经在运营"的网。
## 只用于截图/回归对比，不参与正式玩法。

const STATION_POINTS := [
	Vector2(300, 300), Vector2(620, 250), Vector2(950, 300), Vector2(1290, 240), Vector2(1590, 380),
	Vector2(420, 640), Vector2(760, 560), Vector2(1120, 660), Vector2(1470, 720),
	Vector2(900, 870), Vector2(560, 900),
]

const STATION_SHAPES := [
	Shape.Kind.CIRCLE, Shape.Kind.TRIANGLE, Shape.Kind.SQUARE, Shape.Kind.CIRCLE, Shape.Kind.TRIANGLE,
	Shape.Kind.SQUARE, Shape.Kind.CIRCLE, Shape.Kind.TRIANGLE, Shape.Kind.SQUARE, Shape.Kind.CIRCLE,
	Shape.Kind.TRIANGLE,
]

## 线路 = 站点索引序列
const LINES := [
	[0, 1, 2, 3, 4],
	[5, 6, 7, 8],
	[9, 10, 6, 2],
]


static func build(network: MetroNetwork, level: LevelData, line_count: int = 3) -> void:
	var stations: Array[Station] = []
	for i in STATION_POINTS.size():
		stations.append(network.add_station(STATION_POINTS[i], STATION_SHAPES[i]))
	for i in mini(line_count, LINES.size()):
		var line := network.create_line()
		for index in LINES[i]:
			line.add_stop(stations[index])
	network.touch()
	level.start_station_count = stations.size()


## 给每座站预置一个"去别的形状"的乘客，让截图里能看到等待图标与送达。
static func seed_passengers(network: MetroNetwork) -> void:
	var shapes: Array[int] = []
	for st in network.stations:
		if not shapes.has(st.shape):
			shapes.append(st.shape)
	shapes.sort()
	if shapes.size() < 2:
		return
	var fallback: int = shapes[0]
	for st in network.stations:
		var target := fallback
		for candidate in shapes:
			if candidate != st.shape:
				target = candidate
				break
		st.waiting.append(Passenger.new(target))
