extends Node2D
## 入口：装配世界与 UI、驱动模拟、处理模式/设置/存档事件、截图与冒烟 CLI。
##
## 命令行参数（放在 `--` 之后）：
##   --demo            确定性布局 + 3 条线路 + 预置乘客（截图/演示用）
##   --pose=draft|insert|riders|interchange|pick|overload|gameover|week|settings|menu
##   --mode=classic|endless|daily   直接以指定模式开局（跳过模式菜单）
##   --seed=12345      指定随机种子
##   --smoke=600       无渲染跑 N 个 tick 后打印状态并退出
##   --shot=<path>     渲染若干帧后把截图写到指定路径并退出
## 不带任何参数启动时显示模式选择菜单。

const PAPER_GRAIN := preload("res://art/shaders/paper_grain.gdshader")

var network: MetroNetwork = null
var level: LevelData = null
var simulation: Simulation = null

var map_view: MapView = null
var line_layer: LineLayer = null
var legacy_line_layer: LegacyLineLayer = null
var bridge_layer: BridgeLayer = null
var river_dash_layer: RiverDashLayer = null
var relocation_ghost_layer: RelocationGhostLayer = null
var near_line_layer: NearLineMarkerLayer = null
var train_layer: TrainLayer = null
var station_layer: StationLayer = null
var passenger_layer: PassengerLayer = null
var fx_layer: FxLayer = null
var editor: LineEditor = null
var hud: Hud = null
var camera: Camera2D = null
var _night_filter: ColorRect = null

var _shot_path := ""
var _demo := false
var _pose := ""
var _seed := 0
var _smoke_ticks := -1
var _mode_arg := -1
var _menu_mode := false
var _lang_arg := ""
var _city_arg := ""


func _ready() -> void:
	_parse_args()
	if _lang_arg != "":
		Loc.set_language(_lang_arg)
	_resolve_run()
	_build_world()
	_build_ui()
	if _menu_mode:
		hud.menu_cities = CityMaps.all()
		hud.city_index = CityMaps.index_of(Game.city_id)
		editor.set_process_unhandled_input(false)
		_refresh_mode_bests()
		hud.show_mode_menu()
	else:
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
		hud.week = 1 if simulation == null else simulation.week_index
		hud.best_score = _best_for_mode()
		hud.clock_hours = 7.0 if simulation == null else simulation.hour_of_day()
		hud.is_night = false if simulation == null else simulation.is_night()
		hud.weekday = "" if simulation == null else simulation.weekday_name()
		hud.stock_counts = {
			"train": 0 if simulation == null else simulation.inventory_trains,
			"carriage": 0 if simulation == null else simulation.inventory_carriages,
			"interchange": 0 if simulation == null else simulation.inventory_interchanges,
		}
		if simulation != null and not hud.mode_menu:
			hud.stage_label = "%s · %s" % [
				simulation.stage_name(),
				Loc.t("车站 %d", "Stations %d") % network.stations.size(),
			]
		else:
			hud.stage_label = ""
		if editor != null and simulation != null and not hud.mode_menu \
				and not hud.week_modal and not hud.settings_menu and not hud.game_over:
			if editor.hover_station != null:
				hud.hover_landmark = Shape.landmark_name(editor.hover_station.shape)
				hud.hover_screen = get_viewport().get_canvas_transform() * editor.hover_station.pos
			else:
				hud.hover_landmark = ""
		else:
			hud.hover_landmark = ""
		if _night_filter != null:
			var strength := 0.0 if simulation == null else Simulation.night_strength(simulation.hour_of_day())
			_night_filter.color = Color(0.03, 0.06, 0.16, 0.36 * strength)
		if hud.settings_menu:
			_sync_settings_values()
	if simulation != null and not Game.paused:
		simulation.advance(delta, Game.speed)
	if camera != null and simulation != null:
		var target_zoom := simulation.camera_zoom_target()
		var next_zoom := lerpf(camera.zoom.x, target_zoom, clampf(delta * 0.9, 0.0, 1.0))
		camera.zoom = Vector2(next_zoom, next_zoom)
		simulation.current_camera_zoom = next_zoom
		simulation.screen_size = get_viewport_rect().size


# ---------------------------------------------------------------------------
# 启动 / 模式
# ---------------------------------------------------------------------------

func _resolve_run() -> void:
	var direct := _demo or _shot_path != "" or _smoke_ticks > 0 \
		or (_pose != "" and _pose != "menu") or _mode_arg >= 0
	if _pose == "menu":
		direct = false
	if _city_arg != "":
		Game.pending_city = _city_arg
	elif Game.pending_city == "" and not direct and Save != null:
		Game.pending_city = String(Save.get_setting("city", CityMaps.default_city_id()))
	if Game.pending_mode >= 0:
		Game.start_run(_seed)
	elif direct:
		Game.start_run(_seed, _mode_arg)
	else:
		# 仅用于展示背景，真正开局在模式菜单选择后 reload
		Game.start_run(_seed)
		_menu_mode = true
	network = Game.network
	level = Game.level


func _best_for_mode() -> int:
	if Save == null:
		return 0
	if Game.is_daily():
		return Save.daily_best(Game.daily_date)
	return Save.best_score(Game.mode_key)


func _refresh_mode_bests() -> void:
	if hud == null or Save == null:
		return
	hud.mode_bests = {
		"classic": Save.best_score("classic"),
		"endless": Save.best_score("endless"),
		"daily": Save.daily_best(GameMode.today()),
	}


func _choose_mode(kind: int) -> void:
	if hud != null and not hud.menu_cities.is_empty():
		var city: CityMap = hud.menu_cities[hud.city_index]
		Game.pending_city = city.id
		if Save != null:
			Save.set_setting("city", city.id)
	Game.pending_mode = kind
	get_tree().reload_current_scene()


func _cycle_city(direction: int) -> void:
	if hud == null or hud.menu_cities.is_empty():
		return
	hud.city_index = (hud.city_index + direction + hud.menu_cities.size()) % hud.menu_cities.size()
	Audio.play("click")


func _restart() -> void:
	Game.pending_mode = Game.mode
	get_tree().reload_current_scene()


func _back_to_menu() -> void:
	Game.pending_mode = -1
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

## 倍速按钮走 _input（早于 _unhandled_input），这样线编辑不会把点击吞掉。
func _input(event: InputEvent) -> void:
	if hud == null:
		return
	if hud.mode_menu or hud.settings_menu or hud.week_modal or hud.game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# HUD 在 CanvasLayer 里，必须用屏幕坐标命中；世界拖拽才用世界坐标
		var pos: Vector2 = (event as InputEventMouseButton).position
		# 左上角库存图标：拖到地图上放资源
		var stock := hud.stock_icon_at(pos)
		if stock != "" and simulation != null:
			var count := 0
			match stock:
				"train": count = simulation.inventory_trains
				"carriage": count = simulation.inventory_carriages
				"interchange": count = simulation.inventory_interchanges
			if count > 0 and editor.begin_stock_drag(stock, get_global_mouse_position()):
				Audio.play("click")
				get_viewport().set_input_as_handled()
				return
		var speed := hud.speed_button_at(pos)
		if speed > 0:
			Game.speed = float(speed)
			Audio.play("click")
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.mode_menu:
		_handle_mode_menu_input(event)
		return
	if hud != null and hud.settings_menu:
		_handle_settings_input(event)
		return
	if hud != null and hud.week_modal:
		_handle_week_input(event)
		return
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
			_restart()
		KEY_M:
			_back_to_menu()


func _handle_mode_menu_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_choose_mode(GameMode.Kind.CLASSIC)
			KEY_2:
				_choose_mode(GameMode.Kind.ENDLESS)
			KEY_3:
				_choose_mode(GameMode.Kind.DAILY)
			KEY_LEFT:
				_cycle_city(-1)
			KEY_RIGHT:
				_cycle_city(1)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).position
		var index := hud.mode_card_at(pos)
		if index >= 0:
			_choose_mode(hud._mode_kind_at(index))
			return
		var direction := hud.city_arrow_at(pos)
		if direction != 0:
			_cycle_city(direction)


func _open_settings() -> void:
	if hud == null:
		return
	Game.paused = true
	hud.show_settings()
	_sync_settings_values()
	if editor != null:
		editor.set_process_unhandled_input(false)


func _close_settings() -> void:
	if hud == null:
		return
	hud.hide_settings()
	Game.paused = hud.game_over
	if editor != null:
		editor.set_process_unhandled_input(true)


func _sync_settings_values() -> void:
	if hud == null or Save == null:
		return
	hud.settings_values = {
		"master_volume": float(Save.get_setting("master_volume", 0.8)),
		"music_volume": float(Save.get_setting("music_volume", 0.7)),
		"fullscreen": bool(Save.get_setting("fullscreen", false)),
		"language": String(Save.get_setting("language", "zh")),
	}


func _handle_settings_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).position
		var vp := get_viewport_rect().size
		var row_width := 560.0
		var step := 54.0
		var start_x := (vp.x - row_width) * 0.5
		var start_y := vp.y * 0.5 - 160.0
		var index := int(floor((pos.y - start_y) / step))
		if index >= 0 and index < hud.settings_row_count():
			var row := Rect2(start_x, start_y + float(index) * step, row_width, 46.0)
			if row.has_point(pos):
				hud.settings_index = index
				if index in [0, 3, 4, 5, 6]:
					_activate_setting(index)
				else:
					_adjust_setting(index, 1)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var rows := hud.settings_row_count()
	match event.keycode:
		KEY_UP:
			hud.settings_index = (hud.settings_index - 1 + rows) % rows
		KEY_DOWN:
			hud.settings_index = (hud.settings_index + 1) % rows
		KEY_LEFT:
			_adjust_setting(hud.settings_index, -1)
		KEY_RIGHT:
			_adjust_setting(hud.settings_index, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_setting(hud.settings_index)
		KEY_ESCAPE:
			_close_settings()


func _adjust_setting(index: int, direction: int) -> void:
	if Save == null:
		return
	match index:
		1:
			var master := clampf(float(Save.get_setting("master_volume", 0.8)) + 0.1 * direction, 0.0, 1.0)
			Save.set_setting("master_volume", master)
		2:
			var music := clampf(float(Save.get_setting("music_volume", 0.7)) + 0.1 * direction, 0.0, 1.0)
			Save.set_setting("music_volume", music)
		3:
			Save.set_setting("fullscreen", not bool(Save.get_setting("fullscreen", false)))
		4:
			_toggle_language()
	_sync_settings_values()


func _activate_setting(index: int) -> void:
	match index:
		0:
			_close_settings()
		3:
			Save.set_setting("fullscreen", not bool(Save.get_setting("fullscreen", false)))
		4:
			_toggle_language()
		5:
			_close_settings()
			_restart()
		6:
			_close_settings()
			_back_to_menu()
	if index in [3, 4]:
		_sync_settings_values()


func _toggle_language() -> void:
	if Save == null:
		return
	var current := String(Save.get_setting("language", "zh"))
	Save.set_setting("language", "en" if current == "zh" else "zh")
	_refresh_mode_bests()


func _handle_week_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_choose_upgrade(0)
		elif event.keycode == KEY_2:
			_choose_upgrade(1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := hud.card_at((event as InputEventMouseButton).position)
		if index >= 0:
			_choose_upgrade(index)


func _on_week_completed(cards: Array, week_number: int) -> void:
	if hud != null:
		hud.show_week(cards, week_number)
	Audio.play("upgrade")
	if editor != null:
		editor.set_process_unhandled_input(false)


func _choose_upgrade(index: int) -> void:
	if simulation == null or hud == null or not hud.week_modal:
		return
	Audio.play("click")
	simulation.choose_upgrade(index)
	hud.hide_week()
	if editor != null:
		editor.set_process_unhandled_input(true)


## 从 HUD 库存图标拖到地图上：放列车 / 挂车厢 / 放换乘中心。
func _on_stock_drop(kind: String, pos: Vector2) -> void:
	if simulation == null:
		return
	var ok := false
	match kind:
		"train":
			ok = simulation.place_train(simulation.nearest_line(pos), pos)
			if ok:
				Audio.play("board")
			else:
				hud.show_toast(Loc.t("把列车拖到一条线路上", "Drop the train onto a line"))
		"carriage":
			ok = simulation.place_carriage(pos)
			if ok:
				Audio.play("board")
			else:
				hud.show_toast(Loc.t("把车厢拖到一列车上", "Drop the carriage onto a train"))
		"interchange":
			var st := network.station_at(pos, Shape.STATION_RADIUS + 14.0)
			ok = simulation.place_interchange(st)
			if ok:
				Audio.play("upgrade")
			else:
				hud.show_toast(Loc.t("把换乘中心拖到容量 6 的车站上",
					"Drop the interchange onto a capacity-6 station"))
	if ok:
		hud.queue_redraw()


func _handle_station_pick(event: InputEvent) -> void:
	pass


# ---------------------------------------------------------------------------
# 世界 / UI 装配
# ---------------------------------------------------------------------------

func _on_game_over(_station: Station) -> void:
	Game.paused = true
	Audio.play("gameover")
	var score := 0 if simulation == null else simulation.score
	if Save != null:
		Save.record_run(Game.mode_key, score, Game.daily_date)
	if hud != null:
		hud.show_game_over(score, maxi(score, _best_for_mode()))


func _on_passengers_delivered(station: Station, count: int) -> void:
	if fx_layer != null:
		fx_layer.spawn_delivery(station.pos, count)
	Audio.play("deliver")


func _on_overload_started(station: Station) -> void:
	if fx_layer != null:
		fx_layer.spawn_overload(station.pos)
	Audio.play("warn")


func _on_station_added(_station: Station) -> void:
	if _demo:
		return
	Audio.play("station")


func _build_world() -> void:
	# 世界相机：固定看向地图中心，随城镇发展逐渐拉远
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position = level.world_size * 0.5
	camera.zoom = Vector2(2.0, 2.0)
	camera.enabled = true
	add_child(camera)

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

	legacy_line_layer = LegacyLineLayer.new()
	legacy_line_layer.name = "LegacyLineLayer"
	legacy_line_layer.z_index = 99
	world.add_child(legacy_line_layer)

	bridge_layer = BridgeLayer.new()
	bridge_layer.name = "BridgeLayer"
	bridge_layer.z_index = 110
	world.add_child(bridge_layer)

	river_dash_layer = RiverDashLayer.new()
	river_dash_layer.name = "RiverDashLayer"
	river_dash_layer.z_index = 105
	world.add_child(river_dash_layer)

	relocation_ghost_layer = RelocationGhostLayer.new()
	relocation_ghost_layer.name = "RelocationGhostLayer"
	relocation_ghost_layer.z_index = 140
	world.add_child(relocation_ghost_layer)

	near_line_layer = NearLineMarkerLayer.new()
	near_line_layer.name = "NearLineMarkerLayer"
	near_line_layer.z_index = 145
	world.add_child(near_line_layer)

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

	fx_layer = FxLayer.new()
	fx_layer.name = "FxLayer"
	fx_layer.z_index = 350
	world.add_child(fx_layer)

	line_layer.setup(network)
	legacy_line_layer.setup(network)
	bridge_layer.setup(network)
	river_dash_layer.setup(network)
	relocation_ghost_layer.setup(network)
	near_line_layer.setup(network)
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
	editor.settings_requested.connect(_open_settings)
	editor.stock_drop_requested.connect(_on_stock_drop)

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

	# 夜色滤镜：盖在世界之上、UI 之下，白天透明度 0，入夜渐深
	var night_layer := CanvasLayer.new()
	night_layer.name = "Night"
	night_layer.layer = 6
	add_child(night_layer)
	_night_filter = ColorRect.new()
	_night_filter.name = "NightFilter"
	_night_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_night_filter.color = Color(0.03, 0.06, 0.16, 0.0)
	night_layer.add_child(_night_filter)


# ---------------------------------------------------------------------------
# 开局内容 / 演示姿态
# ---------------------------------------------------------------------------

func _start_session() -> void:
	if _pose == "week":
		level.week_seconds = 7.0
	if _pose == "night":
		level.start_hour = 19.0
	simulation = Simulation.new(network, level, Game.rng)
	simulation.screen_size = get_viewport_rect().size
	if camera != null:
		simulation.current_camera_zoom = camera.zoom.x
	if hud != null:
		hud.map_name = Game.city.display_name() if Game.city != null else ""
	if editor != null:
		editor.simulation = simulation
	simulation.game_over.connect(_on_game_over)
	simulation.week_completed.connect(_on_week_completed)
	simulation.passengers_delivered.connect(_on_passengers_delivered)
	simulation.overload_started.connect(_on_overload_started)
	network.station_added.connect(_on_station_added)

	if _demo:
		# 所有演示都用自适应布局，适配 2400×1200 大地图与新增水系
		var demo_seed := 3
		if Game.city_id != CityMaps.default_city_id():
			demo_seed = hash("citydemo-" + Game.city_id)
		DemoSetup.build_adaptive(network, level, demo_seed)
		DemoSetup.seed_passengers(network)
		_advance_sim(480)
		_apply_pose()
	else:
		# 开局固定三座基础车站：圆形（居民区）、三角形（商务区）、方形（车站）
		simulation.spawner.spawn_rect = simulation.spawn_world_rect()
		simulation.spawner.spawn_starting_trio(network)


func _apply_pose() -> void:
	if _pose in ["insert", "riders", "pick", "interchange"] \
			and (network.lines.is_empty() or network.stations.size() < 7):
		return
	match _pose:
		"draft":
			var st := network.add_station(Vector2(1300, 880), Shape.Kind.TRIANGLE)
			editor.begin_gesture(st.pos)
			editor.move_gesture(Vector2(1470, 720))
			editor.move_gesture(Vector2(1080, 520))
			editor.set_process_unhandled_input(false)
		"insert":
			var line: MetroLine = network.lines[0]
			var offs := line.geometry.stop_offsets
			var mid := Vector2.ZERO
			for i in range(offs.size() - 1):
				var candidate := line.geometry.sample((offs[i] + offs[i + 1]) * 0.5).origin
				if network.station_at(candidate, 48.0) == null:
					mid = candidate
					break
			editor.begin_gesture(mid)
			editor.move_gesture(network.stations[6].pos)
			editor.set_process_unhandled_input(false)
		"riders":
			var line: MetroLine = network.lines[0]
			if not line.trains.is_empty() and line.stops.size() >= 4:
				var train: Train = line.trains[0]
				train.riders.clear()
				for i in mini(train.capacity, 6):
					train.riders.append(Passenger.new(Shape.Kind.TRIANGLE))
				var seg := 2
				train.stop_index = seg
				train.target_index = seg + 1
				train.target_dist = line.geometry.stop_offsets[seg + 1]
				train.dist = (line.geometry.stop_offsets[seg] + line.geometry.stop_offsets[seg + 1]) * 0.5
				train.state = Train.State.MOVING
				train.line_version = line.version
			editor.set_process_unhandled_input(false)
		"interchange":
			var st: Station = network.stations[6]
			st.capacity = 12
			for i in 5:
				st.waiting.append(Passenger.new(Shape.Kind.SQUARE))
			_advance_sim(90)
		"overload":
			var st := network.add_station(Vector2(1450, 900), Shape.Kind.DIAMOND)
			for i in 9:
				st.waiting.append(Passenger.new(Shape.Kind.CIRCLE))
			_advance_sim(420)
		"gameover":
			level.overload_grace = 3.0
			var st := network.add_station(Vector2(1450, 900), Shape.Kind.DIAMOND)
			for i in 9:
				st.waiting.append(Passenger.new(Shape.Kind.CIRCLE))
			_advance_sim(300)
		"pick":
			# 演示：从左上角图标把一列车拖到线路上
			simulation.inventory_trains += 1
			simulation.inventory_interchanges += 1
			if not network.lines.is_empty():
				var line: MetroLine = network.lines[0]
				var drop := line.geometry.sample(line.geometry.total_length * 0.5).origin
				editor.begin_stock_drag("train", hud.stock_icon_center("train"))
				editor.move_gesture(drop)
				editor.set_process_unhandled_input(false)
		"settings":
			Game.paused = true
			hud.show_settings()
			_sync_settings_values()
			editor.set_process_unhandled_input(false)
		"carriages":
			simulation.apply_upgrade("carriage")
			simulation.apply_upgrade("carriage")
			_advance_sim(30)
			var placed := 0
			for line in network.lines:
				if line.trains.is_empty():
					continue
				var train: Train = line.trains[0]
				var pos := line.geometry.sample(train.dist).origin
				if simulation.place_carriage(pos):
					placed += 1
				if placed >= 2:
					break
			_advance_sim(30)
		"loop":
			if network.lines.size() >= 1 and network.stations.size() > 7:
				var line: MetroLine = network.lines[0]
				line.stops.clear()
				for index in [1, 2, 7, 6]:
					line.add_stop(network.stations[index])
				line.is_loop = true
				line.rebuild()
				network.touch()
				_advance_sim(90)
		"legacy":
			# 演示：编辑线路后，列车沿旧线跑完，旧线以浅色保留
			if not network.lines.is_empty() and network.lines[0].stops.size() > 3:
				var line: MetroLine = network.lines[0]
				if not line.trains.is_empty():
					var train: Train = line.trains[0]
					# 先把车放到旧线中段，保证旧线收尾过程可见
					train.dist = line.geometry.total_length * 0.5
					train.speed = 0.0
					var nearest := 0
					var best := INF
					for i in line.geometry.stop_offsets.size():
						var diff := absf(line.geometry.stop_offsets[i] - train.dist)
						if diff < best:
							best = diff
							nearest = i
					train.stop_index = nearest
					train.dir = 1
					train.target_index = mini(nearest + 1, line.stops.size() - 1)
					train.target_dist = line.geometry.stop_offsets[train.target_index]
					train.state = Train.State.MOVING
					train.line_version = line.version
				editor._push_undo()
				# 交换两个中途站，让旧线和新线明显不同
				var swapped: Station = line.stops[1]
				line.stops[1] = line.stops[2]
				line.stops[2] = swapped
				line.rebuild()
				network.touch()
				_advance_sim(4)
		"near-line":
			# 演示：在弯折前放一个 12px 远的站，白线会跨过折点、跟着线路转弯
			if not network.lines.is_empty():
				var line: MetroLine = network.lines[0]
				var marker_offset := line.geometry.total_length * 0.55
				for entry in line.geometry.curve_entries:
					var bend_offset := float(entry.x)
					if bend_offset < 50.0:
						continue
					var candidate_offset := bend_offset - 45.0
					var candidate := line.geometry.sample(candidate_offset).origin
					if network.station_at(candidate, 90.0) == null:
						marker_offset = candidate_offset
						break
				var xf := line.geometry.sample(marker_offset)
				var normal := xf.x.rotated(PI * 0.5)
				network.add_station(xf.origin + normal * 12.0, Shape.Kind.STAR)
				_advance_sim(2)
		"segment-dwell":
			# 演示：拖线段时在端点站上停留，红色进度环
			if not network.lines.is_empty() and network.lines[0].stops.size() >= 2:
				var line: MetroLine = network.lines[0]
				var offsets := line.geometry.stop_offsets
				var mid := line.geometry.sample((offsets[0] + offsets[1]) * 0.5).origin
				editor.begin_gesture(mid)
				editor.move_gesture(line.stops[0].pos)
				editor.advance(1.0)
				editor.set_process_unhandled_input(false)
		"relocate":
			# 演示：拖车换线时，车先靠站下客，目标位置显示浅色车
			if network.lines.size() >= 2 and not network.lines[0].trains.is_empty():
				var from_line: MetroLine = network.lines[0]
				var to_line: MetroLine = network.lines[1]
				var train: Train = from_line.trains[0]
				var target := to_line.geometry.sample(to_line.geometry.total_length * 0.5).origin
				simulation.request_train_relocation(train, from_line, to_line, target)
				_advance_sim(40)
		"metropolis":
			# 演示：城镇发展到大都市，车站变多，相机拉到最远
			var shapes := [
				Shape.Kind.CIRCLE, Shape.Kind.SQUARE, Shape.Kind.TRIANGLE,
				Shape.Kind.PLUS, Shape.Kind.STAR, Shape.Kind.DIAMOND,
				Shape.Kind.PENTAGON, Shape.Kind.HEXAGON, Shape.Kind.OCTAGON,
				Shape.Kind.RING, Shape.Kind.SEMICIRCLE, Shape.Kind.CLOVER,
			]
			for i in 30:
				var candidate := Vector2(320.0 + float(i % 6) * 360.0,
					260.0 + float(i / 6) * 200.0)
				if network.station_at(candidate, 90.0) == null \
						and not network.is_point_in_water(candidate):
					network.add_station(candidate, shapes[i % shapes.size()])
			_advance_sim(30)
			if camera != null:
				var target_zoom := simulation.camera_zoom_target()
				camera.zoom = Vector2(target_zoom, target_zoom)
		"landmark":
			# 演示：把鼠标"放"在一座车站上，显示地标名称
			if not network.stations.is_empty():
				editor.hover_station = network.stations[0]
				_advance_sim(2)
		"train-drag":
			if network.lines.size() >= 2 and not network.lines[0].trains.is_empty():
				var source_line: MetroLine = network.lines[0]
				var train: Train = source_line.trains[0]
				editor.begin_gesture(source_line.geometry.sample(train.dist).origin)
				var target_line: MetroLine = network.lines[network.lines.size() - 1]
				editor.move_gesture(
					target_line.geometry.sample(target_line.geometry.total_length * 0.5).origin
				)
				editor.set_process_unhandled_input(false)
		"boarding":
			# 演示：列车停站后逐个上下客（每 0.5s 一名），站上有呼吸提示环
			if not network.lines.is_empty() and network.lines[0].stops.size() >= 2:
				var line: MetroLine = network.lines[0]
				var station: Station = line.stops[0]
				if line.trains.is_empty():
					simulation._spawn_train_at(line, station.pos)
				var train: Train = line.trains[0]
				train.dist = line.geometry.stop_offsets[0]
				train.stop_index = 0
				train.target_index = 1
				train.speed = 0.0
				train.riders.clear()
				for i in 4:
					station.waiting.append(Passenger.new(line.stops[1].shape))
				simulation._begin_stop(train, line, station)
				train.state = Train.State.DWELL
				_advance_sim(20)
				editor.set_process_unhandled_input(false)
		"night":
			_advance_sim(60)
		_:
			pass


func _advance_sim(ticks: int) -> void:
	for i in ticks:
		if simulation != null:
			simulation.tick(Simulation.STEP)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

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
		elif arg.begins_with("--mode="):
			_mode_arg = GameMode.from_key(arg.trim_prefix("--mode="))
		elif arg.begins_with("--lang="):
			_lang_arg = arg.trim_prefix("--lang=")
		elif arg.begins_with("--city="):
			_city_arg = arg.trim_prefix("--city=")
		elif arg == "--demo":
			_demo = true


func _print_stats() -> void:
	print("SMOKE_OK mode=%s stations=%d lines=%d trains=%d delivered=%d waiting=%d seed=%d" % [
		Game.mode_key,
		network.stations.size(),
		network.lines.size(),
		network.train_count(),
		0 if simulation == null else simulation.delivered,
		network.total_waiting(),
		Game.run_seed,
	])


func _run_smoke() -> void:
	await get_tree().process_frame
	if simulation != null:
		_advance_sim(_smoke_ticks)
	_print_stats()
	get_tree().quit(0)


func _capture_and_quit() -> void:
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	_print_stats()
	print("SCREENSHOT ", _shot_path, " err=", err)
	get_tree().quit(0 if err == OK else 1)
