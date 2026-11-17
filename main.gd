extends Node2D
## 入口：装配世界（地图 / 线路 / 列车 / 站点 / 乘客 / 手势层）与 UI，驱动固定步长模拟。
##
## 命令行参数（放在 `--` 之后）：
##   --demo            确定性布局 + 3 条线路 + 预置乘客（截图/演示用）
##   --pose=draft      摆出"正在画线"的中间姿态
##   --pose=overload   摆出"站点超载计时"的姿态
##   --seed=12345      指定随机种子
##   --smoke=600       无渲染跑 N 个 tick 后打印状态并退出
##   --shot=<path>     渲染若干帧后把截图写到指定路径并退出

const PAPER_GRAIN := preload("res://art/shaders/paper_grain.gdshader")

var network: MetroNetwork = null
var level: LevelData = null
var simulation: Simulation = null

var map_view: MapView = null
var line_layer: LineLayer = null
var train_layer: TrainLayer = null
var station_layer: StationLayer = null
var passenger_layer: PassengerLayer = null
var editor: LineEditor = null
var hud: Hud = null

var _shot_path := ""
var _demo := false
var _pose := ""
var _seed := 0
var _smoke_ticks := -1


func _ready() -> void:
	_parse_args()
	Game.start_run(_seed)
	network = Game.network
	level = Game.level
	_build_world()
	_build_ui()
	_start_session()
	if _smoke_ticks > 0:
		_run_smoke()
	elif _shot_path != "":
		_capture_and_quit()


func _process(delta: float) -> void:
	if hud != null:
		hud.paused = Game.paused
		hud.speed = Game.speed
		hud.score = 0 if simulation == null else simulation.score
	if simulation != null and not Game.paused:
		simulation.advance(delta, Game.speed)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			Game.paused = not Game.paused
		KEY_1:
			Game.speed = 1.0
		KEY_2:
			Game.speed = 2.0
		KEY_3:
			Game.speed = 3.0
		KEY_R:
			get_tree().reload_current_scene()


func _on_game_over(_station: Station) -> void:
	Game.paused = true
	if hud != null:
		hud.show_game_over(0 if simulation == null else simulation.score)


func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	map_view = MapView.new()
	map_view.name = "MapLayer"
	map_view.z_index = 0
	world.add_child(map_view)
	map_view.setup(level)

	line_layer = LineLayer.new()
	line_layer.name = "LineLayer"
	line_layer.z_index = 100
	world.add_child(line_layer)

	train_layer = TrainLayer.new()
	train_layer.name = "TrainLayer"
	train_layer.z_index = 150
	world.add_child(train_layer)

	station_layer = StationLayer.new()
	station_layer.name = "StationLayer"
	station_layer.z_index = 200
	world.add_child(station_layer)

	passenger_layer = PassengerLayer.new()
	passenger_layer.name = "PassengerLayer"
	passenger_layer.z_index = 215
	world.add_child(passenger_layer)

	var overlay := Node2D.new()
	overlay.name = "OverlayLayer"
	overlay.z_index = 300
	world.add_child(overlay)

	editor = LineEditor.new()
	editor.name = "LineEditor"
	overlay.add_child(editor)

	line_layer.setup(network)
	train_layer.setup(network)
	station_layer.setup(network)
	passenger_layer.setup(network)
	editor.setup(network, level, station_layer)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)

	hud = Hud.new()
	hud.name = "Hud"
	ui.add_child(hud)
	hud.setup(network, level)
	editor.toast_requested.connect(hud.show_toast)

	var grain_layer := CanvasLayer.new()
	grain_layer.name = "Grain"
	grain_layer.layer = 5
	add_child(grain_layer)
	var grain := ColorRect.new()
	grain.name = "GrainRect"
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = PAPER_GRAIN
	grain.material = mat
	grain_layer.add_child(grain)


func _start_session() -> void:
	simulation = Simulation.new(network, level, Game.rng)
	simulation.game_over.connect(_on_game_over)
	if _demo:
		DemoSetup.build(network, level, 2 if _pose == "draft" else 3)
		DemoSetup.seed_passengers(network)
		_advance_sim(480)
		if _pose == "draft":
			# 从一座新站起手画线，先吸到已有站再拖向空中，展示"飞线"
			var st := network.add_station(Vector2(1300, 880), Shape.Kind.TRIANGLE)
			editor.begin_gesture(st.pos)
			editor.move_gesture(Vector2(1470, 720))
			editor.move_gesture(Vector2(1080, 520))
			editor.set_process_unhandled_input(false)
		elif _pose == "overload":
			# 一座没有线路的站 + 超容等待乘客，展示红色超载计时环
			var st := network.add_station(Vector2(1450, 900), Shape.Kind.DIAMOND)
			for i in 9:
				st.waiting.append(Passenger.new(Shape.Kind.CIRCLE))
			_advance_sim(420)
		elif _pose == "gameover":
			# 缩短宽限期并制造拥堵，截"游戏结束"界面
			level.overload_grace = 3.0
			var st := network.add_station(Vector2(1450, 900), Shape.Kind.DIAMOND)
			for i in 9:
				st.waiting.append(Passenger.new(Shape.Kind.CIRCLE))
			_advance_sim(300)
	else:
		simulation.spawner.spawn_initial(network, level.start_station_count)


func _advance_sim(ticks: int) -> void:
	for i in ticks:
		simulation.tick(Simulation.STEP)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--smoke="):
			_smoke_ticks = int(arg.trim_prefix("--smoke="))
		elif arg.begins_with("--pose="):
			_pose = arg.trim_prefix("--pose=")
		elif arg == "--demo":
			_demo = true


func _print_stats() -> void:
	print("SMOKE_OK stations=%d lines=%d trains=%d delivered=%d waiting=%d seed=%d" % [
		network.stations.size(),
		network.lines.size(),
		network.train_count(),
		0 if simulation == null else simulation.delivered,
		network.total_waiting(),
		Game.run_seed,
	])


func _run_smoke() -> void:
	await get_tree().process_frame
	_advance_sim(_smoke_ticks)
	_print_stats()
	get_tree().quit(0)


func _capture_and_quit() -> void:
	# 等站点弹出动画播完再截
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	_print_stats()
	print("SCREENSHOT ", _shot_path, " err=", err)
	get_tree().quit(0 if err == OK else 1)
