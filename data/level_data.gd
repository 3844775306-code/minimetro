class_name LevelData
extends Resource
## 一局的地图 / 资源 / 节奏配置。
## M1 起由 Game.start_run() 直接 new() 出默认值；M4 起支持手写河道多边形。

@export var title: String = "纸城 · 手势原型"

@export_group("地图")
@export var world_size: Vector2 = Vector2(1920, 1080)
@export var land_margin: float = 96.0
@export var land_corner_radius: float = 72.0
@export var station_margin: float = 150.0

@export_group("水域与桥梁")
## 河道多边形（闭合）。线路每穿过一条河道消耗 1 座桥/隧道。
@export var rivers: Array[PackedVector2Array] = []
## 站点离河道边缘至少这么远（避免"贴着河岸没地方画线"）。
@export var station_water_clearance: float = 36.0
@export var max_bridges: int = 6

@export_group("站点生成")
@export var start_station_count: int = 8
@export var max_stations: int = 40
@export var station_min_distance: float = 105.0
@export var station_spawn_interval: float = 13.0
## 形状权重：越大越常见。菱形 / 星形是稀有站，给乘客目的地增加多样性。
@export var station_shape_weights: Dictionary = {
	Shape.Kind.CIRCLE: 5.0,
	Shape.Kind.TRIANGLE: 4.0,
	Shape.Kind.SQUARE: 4.0,
	Shape.Kind.DIAMOND: 1.2,
	Shape.Kind.STAR: 0.8,
}

@export_group("乘客与压力")
## 乘客生成间隔：从 start 随时间线性降到 end（秒）。
@export var passenger_spawn_start: float = 2.6
@export var passenger_spawn_end: float = 0.9
## 从 start 降到 end 所需的游戏时长（秒）。
@export var passenger_ramp_seconds: float = 420.0
## 站点超载后多久判定游戏结束（秒）。
@export var overload_grace: float = 30.0

@export_group("初始资源（库存，从 HUD 图标拖到地图上使用）")
@export var start_lines: int = 3
@export var start_trains: int = 3
@export var start_carriages: int = 0
@export var start_interchanges: int = 1
@export var start_bridges: int = 2

@export_group("资源上限与周循环")
## 每周时长（游戏小时）。1 现实秒 = 1 游戏小时，所以 168 小时 = 168 秒/周。
@export var week_seconds: float = 168.0
## 一局从几点开始（游戏小时，0~24）。
@export var start_hour: float = 7.0
@export var max_lines: int = 7
@export var max_trains: int = 6
@export var max_carriages: int = 3
@export var max_interchanges: int = 3

@export_group("模式")
## 无尽模式：站点超载只显示计时环，不会判负。
@export var endless: bool = false

@export_group("线路配色")
@export var line_colors: Array[Color] = [
	Color("#D64545"),
	Color("#2D6CDF"),
	Color("#E8A33D"),
	Color("#3FA34D"),
	Color("#8E44AD"),
	Color("#E67E22"),
	Color("#17A2B8"),
	Color("#E84393"),
]


## 默认河道：竖着把地图切成左右两半，带轻微弯曲。
static func default_river(world_size: Vector2) -> PackedVector2Array:
	var top := Vector2(world_size.x * 0.62, world_size.y * 0.08)
	var bottom := Vector2(world_size.x * 0.64, world_size.y * 0.92)
	var width := world_size.x * 0.10
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 5
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var y := lerpf(top.y, bottom.y, t)
		var center_x := lerpf(top.x, bottom.x, t) + sin(t * TAU) * world_size.x * 0.03
		left.append(Vector2(center_x - width * 0.5, y))
		right.append(Vector2(center_x + width * 0.5, y))
	var poly := PackedVector2Array()
	for point in left:
		poly.append(point)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly
