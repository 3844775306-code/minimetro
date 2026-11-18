extends Node2D
## 入口：装配世界与 UI、驱动模拟、处理模式/设置/存档事件、截图与冒烟 CLI。
##
## 命令行参数（放在 `--` 之后）：
##   --demo            确定性布局 + 3 条线路 + 预置乘客（截图/演示用）
##   --pose=draft|insert|riders|interchange|pick|overload|gameover|week|settings|menu|intro
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
var _shot_path := ""
var _shot_delay := 0.45
var _demo := false
var _pose := ""
var _seed := 0
var _smoke_ticks := -1
var _mode_arg := -1
var _menu_mode := false
var _lang_arg := ""
var _city_arg := ""
var _open_arg := ""
var _name_edit_arg := false
var _cloud_post_test := false
var _leaderboard_kind := ""
## 结束演出：先把镜头拉近到爆仓车站，再显示结算面板
var _ending_focus := false
var _ending_timer := 0.0
var _ending_overlay_shown := false
var _ending_station: Station = null
var _ending_score := 0
var _ending_best := 0
var _ending_can_restart := true
var _tutorial: TutorialController = null
var _tutorial_station_a: Station = null
var _tutorial_station_b: Station = null
var _tutorial_station_c: Station = null
var _tutorial_upgrade_offered := false


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
		if _pose == "intro":
			hud.start_startup_intro()
		elif not Game.intro_played and _shot_path == "" and _smoke_ticks < 0:
			Game.intro_played = true
			hud.start_startup_intro()
		match _open_arg:
			"daily":
				_open_daily_leaderboard()
			"hall":
				_open_map_hall()
			"rank":
				_open_map_leaderboard()
	else:
		_start_session()
	if _smoke_ticks > 0:
		_run_smoke()
	if _shot_path != "":
		_capture_and_quit()
	elif _cloud_post_test:
		_run_cloud_post_test()


func _process(delta: float) -> void:
	if hud != null:
		hud.paused = Game.paused
		hud.speed = Game.speed
		hud.score = 0 if simulation == null else simulation.score
		hud.throughput = 0.0 if simulation == null else simulation.recent_throughput_per_30s()
		hud.endless_mode = Game.is_endless()
		hud.week = 1 if simulation == null else simulation.week_index
		hud.best_score = _best_for_mode()
		hud.clock_hours = 7.0 if simulation == null else simulation.hour_of_day()
		hud.is_night = false if simulation == null else simulation.is_night()
		hud.weekday = "" if simulation == null else simulation.weekday_name()
		hud.stock_counts = {
			"train": 0 if simulation == null else simulation.inventory_trains,
			"express": 0 if simulation == null else simulation.inventory_high_speed,
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
		if map_view != null:
			var strength := 0.0 if simulation == null else Simulation.night_strength(simulation.hour_of_day())
			map_view.set_night_strength(strength)
		if hud.settings_menu:
			_sync_settings_values()
	if simulation != null and not Game.paused:
		simulation.edit_in_progress = editor != null and editor.is_busy()
		simulation.advance(delta, Game.speed)
	if _tutorial != null and _tutorial.active:
		_tutorial.update()
	if camera != null and simulation != null:
		if _ending_focus:
			_ending_timer += delta
			var focus_pos := _ending_station.pos if _ending_station != null else camera.position
			camera.position = camera.position.lerp(focus_pos, clampf(delta * 5.0, 0.0, 1.0))
			var cinematic_zoom := lerpf(camera.zoom.x, 3.1, clampf(delta * 3.2, 0.0, 1.0))
			camera.zoom = Vector2(cinematic_zoom, cinematic_zoom)
			simulation.current_camera_zoom = cinematic_zoom
			simulation.screen_size = get_viewport_rect().size
			if not _ending_overlay_shown and _ending_timer >= 0.9:
				_ending_overlay_shown = true
				if hud != null:
					hud.show_game_over(_ending_score, _ending_best, _ending_can_restart)
		else:
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
		or (_pose != "" and _pose != "menu" and _pose != "intro") or _mode_arg >= 0
	if _pose in ["menu", "intro"]:
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
	if Save == null or Game.mode == GameMode.Kind.TUTORIAL:
		return 0
	if Game.is_daily():
		return Save.daily_best(Game.daily_date)
	return Save.map_best(Game.mode_key, Game.city_id)


func _refresh_mode_bests() -> void:
	if hud == null or Save == null:
		return
	var city_id := "paper"
	if not hud.menu_cities.is_empty():
		city_id = hud.menu_cities[clampi(hud.city_index, 0, hud.menu_cities.size() - 1)].id
	hud.mode_bests = {
		"classic": Save.map_best("classic", city_id),
		"endless": Save.map_best("endless", city_id),
		"daily": Save.daily_best(GameMode.today()),
		"manager": Save.map_best("manager", city_id),
	}


func _open_map_editor() -> void:
	get_tree().change_scene_to_file("res://map_editor/map_editor.tscn")


func _open_daily_leaderboard() -> void:
	if hud == null:
		return
	_leaderboard_kind = "daily"
	hud.show_leaderboard(Loc.t("每日挑战排行榜", "Daily Challenge Leaderboard"),
		Loc.t("最近 7 天 · 每名玩家每天只有 1 次机会 · %s",
			"Last 7 days · one attempt per player per day · %s") % Cloud.remote_status(),
		Cloud.recent_daily_lines(7, 3))


func _open_map_leaderboard() -> void:
	if hud == null:
		return
	_leaderboard_kind = "rank"
	var city: CityMap = null
	if not hud.menu_cities.is_empty():
		city = hud.menu_cities[clampi(hud.city_index, 0, hud.menu_cities.size() - 1)]
	var city_id := "paper"
	var city_name := "纸城"
	if city != null:
		city_id = city.id
		city_name = city.display_name()
	var lines: Array[String] = []
	for mode in ["classic", "endless", "manager"]:
		lines.append("【%s】" % GameMode.title(GameMode.from_key(mode)))
		var entries := Cloud.best_leaderboard(mode, city_id, 3)
		if entries.is_empty():
			lines.append("  暂无成绩")
		for i in entries.size():
			var entry: Dictionary = entries[i]
			lines.append("  %d. %s   %d" % [i + 1, String(entry.get("name", "?")),
				int(entry.get("score", 0))])
		var personal := 0
		if Save != null:
			personal = Save.map_best(mode, city_id)
		lines.append("  你的最高：%d" % personal)
		lines.append("")
	hud.show_leaderboard(Loc.t("地图排行榜 · %s", "Map Leaderboard · %s") % city_name,
		Loc.t("分地图最高纪录与云端排行榜 · %s",
			"Best records and cloud board per map · %s") % Cloud.remote_status(),
		lines)


func _open_map_hall() -> void:
	if hud == null:
		return
	hud.show_map_hall(Cloud.maps(20))


func _on_cloud_updated() -> void:
	if hud == null:
		return
	if hud.leaderboard_open:
		match _leaderboard_kind:
			"daily":
				_open_daily_leaderboard()
			"rank":
				_open_map_leaderboard()
	if hud.map_hall_open:
		hud.show_map_hall(Cloud.maps(20))


func _cancel_line_by_id(line_id: int) -> void:
	if hud == null or network == null:
		return
	var line := network.line_by_id(line_id)
	if line == null:
		hud.hide_line_cancel()
		return
	if editor != null and editor.is_busy():
		editor.cancel_gesture()
	var returned := 0
	if simulation != null:
		returned = simulation.cancel_line(line)
	else:
		network.remove_line(line)
	hud.hide_line_cancel()
	hud.show_toast(Loc.t("已取消线路 · 返还 %d 列车", "Line cancelled · %d trains returned")
		% returned)
	Audio.play("click")


func _download_hall_map(index: int) -> void:
	if hud == null or index < 0 or index >= hud.map_hall_entries.size():
		return
	var entry: Dictionary = hud.map_hall_entries[index]
	var map := Cloud.download_map(String(entry.get("id", "")))
	if map.is_empty():
		hud.show_toast(Loc.t("下载失败", "Download failed"))
		return
	if CustomMapStore.save_map(map):
		CityMaps.reload()
		hud.menu_cities = CityMaps.all()
		hud.hide_map_hall()
		hud.show_toast(Loc.t("已下载地图：%s" % String(map.get("name_zh", "?")),
			"Downloaded: %s" % String(map.get("name_en", "?"))))


func _choose_mode(kind: int) -> void:
	if kind == GameMode.Kind.DAILY and Save != null \
			and Save.daily_attempt_used(GameMode.today()):
		_open_daily_leaderboard()
		return
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
	_refresh_mode_bests()
	Audio.play("click")


func _record_run_result() -> void:
	if simulation == null or Save == null or Game.mode == GameMode.Kind.TUTORIAL:
		return
	var score := simulation.score
	if Game.is_daily():
		Save.record_run("daily", score, Game.daily_date)
		if Cloud != null:
			Cloud.submit_daily(Game.daily_date, score)
		return
	if Game.is_endless():
		score = simulation.endless_best()
	Save.record_run(Game.mode_key, score, "")
	Save.record_map_run(Game.mode_key, Game.city_id, score)
	if Cloud != null:
		Cloud.submit_best(Game.mode_key, Game.city_id, score)


func _record_endless_best() -> void:
	_record_run_result()


func _restart() -> void:
	_record_run_result()
	if Game.is_daily():
		Game.pending_mode = -1
		get_tree().reload_current_scene()
		return
	Game.pending_mode = Game.mode
	get_tree().reload_current_scene()


func _back_to_menu() -> void:
	_record_run_result()
	Game.pending_mode = -1
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

## 倍速按钮走 _input（早于 _unhandled_input），这样线编辑不会把点击吞掉。
func _input(event: InputEvent) -> void:
	if hud == null:
		return
	if hud.tutorial_active:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var tutorial_pos: Vector2 = (event as InputEventMouseButton).position
			if hud.tutorial_complete:
				if hud.tutorial_start_at(tutorial_pos):
					# reload 会销毁当前 viewport，先消费输入再 reload
					get_viewport().set_input_as_handled()
					_start_after_tutorial()
				elif hud.tutorial_menu_at(tutorial_pos):
					get_viewport().set_input_as_handled()
					_finish_tutorial_to_menu()
				return
			if hud.tutorial_skip_at(tutorial_pos):
				get_viewport().set_input_as_handled()
				_finish_tutorial_to_menu()
				return
		if hud.tutorial_complete:
			return
	if hud.line_cancel_id >= 0:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = (event as InputEventMouseButton).position
			if hud.line_cancel_at(pos):
				_cancel_line_by_id(hud.line_cancel_id)
			else:
				hud.hide_line_cancel()
			get_viewport().set_input_as_handled()
		return
	if hud.mode_menu or hud.settings_menu or hud.week_modal or hud.game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# HUD 在 CanvasLayer 里，必须用屏幕坐标命中；世界拖拽才用世界坐标
		var pos: Vector2 = (event as InputEventMouseButton).position
		# 左上角线路颜色条：点开"取消整条线路"的叉按钮
		var chip_line_id := hud.line_chip_at(pos)
		if chip_line_id >= 0:
			hud.show_line_cancel(chip_line_id)
			Audio.play("click")
			get_viewport().set_input_as_handled()
			return
		# 左上角库存图标：拖到地图上放资源
		var stock := hud.stock_icon_at(pos)
		if stock != "" and simulation != null:
			var count := 0
			match stock:
				"train": count = simulation.inventory_trains
				"express": count = simulation.inventory_high_speed
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
			return
		if hud.settings_button_at(pos):
			_open_settings()
			Audio.play("click")
			get_viewport().set_input_as_handled()
			return
		if hud.pause_button_at(pos):
			Game.paused = not Game.paused
			hud.paused = Game.paused
			Audio.play("click")
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.startup_intro_active:
		# 动画期间吞掉输入；任意点击/按键跳过，避免误触后面的模式卡
		if (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed):
			hud.skip_startup_intro()
			get_viewport().set_input_as_handled()
		return
	if hud != null and hud.line_cancel_id >= 0:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_ESCAPE:
			hud.hide_line_cancel()
		return
	if hud != null and hud.leaderboard_open:
		var back := false
		if event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_ESCAPE:
			back = true
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			back = hud.leaderboard_back_at((event as InputEventMouseButton).position)
		if back:
			hud.hide_leaderboard()
		return
	if hud != null and hud.map_hall_open:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_ESCAPE:
			hud.hide_map_hall()
			return
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = (event as InputEventMouseButton).position
			var row := hud.map_hall_row_at(pos)
			if row >= 0:
				_download_hall_map(row)
			elif hud.map_hall_back_at(pos):
				hud.hide_map_hall()
		return
	if hud != null and hud.mode_menu:
		_handle_mode_menu_input(event)
		return
	if hud != null and hud.settings_menu:
		_handle_settings_input(event)
		return
	if hud != null and hud.week_modal:
		_handle_week_input(event)
		return
	if hud != null and hud.game_over:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = (event as InputEventMouseButton).position
			if hud.game_over_restart_at(pos):
				_restart()
				return
			if hud.game_over_menu_at(pos):
				_back_to_menu()
				return
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_R:
					_restart()
				KEY_M:
					_back_to_menu()
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
			KEY_4:
				_choose_mode(GameMode.Kind.MANAGER)
			KEY_5:
				_choose_mode(GameMode.Kind.TUTORIAL)
			KEY_E:
				_open_map_editor()
			KEY_D:
				_open_daily_leaderboard()
			KEY_H:
				_open_map_hall()
			KEY_L:
				_open_map_leaderboard()
			KEY_LEFT:
				_cycle_city(-1)
			KEY_RIGHT:
				_cycle_city(1)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).position
		if hud.editor_button_at(pos):
			_open_map_editor()
			return
		if hud.daily_board_button_at(pos):
			_open_daily_leaderboard()
			return
		if hud.map_hall_button_at(pos):
			_open_map_hall()
			return
		if hud.map_rank_button_at(pos):
			_open_map_leaderboard()
			return
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
	if hud.name_edit_open:
		hud.hide_name_editor()
	Game.paused = true
	hud.show_settings()
	_sync_settings_values()
	if editor != null:
		editor.set_process_unhandled_input(false)


func _close_settings() -> void:
	if hud == null:
		return
	hud.hide_name_editor()
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
		"player_name": String(Save.get_setting("player_name", "玩家")),
		"station_remove_time": float(Save.get_setting("station_remove_time", 0.8)),
	}


func _apply_editor_settings() -> void:
	if editor != null and Save != null:
		editor.dwell_remove_time = float(Save.get_setting("station_remove_time", 0.8))


func _on_player_name_submitted(player_name: String) -> void:
	if Save != null:
		Save.set_setting("player_name", player_name)
	_sync_settings_values()


func _handle_settings_input(event: InputEvent) -> void:
	if hud != null and hud.name_edit_open:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_ESCAPE:
			hud.hide_name_editor()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).position
		var vp := get_viewport_rect().size
		var row_width := 820.0
		var step := 80.0
		var start_x := (vp.x - row_width) * 0.5
		var start_y := vp.y * 0.5 - 360.0
		var index := int(floor((pos.y - start_y) / step))
		if index >= 0 and index < hud.settings_row_count():
			var row := Rect2(start_x, start_y + float(index) * step, row_width, 72.0)
			if row.has_point(pos):
				var minus_row := hud.settings_minus_at(pos)
				if minus_row >= 0:
					hud.settings_index = minus_row
					_adjust_setting(minus_row, -1)
					return
				var plus_row := hud.settings_plus_at(pos)
				if plus_row >= 0:
					hud.settings_index = plus_row
					_adjust_setting(plus_row, 1)
					return
				hud.settings_index = index
				if index in [0, 3, 4, 5, 6, 7, 8]:
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
		5:
			var remove_time := clampf(
				float(Save.get_setting("station_remove_time", 0.8)) + 0.1 * direction, 0.4, 2.0)
			Save.set_setting("station_remove_time", remove_time)
			_apply_editor_settings()
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
			_adjust_setting(5, 1)
		6:
			hud.show_name_editor(String(Save.get_setting("player_name", "玩家")))
		7:
			_close_settings()
			_restart()
		8:
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
		hud.show_week(cards, week_number,
			simulation.pending_reward_title if simulation != null else "")
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
		"express":
			ok = simulation.place_train(simulation.nearest_line(pos), pos, true)
			if ok:
				Audio.play("board")
			else:
				hud.show_toast(Loc.t("把新干线拖到一条线路上", "Drop the Shinkansen onto a line"))
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
	_record_run_result()
	_ending_score = score
	_ending_best = maxi(score, _best_for_mode())
	_ending_can_restart = not Game.is_daily()
	_ending_station = _station
	_ending_timer = 0.0
	_ending_overlay_shown = false
	_ending_focus = _station != null
	if hud != null:
		hud.ending_focus = true
	if editor != null:
		editor.set_process_unhandled_input(false)
	if not _ending_focus and hud != null:
		hud.show_game_over(_ending_score, _ending_best, _ending_can_restart)


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
	_apply_editor_settings()


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
	hud.name_submitted.connect(_on_player_name_submitted)
	if Cloud != null:
		Cloud.updated.connect(_on_cloud_updated)

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
	elif Game.mode == GameMode.Kind.TUTORIAL:
		_setup_tutorial()
	else:
		if Game.mode == GameMode.Kind.MANAGER:
			# 管理模式：固定 1x，一次性生成 40 座车站，之后不再生成
			if camera != null:
				camera.zoom = Vector2.ONE
				simulation.current_camera_zoom = 1.0
			simulation.spawner.spawn_rect = simulation.spawn_world_rect()
			simulation.spawner.spawn_manager_layout(network, 40, level.station_shape_weights)
		else:
			# 开局固定三座基础车站：圆形（居民区）、三角形（商务区）、方形（车站）
			simulation.spawner.spawn_rect = simulation.spawn_world_rect()
			simulation.spawner.spawn_starting_trio(network)


## 新手教程：三座固定位置的实际站台，不随机生成，不自动配车。
func _setup_tutorial() -> void:
	if camera != null:
		camera.zoom = Vector2(2.0, 2.0)
		simulation.current_camera_zoom = 2.0
	_tutorial_station_a = network.add_station(Vector2(850, 500), Shape.Kind.CIRCLE)
	_tutorial_station_b = network.add_station(Vector2(1250, 500), Shape.Kind.SQUARE)
	_tutorial_station_c = network.add_station(Vector2(1050, 780), Shape.Kind.TRIANGLE)
	network.touch()
	_tutorial = TutorialController.new()
	_tutorial.setup(network, simulation, _tutorial_station_a,
		_tutorial_station_b, _tutorial_station_c)
	_tutorial.step_changed.connect(_on_tutorial_step_changed)
	_tutorial.finished.connect(_on_tutorial_finished)
	_tutorial_upgrade_offered = false
	if hud != null:
		hud.map_name = Loc.t("新手教程", "Tutorial")
	_refresh_tutorial_hud()


func _on_tutorial_step_changed(_index: int) -> void:
	_refresh_tutorial_hud()
	if _tutorial != null and _tutorial.step == 11 and not _tutorial_upgrade_offered:
		_tutorial_upgrade_offered = true
		# 复用正式周结算：HUD 周卡弹窗、暂停和选卡逻辑都不另写一套
		simulation.offer_week_reward()


func _refresh_tutorial_hud() -> void:
	if hud == null or _tutorial == null:
		return
	hud.tutorial_active = true
	hud.tutorial_complete = _tutorial.completed
	hud.tutorial_step = _tutorial.step
	hud.tutorial_total = TutorialController.TOTAL_STEPS
	hud.tutorial_title = _tutorial.title()
	hud.tutorial_body = _tutorial.body()
	hud.tutorial_hint = _tutorial.hint()
	hud.tutorial_highlights = _tutorial.highlights()
	hud.queue_redraw()


func _on_tutorial_finished() -> void:
	Game.paused = true
	if editor != null:
		editor.set_process_unhandled_input(false)
	_refresh_tutorial_hud()


func _finish_tutorial_to_menu() -> void:
	Game.paused = false
	_tutorial = null
	if hud != null:
		hud.tutorial_active = false
	Game.pending_mode = -1
	get_tree().reload_current_scene()


func _start_after_tutorial() -> void:
	Game.paused = false
	_tutorial = null
	if hud != null:
		hud.tutorial_active = false
	Game.pending_mode = GameMode.Kind.CLASSIC
	Game.pending_city = Game.city_id
	get_tree().reload_current_scene()


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
			if _name_edit_arg and Save != null:
				hud.show_name_editor(String(Save.get_setting("player_name", "玩家")))
			editor.set_process_unhandled_input(false)
		"cancel":
			if not network.lines.is_empty():
				hud.show_line_cancel(network.lines[0].id)
				Game.paused = true
				editor.set_process_unhandled_input(false)
		"overlap":
			# 调试姿态：让前两条线完全重叠，检查渲染偏移与端点手柄错开
			if network.lines.size() >= 2:
				var src: MetroLine = network.lines[0]
				var dst: MetroLine = network.lines[1]
				dst.stops.clear()
				for st in src.stops:
					dst.stops.append(st)
				dst.is_loop = src.is_loop
				dst.bend_flips = src.bend_flips.duplicate()
				dst.rebuild()
				network.touch()
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
		"express":
			# 演示：新干线 + 放大后的资源图标
			simulation.inventory_high_speed = 2
			if network.lines.size() >= 2:
				var line: MetroLine = network.lines[1]
				var mid := line.geometry.sample(line.geometry.total_length * 0.5).origin
				simulation.place_train(line, mid, true)
			_advance_sim(30)
		"paused":
			Game.paused = true
			hud.paused = true
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
		elif arg.begins_with("--shot-delay="):
			_shot_delay = maxf(0.1, float(arg.trim_prefix("--shot-delay=")))
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
		elif arg.begins_with("--open="):
			_open_arg = arg.trim_prefix("--open=")
		elif arg == "--name-edit":
			_name_edit_arg = true
		elif arg == "--cloud-post-test":
			_cloud_post_test = true
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


func _run_cloud_post_test() -> void:
	await get_tree().create_timer(0.5).timeout
	if Cloud != null:
		Cloud.submit_best("classic", "cloud_smoke_city", 42)
	await get_tree().create_timer(3.0).timeout
	print("CLOUD_POST_TEST_DONE")
	get_tree().quit(0)


func _capture_and_quit() -> void:
	await get_tree().create_timer(_shot_delay).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	_print_stats()
	print("SCREENSHOT ", _shot_path, " err=", err)
	get_tree().quit(0 if err == OK else 1)
