class_name LevelData
extends Resource
## 一局的地图 / 资源 / 节奏配置。
## M1 阶段由 Game.start_run() 直接 new() 出默认值；
## M4 起改为 res://data/levels/*.tres 资源文件，字段保持兼容。

@export var title: String = "纸城 · 手势原型"

@export_group("地图")
@export var world_size: Vector2 = Vector2(1920, 1080)
@export var land_margin: float = 96.0
@export var land_corner_radius: float = 72.0
@export var station_margin: float = 150.0

@export_group("站点生成")
@export var start_station_count: int = 8
@export var max_stations: int = 40
@export var station_min_distance: float = 105.0
@export var station_spawn_interval: float = 13.0
@export var station_shapes: Array[int] = [
	Shape.Kind.CIRCLE,
	Shape.Kind.TRIANGLE,
	Shape.Kind.SQUARE,
]

@export_group("初始资源")
@export var start_lines: int = 3
@export var start_trains: int = 3
@export var start_carriages: int = 0
@export var start_bridges: int = 2

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
