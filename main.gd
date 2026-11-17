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
var bridge_layer: BridgeLayer = null
var train_layer: TrainLayer = null
var station_layer: StationLayer = null
var passenger_layer: PassengerLayer = null
var fx_layer: FxLayer = null
var editor: LineEditor = null
var hud: Hud = null

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
		hud.mode_title = _mode_label()
		hud.best_score = _best_for_mode()
		if hud.settings_menu:
			_sync_settings_values()
	if simulation != null and not Game.paused:
		simulation.advance(delta, Game.speed)


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


func _mode_label() -> String:
	var label := GameMode.title(Game.mode)
	if Game.city != null:
		label += " · " + Game.city.display_name()
	if Game.is_daily():
		label += " · " + Game.daily_date
	return label


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
	if hud != null and hud.station_pick:
		_handle_station_pick(event)
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
		var pos := get_global_mouse_position()
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
		var index := hud.card_at(get_global_mouse_position())
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
	if simulation.interchange_pending:
		hud.show_station_pick()
		if editor != null:
			editor.set_process_unhandled_input(false)
		return
	if editor != null:
		editor.set_process_unhandled_input(true)


func _handle_station_pick(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_station_pick()
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_station_pick()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos := get_global_mouse_position()
	var st := network.station_at(pos, Shape.STATION_RADIUS + 8.0)
	if st != null and st.capacity <= 6 and simulation.upgrade_station(st.id):
		Audio.play("upgrade")
		hud.hide_station_pick()
		if editor != null:
			editor.set_process_unhandled_input(true)
	else:
		hud.show_toast(Loc.t("请点击一座容量为 6 的车站", "Pick a station with capacity 6"))


func _cancel_station_pick() -> void:
	if simulation == null:
		return
	var st := simulation.cancel_interchange()
	hud.hide_station_pick()
	if editor != null:
		editor.set_process_unhandled_input(true)
	if st != null:
		hud.show_toast(Loc.t("已自动升级最拥挤的车站", "Upgraded the busiest station"))


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

	bridge_layer = BridgeLayer.new()
	bridge_layer.name = "BridgeLayer"
	bridge_layer.z_index = 110
	world.add_child(bridge_layer)

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
	bridge_layer.setup(network)
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


# ---------------------------------------------------------------------------
# 开局内容 / 演示姿态
# ---------------------------------------------------------------------------

func _start_session() -> void:
	if _pose == "week":
		level.week_seconds = 7.0
	simulation = Simulation.new(network, level, Game.rng)
	simulation.game_over.connect(_on_game_over)
	simulation.week_completed.connect(_on_week_completed)
	simulation.passengers_delivered.connect(_on_passengers_delivered)
	simulation.overload_started.connect(_on_overload_started)
	network.station_added.connect(_on_station_added)

	if _demo:
		if Game.city_id == CityMaps.default_city_id():
			DemoSetup.build(network, level, 2 if _pose == "draft" else 3)
		else:
			# 非默认城市：用固定种子生成站点 + 最近邻串线，适配任意河道
			DemoSetup.build_adaptive(network, level, hash("citydemo-" + Game.city_id))
		DemoSetup.seed_passengers(network)
		_advance_sim(480)
		_apply_pose()
	else:
		simulation.spawner.spawn_initial(network, level.start_station_count)


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
			simulation.week_pending = true
			simulation.pending_cards.clear()
			simulation.pending_cards.append(UpgradeCards.get_card("interchange"))
			simulation.choose_upgrade(0)
			hud.hide_week()
			hud.show_station_pick()
			editor.set_process_unhandled_input(false)
		"settings":
			Game.paused = true
			hud.show_settings()
			_sync_settings_values()
			editor.set_process_unhandled_input(false)
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
