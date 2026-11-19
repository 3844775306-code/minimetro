class_name Hud
extends Control
## HUD 与全部菜单：资源/分数、周抽卡、换乘站点选、模式选择、暂停/设置、结束遮罩。
## 文本全部走 Loc 双语；中文字体用 SystemFont 取系统字体（不打包字体文件）。

const INK := Color("#2B2B2B")
const MUTED := Color("#7C7568")
const PAPER := Color("#FBF8F1")
const WATER := Color("#CFE4EA")
const ACCENT := Color("#D64545")
const GOLD := Color("#E8A33D")
const TEAL := Color("#2F8F9D")
const DEEP := Color("#121518")
const HUD_OCCLUSION_SHADER := preload("res://art/shaders/hud_occlusion.gdshader")
const CHIP_W := 46.0
const CHIP_H := 13.0
const CHIP_GAP := 12.0

var network: MetroNetwork = null
var level: LevelData = null
var font: Font = null

var paused := false
var speed := 1.0
var score := 0
## 无尽模式的评价指标：近 30 秒平均每 5 秒客运量
var throughput := 0.0
var endless_mode := false
var week := 1
var best_score := 0
## 游戏内时钟（1 现实秒 = 1 游戏小时）
var clock_hours := 7.0
var is_night := false
var weekday := ""
## 城镇发展阶段（村庄/小镇/城市/大都市 · 车站数）
var stage_label := ""
## 当前地图名（显示在屏幕顶部中央）
var map_name := ""
## 操作提示显示剩余时间；超时后隐藏，避免长期占着底部
var hint_left := 18.0
## 鼠标悬停车站时显示的地标名称
var hover_landmark := ""
var hover_screen := Vector2.ZERO
## 库存（可拖到地图上的资源）
var stock_counts := {"train": 0, "carriage": 0, "interchange": 0}
var _speed_rects: Array[Rect2] = []
var _pause_rect := Rect2()
var _settings_rect := Rect2()
var _stock_rects := {}
var _line_chips: Array[Dictionary] = []
var line_cancel_id := -1
var _line_cancel_rect := Rect2()

var game_over := false
var ending_focus := false
var final_score := 0
var game_over_can_restart := true
var _game_over_restart_rect := Rect2()
var _game_over_menu_rect := Rect2()

var week_modal := false
var reward_title := ""
var week_cards: Array = []
var _card_rects: Array[Rect2] = []

var mode_menu := false
## 主菜单三层配置：资源获取 × 无尽 × 管理
var menu_config: RunConfig = RunConfig.classic()
var menu_best := 0
var _menu_base_rects: Array[Rect2] = []
var _menu_endless_rects: Array[Rect2] = []
var _menu_manager_rects: Array[Rect2] = []
var _menu_start_rect := Rect2()
var _daily_card_rect := Rect2()
var _tutorial_card_rect := Rect2()
## 发展模式：金币经济 + 商店
var development_mode := false
var coins := 0
var shop_open := false
## 每种商品的购买次数（用于动态价格显示）
var shop_purchase_counts := {}
var _shop_button_rect := Rect2()
var _shop_close_rect := Rect2()
var _shop_item_rects: Array[Rect2] = []
## 启动动画：只在本次启动第一次进入模式菜单时播放
var startup_intro_active := false
var startup_intro_time := 0.0
const STARTUP_INTRO_DURATION := 2.4
var mode_bests := {}
var _mode_rects: Array[Rect2] = []
var _editor_button_rect := Rect2()
var _daily_board_rect := Rect2()
var _map_hall_rect := Rect2()
var _map_rank_rect := Rect2()

## 新手教程引导层
var tutorial_active := false
var tutorial_step := 0
var tutorial_total := 5
var tutorial_title := ""
var tutorial_body := ""
var tutorial_hint := ""
var tutorial_complete := false
var tutorial_highlights: Array[Vector2] = []
var _tutorial_skip_rect := Rect2()
var _tutorial_start_rect := Rect2()
var _tutorial_menu_rect := Rect2()

## 排行榜 / 地图大厅浮层
var leaderboard_open := false
var leaderboard_title := ""
var leaderboard_subtitle := ""
var leaderboard_lines: Array[String] = []
var _leaderboard_back_rect := Rect2()
## 地图排行榜按配置分类：每个分类有 title/lines
var _leaderboard_categories: Array[Dictionary] = []
var _leaderboard_category_index := 0
var _leaderboard_category_rects: Array[Rect2] = []
var map_hall_open := false
var map_hall_entries: Array = []
var _map_hall_row_rects: Array[Rect2] = []
var _map_hall_back_rect := Rect2()
## 模式菜单里的城市选择
var menu_cities: Array = []
var city_index := 0
var _city_arrow_rects: Array[Rect2] = []

var settings_menu := false
var settings_index := 0
## 主循环每帧回填：master_volume / music_volume / fullscreen / language / player_name
var settings_values := {}
var _settings_minus_rects: Array[Rect2] = []
var _settings_plus_rects: Array[Rect2] = []
var _settings_minus_rows: Array[int] = []
var _settings_plus_rows: Array[int] = []

var toast_text := ""
var toast_left := 0.0
## 玩家名输入框（设置菜单中的"玩家名"）
var name_edit: LineEdit = null
var name_edit_open := false
var name_edit_required := false
var name_edit_error := false
## 新玩家强制教程：不显示跳过按钮
var tutorial_forced := false
signal name_submitted(player_name: String)

## 手机 / 低高度横屏把 UI 字号整体放大，避免 1080p 手机上文字过小。
var ui_text_scale := 1.0
var _mobile_ui := false

## 四角 HUD 遮挡站台时自动“隐身”，但保留很淡的轮廓；输入也会穿透到站台。
var _hud_material: ShaderMaterial = null
var _ghost_tl := 0.0
var _ghost_tr := 0.0
var _ghost_br := 0.0
var _ghost_bl := 0.0
var _tl_rect := Rect2()
var _tr_rect := Rect2()
var _br_rect := Rect2()
var _bl_rect := Rect2()


## 四角 HUD 遮挡站台时自动“隐身”，但保留很淡的轮廓；输入也会穿透到站台。
func _update_corner_occlusion(delta: float) -> void:
	if _hud_material == null:
		return
	var vp := get_viewport_rect().size
	_tl_rect = Rect2(24.0, 36.0, 748.0, 176.0)
	_tr_rect = Rect2(vp.x - 342.0, 18.0, 312.0, 232.0)
	_br_rect = Rect2(vp.x - 470.0, vp.y - 140.0, 454.0, 132.0)
	_bl_rect = Rect2(28.0, vp.y - 142.0, 264.0, 104.0)
	var playable := network != null and not mode_menu and not game_over \
		and not week_modal and not settings_menu and not leaderboard_open \
		and not map_hall_open and not startup_intro_active and not shop_open
	var hit_tl := false
	var hit_tr := false
	var hit_br := false
	var hit_bl := false
	if playable:
		var canvas := get_viewport().get_canvas_transform()
		for station in network.stations:
			var screen_pos: Vector2 = canvas * station.pos
			var margin := Shape.STATION_RADIUS + 12.0
			if _tl_rect.grow(margin).has_point(screen_pos):
				hit_tl = true
			if _tr_rect.grow(margin).has_point(screen_pos):
				hit_tr = true
			if _br_rect.grow(margin).has_point(screen_pos):
				hit_br = true
			if development_mode and _bl_rect.grow(margin).has_point(screen_pos):
				hit_bl = true
	var follow := clampf(delta * 7.0, 0.0, 1.0)
	if not playable:
		_ghost_tl = 0.0
		_ghost_tr = 0.0
		_ghost_br = 0.0
		_ghost_bl = 0.0
	else:
		_ghost_tl = move_toward(_ghost_tl, 1.0 if hit_tl else 0.0, follow)
		_ghost_tr = move_toward(_ghost_tr, 1.0 if hit_tr else 0.0, follow)
		_ghost_br = move_toward(_ghost_br, 1.0 if hit_br else 0.0, follow)
		_ghost_bl = move_toward(_ghost_bl, 1.0 if hit_bl else 0.0, follow)
	_hud_material.set_shader_parameter("viewport_size", vp)
	_hud_material.set_shader_parameter("tl_rect", _rect_to_vec4(_tl_rect))
	_hud_material.set_shader_parameter("tr_rect", _rect_to_vec4(_tr_rect))
	_hud_material.set_shader_parameter("br_rect", _rect_to_vec4(_br_rect))
	_hud_material.set_shader_parameter("bl_rect", _rect_to_vec4(_bl_rect))
	_hud_material.set_shader_parameter("tl_ghost", _ghost_tl)
	_hud_material.set_shader_parameter("tr_ghost", _ghost_tr)
	_hud_material.set_shader_parameter("br_ghost", _ghost_br)
	_hud_material.set_shader_parameter("bl_ghost", _ghost_bl)


static func _rect_to_vec4(rect: Rect2) -> Vector4:
	return Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)


## 这个屏幕点是否落在正在“隐身”的 HUD 角上；Main 用它让点击穿透到站台。
func ui_ghost_at(pos: Vector2) -> bool:
	return (_ghost_tl > 0.18 and _tl_rect.has_point(pos)) \
		or (_ghost_tr > 0.18 and _tr_rect.has_point(pos)) \
		or (_ghost_br > 0.18 and _br_rect.has_point(pos)) \
		or (_ghost_bl > 0.18 and _bl_rect.has_point(pos))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = UiFonts.get_font()
	_mobile_ui = OS.get_name() in ["Android", "iOS"] \
		or OS.has_feature("mobile") \
		or OS.get_cmdline_user_args().has("--mobile-ui") \
		or DisplayServer.is_touchscreen_available()
	var window_size := DisplayServer.window_get_size()
	if window_size.x > 0 and window_size.y > 0 and window_size.y <= 1120 \
			and window_size.x >= window_size.y:
		_mobile_ui = true
	ui_text_scale = 1.28 if _mobile_ui else 1.0
	name_edit = LineEdit.new()
	name_edit.add_theme_font_override("font", font)
	name_edit.visible = false
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.max_length = 16
	name_edit.add_theme_font_size_override("font_size", _scaled_size(32))
	name_edit.text_submitted.connect(_on_name_edit_submitted)
	add_child(name_edit)
	_hud_material = ShaderMaterial.new()
	_hud_material.shader = HUD_OCCLUSION_SHADER
	material = _hud_material
	set_process(true)


func setup(net: MetroNetwork, lvl: LevelData) -> void:
	network = net
	level = lvl
	queue_redraw()


func show_toast(message: String) -> void:
	toast_text = message
	toast_left = 2.0
	queue_redraw()


func show_game_over(final: int, best: int, can_restart: bool = true) -> void:
	game_over = true
	final_score = final
	best_score = best
	game_over_can_restart = can_restart
	queue_redraw()


func game_over_restart_at(pos: Vector2) -> bool:
	return game_over_can_restart and _game_over_restart_rect.has_point(pos)


func game_over_menu_at(pos: Vector2) -> bool:
	return _game_over_menu_rect.has_point(pos)


func show_week(cards: Array, week_number: int, title_text: String = "") -> void:
	week_cards = cards
	week = week_number
	reward_title = title_text
	week_modal = true
	queue_redraw()


func hide_week() -> void:
	week_modal = false
	reward_title = ""
	week_cards = []
	_card_rects = []
	queue_redraw()


func show_station_pick() -> void:
	queue_redraw()


func hide_station_pick() -> void:
	queue_redraw()


func show_mode_menu() -> void:
	mode_menu = true
	game_over = false
	week_modal = false
	queue_redraw()


func hide_mode_menu() -> void:
	mode_menu = false
	queue_redraw()


func show_shop() -> void:
	shop_open = true
	queue_redraw()


func hide_shop() -> void:
	shop_open = false
	_shop_item_rects = []
	_shop_close_rect = Rect2()
	queue_redraw()


func shop_button_at(pos: Vector2) -> bool:
	return development_mode and not shop_open and _shop_button_rect.has_point(pos)


func shop_close_at(pos: Vector2) -> bool:
	return _shop_close_rect.has_point(pos)


## 返回被点击的商店条目 id；“” 表示没点中。
func shop_item_at(pos: Vector2) -> String:
	var items := ShopCatalog.items()
	for i in _shop_item_rects.size():
		if i < items.size() and _shop_item_rects[i].has_point(pos):
			return String(items[i]["id"])
	return ""


func mode_card_at(pos: Vector2) -> int:
	for i in _mode_rects.size():
		if _mode_rects[i].has_point(pos):
			return i
	return -1


func menu_base_at(pos: Vector2) -> int:
	for i in _menu_base_rects.size():
		if _menu_base_rects[i].has_point(pos):
			return i
	return -1


func menu_endless_at(pos: Vector2) -> int:
	for i in _menu_endless_rects.size():
		if _menu_endless_rects[i].has_point(pos):
			return i
	return -1


func menu_manager_at(pos: Vector2) -> int:
	for i in _menu_manager_rects.size():
		if _menu_manager_rects[i].has_point(pos):
			return i
	return -1


func menu_start_at(pos: Vector2) -> bool:
	return _menu_start_rect.has_point(pos)


func daily_card_at(pos: Vector2) -> bool:
	return _daily_card_rect.has_point(pos)


func tutorial_card_at(pos: Vector2) -> bool:
	return _tutorial_card_rect.has_point(pos)


## 城市切换箭头：-1 = 上一个，1 = 下一个，0 = 没点中。
func city_arrow_at(pos: Vector2) -> int:
	if _city_arrow_rects.size() < 2:
		return 0
	if _city_arrow_rects[0].has_point(pos):
		return -1
	if _city_arrow_rects[1].has_point(pos):
		return 1
	return 0


## 周抽卡弹窗的点击命中（-1 = 没点中）。
func card_at(pos: Vector2) -> int:
	for i in _card_rects.size():
		if _card_rects[i].has_point(pos):
			return i
	return -1


func show_settings() -> void:
	settings_menu = true
	settings_index = 0
	queue_redraw()


func hide_settings() -> void:
	settings_menu = false
	queue_redraw()


func settings_row_count() -> int:
	return 9


## 音量 / 移站时间的触屏 - / + 按钮命中（返回行号，-1 表示没点中）。
func settings_minus_at(pos: Vector2) -> int:
	for i in _settings_minus_rects.size():
		if _settings_minus_rects[i].has_point(pos):
			return _settings_minus_rows[i]
	return -1


func settings_plus_at(pos: Vector2) -> int:
	for i in _settings_plus_rects.size():
		if _settings_plus_rects[i].has_point(pos):
			return _settings_plus_rows[i]
	return -1


func show_name_editor(current_name: String, required: bool = false) -> void:
	if name_edit == null:
		return
	name_edit_open = true
	name_edit_required = required
	name_edit_error = false
	var vp := get_viewport_rect().size
	name_edit.position = Vector2(vp.x * 0.5 - 350.0, vp.y * 0.5 - 36.0)
	name_edit.size = Vector2(700.0, 80.0)
	name_edit.text = current_name
	name_edit.visible = true
	name_edit.grab_focus()
	name_edit.select_all()
	queue_redraw()


func hide_name_editor() -> void:
	name_edit_open = false
	name_edit_required = false
	if name_edit != null:
		name_edit.visible = false
		name_edit.release_focus()
	queue_redraw()


func _on_name_edit_submitted(text: String) -> void:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		if name_edit_required:
			name_edit_error = true
			queue_redraw()
			return
		cleaned = "玩家"
	name_edit_error = false
	hide_name_editor()
	name_submitted.emit(cleaned)


func _process(delta: float) -> void:
	_update_ui_scale()
	if toast_left > 0.0:
		toast_left = maxf(0.0, toast_left - delta)
	if startup_intro_active:
		startup_intro_time += delta
		if startup_intro_time >= STARTUP_INTRO_DURATION:
			startup_intro_active = false
	if not mode_menu and not paused:
		hint_left = maxf(0.0, hint_left - delta)
	_update_corner_occlusion(delta)
	queue_redraw()


## 播放一次启动动画；点击/按键由 Main 调用 skip_startup_intro() 跳过。
## 手机端字号整体放大；桌面 2400×1200 保持原尺寸。
func _update_ui_scale() -> void:
	var win := DisplayServer.window_get_size()
	var compact_window := win.x > 0 and win.y > 0 and win.y <= 1120 and win.x >= win.y
	var target := 1.28 if (_mobile_ui or compact_window) else 1.0
	if not is_equal_approx(ui_text_scale, target):
		ui_text_scale = target
		queue_redraw()


## 手机端最小字号：以主菜单「发车」在手机上的字号为下限。
const MOBILE_MIN_FONT := 37

func _scaled_size(size: int) -> int:
	var scaled := maxi(1, int(round(float(size) * ui_text_scale)))
	if _mobile_ui:
		return maxi(scaled, MOBILE_MIN_FONT)
	return scaled


func _scaled_tracking(tracking: float) -> float:
	return tracking * ui_text_scale


func start_startup_intro() -> void:
	startup_intro_active = true
	startup_intro_time = 0.0
	queue_redraw()


func skip_startup_intro() -> void:
	startup_intro_active = false
	startup_intro_time = STARTUP_INTRO_DURATION
	queue_redraw()


func _draw() -> void:
	if font == null or level == null:
		return
	var vp := get_viewport_rect().size
	if startup_intro_active:
		# 先画菜单，再让启动动画淡出，最后一帧自然接到模式选择
		if mode_menu:
			_draw_mode_menu(vp)
		_draw_startup_intro(vp)
		return
	if not mode_menu:
		_draw_game_hud(vp)
	if tutorial_active:
		_draw_tutorial(vp)
	if week_modal:
		_draw_week(vp)
	if settings_menu:
		_draw_settings(vp)
	if game_over:
		_draw_game_over(vp)
	if mode_menu:
		_draw_mode_menu(vp)
	if leaderboard_open:
		_draw_leaderboard(vp)
	if map_hall_open:
		_draw_map_hall(vp)
	if shop_open:
		_draw_shop(vp)
	if name_edit_open:
		_draw_name_modal(vp)
	if line_cancel_id >= 0:
		_draw_line_cancel(vp)


# ---------------------------------------------------------------------------
# 游戏内 HUD
# ---------------------------------------------------------------------------

func _draw_game_hud(vp: Vector2) -> void:
	# 电影感边缘暗角，让地图中心更聚焦
	_draw_vignette(vp, 0.55)
	# 减负版 HUD：左上只留线色/库存，右上不再画面板（避免挡地图）
	_draw_panel(Rect2(34.0, 46.0, 720.0, 280.0 if _mobile_ui else 156.0))
	if map_name != "":
		_text_centered(map_name, vp.x * 0.5 + 2.0, 62.0, 32, Color(0.0, 0.0, 0.0, 0.20))
		_text_centered(map_name, vp.x * 0.5, 60.0, 32,
			Color(1.0, 1.0, 1.0, 0.88) if is_night else Color(MUTED, 0.85))
		_draw_accent_rule(Vector2(vp.x * 0.5, 76.0), 48.0, GOLD if not is_night else Color.WHITE)
	_draw_clock(vp)
	var extra := clampf((ui_text_scale - 1.0) / 0.28, 0.0, 1.0)
	if endless_mode:
		# 无尽轴的评价指标：发展模式看金币，经典看客运量
		var metric_text := Loc.t("平均每30秒 %.0f 金币", "%.0f coins / 30s") % throughput \
			if development_mode else Loc.t("平均每30秒 %.0f 人", "%.0f per 30s") % throughput
		var metric_y := 150.0 if development_mode else 160.0
		_text_right(metric_text,
			vp.x - 40.0, metric_y, 28, Color.WHITE if is_night else INK)
		_text_right(Loc.t("已送达 %d", "Delivered %d") % score,
			vp.x - 40.0, metric_y + 20.0 + 28.0 * extra, 20,
			Color(1.0, 1.0, 1.0, 0.78) if is_night else Color(MUTED, 0.9))
	else:
		_text_right(Loc.t("已送达 %d", "Delivered %d") % score, vp.x - 40.0, 162.0, 32,
			Color.WHITE if is_night else INK)
	var dev_coin_y := 0.0
	if development_mode:
		dev_coin_y = (232.0 + 40.0 * extra) if endless_mode else (204.0 + 24.0 * extra)
		var fare_y := dev_coin_y + (44.0 if _mobile_ui else 28.0)
		_text_right(Loc.t("金币 %d", "Coins %d") % coins, vp.x - 40.0, dev_coin_y, 30,
			Color(GOLD, 0.98))
		_text_right(Loc.t("票价 2 金币起", "Fare from 2 coins"), vp.x - 40.0, fare_y, 17,
			Color(1.0, 1.0, 1.0, 0.60) if is_night else Color(MUTED, 0.82))
	if stage_label != "":
		var stage_y := 222.0
		if development_mode:
			stage_y = dev_coin_y + (88.0 if _mobile_ui else (56.0 if endless_mode else 54.0))
		elif endless_mode:
			stage_y = 222.0 + 30.0 * extra
		_text_right(stage_label, vp.x - 40.0, stage_y, 20,
			Color(1.0, 1.0, 1.0, 0.68) if is_night else Color(MUTED, 0.78))
	_draw_resource_slots(vp)
	if development_mode:
		_draw_shop_button(vp)
	var show_hint := hint_left > 0.0 or (network != null and network.lines.is_empty())
	if show_hint:
		var hint_alpha: float = 1.0
		if hint_left > 0.0:
			hint_alpha = clampf(hint_left / 2.0, 0.0, 1.0)
		_text_centered(Loc.t(
			"拖拽画线 · 拖端点延伸 · 轻点翻折 · Ctrl+Z 撤销"
				if _mobile_ui else
				"拖拽画线 · 拖端点延伸 · 拖线段插站 · 轻点翻折 · 拖左上角图标放车 · Ctrl+Z 撤销 · Esc 设置",
			"Drag to draw · drag endpoint to extend · tap to flip · Ctrl+Z undo"
				if _mobile_ui else
				"Drag to draw · drag endpoint to extend · drag a segment to insert · tap to flip · drag top-left icons for vehicles · Ctrl+Z undo · Esc settings"
		), vp.x * 0.5, vp.y - 46.0, 22,
			Color(1.0, 1.0, 1.0, 0.72) if is_night else Color(MUTED, 0.9 * hint_alpha))
	if paused and not game_over and not settings_menu and not week_modal \
			and not mode_menu and not ending_focus and not tutorial_active \
			and not shop_open:
		_text_centered(Loc.t("已暂停", "Paused"), vp.x * 0.5, vp.y * 0.5, 44,
			Color(1.0, 1.0, 1.0, 0.85) if is_night else Color(INK, 0.75))
		_text_centered(Loc.t("可继续修改线路、调动车厢", "You can still edit lines and move carriages"),
			vp.x * 0.5, vp.y * 0.5 + 40.0, 22,
			Color(1.0, 1.0, 1.0, 0.7) if is_night else Color(MUTED, 0.75))
	_draw_speed_buttons(vp)
	if toast_left > 0.0:
		var alpha: float = clampf(toast_left / 0.5, 0.0, 1.0)
		var toast_size := font.get_string_size(toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			_scaled_size(26))
		var toast_rect := Rect2(
			Vector2(vp.x * 0.5 - minf(toast_size.x + 52.0, 900.0) * 0.5,
				vp.y - 158.0 if _mobile_ui else vp.y - 142.0),
			Vector2(minf(toast_size.x + 52.0, 900.0), 64.0 if _mobile_ui else 48.0))
		_draw_soft_shadow(toast_rect, 24.0, 0.20, Vector2(0.0, 8.0))
		var toast_poly := DrawUtil.rounded_rect(toast_rect, 24.0, 10)
		draw_colored_polygon(toast_poly, Color(DEEP, 0.82 * alpha))
		draw_polyline(DrawUtil.closed(toast_poly), Color(1.0, 1.0, 1.0, 0.16 * alpha), 1.2, true)
		draw_circle(Vector2(toast_rect.position.x + 24.0, toast_rect.get_center().y), 3.5,
			Color(GOLD, 0.9 * alpha), true, -1.0, true)
		_text_centered(toast_text, toast_rect.get_center().x,
			toast_rect.position.y + (46.0 if _mobile_ui else 32.0), 26,
			Color(1.0, 1.0, 1.0, alpha))
	# 悬停车站：显示这个形状代表的地标
	if hover_landmark != "":
		var text_size := font.get_string_size(hover_landmark, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, _scaled_size(15))
		var rect := Rect2(hover_screen + Vector2(20.0, -40.0),
			Vector2(text_size.x + 22.0, (48.0 if _mobile_ui else 28.0) * ui_text_scale))
		rect.position.x = clampf(rect.position.x, 12.0, vp.x - rect.size.x - 12.0)
		rect.position.y = clampf(rect.position.y, 12.0, vp.y - rect.size.y - 12.0)
		var poly := DrawUtil.rounded_rect(rect, 9.0, 6)
		_draw_soft_shadow(rect, 9.0, 0.18, Vector2(0.0, 4.0))
		draw_colored_polygon(poly, Color("#FBF8F1", 0.98))
		draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.45), 1.2, true)
		_text(hover_landmark, rect.position + Vector2(11.0,
			(36.0 if _mobile_ui else 21.0) * ui_text_scale), 18, INK)


func _draw_shop_button(vp: Vector2) -> void:
	_shop_button_rect = Rect2(38.0, vp.y - 128.0, 238.0, 78.0)
	var hovered := _shop_button_rect.has_point(get_global_mouse_position())
	_draw_soft_shadow(_shop_button_rect, 16.0, 0.20 if hovered else 0.12, Vector2(0.0, 7.0))
	var poly := DrawUtil.rounded_rect(_shop_button_rect, 16.0, 10)
	draw_colored_polygon(poly, Color("#FFFFFF") if hovered else Color(PAPER, 0.96))
	draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.55 if hovered else 0.32), 1.6, true)
	draw_circle(Vector2(_shop_button_rect.position.x + 38.0,
		_shop_button_rect.get_center().y), 17.0, Color(GOLD, 0.16), true, -1.0, true)
	draw_circle(Vector2(_shop_button_rect.position.x + 38.0,
		_shop_button_rect.get_center().y), 11.0, Color(GOLD, 0.92), true, -1.0, true)
	_text(Loc.t("商店", "Shop"), Vector2(_shop_button_rect.position.x + 66.0,
		_shop_button_rect.position.y + 34.0), 27, INK)
	_text_right(Loc.t("B", "B"), _shop_button_rect.end.x - 18.0,
		_shop_button_rect.end.y - 16.0, 16, Color(MUTED, 0.75))


func _draw_shop(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.06, 0.07, 0.78))
	_draw_vignette(vp, 1.3)
	var panel := Rect2(vp.x * 0.5 - 750.0, vp.y * 0.5 - 420.0, 1500.0, 840.0)
	_draw_soft_shadow(panel, 24.0, 0.46, Vector2(0.0, 18.0))
	var poly := DrawUtil.rounded_rect(panel, 24.0, 12)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.99))
	draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.55), 1.8, true)
	draw_rect(Rect2(panel.position + Vector2(38.0, 0.0),
		Vector2(panel.size.x - 76.0, 5.0)), Color(GOLD, 0.92))
	var cx := panel.get_center().x
	_text_centered(Loc.t("资源商店", "RESOURCE SHOP"), cx, panel.position.y + 72.0, 42, INK)
	_text_centered(Loc.t("送达乘客赚金币 · 金币兑换运营资源",
		"Deliver passengers for coins · spend them on resources"),
		cx, panel.position.y + 108.0, 21, MUTED)
	var coin_badge := Rect2(cx - 120.0, panel.position.y + 126.0, 240.0, 42.0)
	var coin_poly := DrawUtil.rounded_rect(coin_badge, 21.0, 8)
	draw_colored_polygon(coin_poly, Color(GOLD, 0.13))
	draw_circle(Vector2(coin_badge.position.x + 24.0, coin_badge.get_center().y), 8.0,
		Color(GOLD, 0.95), true, -1.0, true)
	_text_centered(Loc.t("金币 %d", "Coins %d") % coins, cx, coin_badge.get_center().y + 10.0,
		24, INK)
	_shop_close_rect = Rect2(panel.end.x - 92.0, panel.position.y + 30.0, 58.0, 58.0)
	var close_center := _shop_close_rect.get_center()
	var close_hovered := _shop_close_rect.has_point(get_global_mouse_position())
	draw_circle(close_center, 26.0, Color(INK, 0.10 if close_hovered else 0.05), true, -1.0, true)
	draw_line(close_center + Vector2(-9.0, -9.0), close_center + Vector2(9.0, 9.0),
		Color(INK, 0.8), 3.0, true)
	draw_line(close_center + Vector2(9.0, -9.0), close_center + Vector2(-9.0, 9.0),
		Color(INK, 0.8), 3.0, true)

	var items := ShopCatalog.items()
	var columns := 3
	var card_w := 430.0
	var card_h := 258.0
	var gap := 24.0
	var grid_w := card_w * columns + gap * (columns - 1)
	var start_x := cx - grid_w * 0.5
	var start_y := panel.position.y + 194.0
	var accents := [GOLD, TEAL, ACCENT, Color("#4F9E63"), Color("#7A6BB5"), Color("#E67E22")]
	_shop_item_rects = []
	var mouse := get_global_mouse_position()
	for i in items.size():
		var item: Dictionary = items[i]
		var col := i % columns
		var row := i / columns
		var base := Rect2(start_x + float(col) * (card_w + gap),
			start_y + float(row) * (card_h + gap), card_w, card_h)
		_shop_item_rects.append(base)
		var hovered := base.has_point(mouse)
		var rect := Rect2(base.position + Vector2(0.0, -5.0 if hovered else 0.0), base.size)
		var price := ShopCatalog.price_for(String(item["id"]),
			int(shop_purchase_counts.get(String(item["id"]), 0)))
		var next_price := ShopCatalog.price_hint(String(item["id"]),
			int(shop_purchase_counts.get(String(item["id"]), 0)))
		var affordable := coins >= price
		var accent: Color = accents[i % accents.size()]
		_draw_soft_shadow(rect, 16.0, 0.26 if hovered else 0.10, Vector2(0.0, 9.0))
		var card_poly := DrawUtil.rounded_rect(rect, 16.0, 8)
		draw_colored_polygon(card_poly, Color("#FFFFFF") if hovered else Color(PAPER, 0.98))
		draw_rect(Rect2(rect.position + Vector2(20.0, 0.0), Vector2(rect.size.x - 40.0, 5.0)),
			Color(accent, 0.90))
		draw_polyline(DrawUtil.closed(card_poly), Color(accent, 0.34 if hovered else 0.16),
			1.8 if hovered else 1.2, true)
		_text_centered(String(item["title"]), rect.get_center().x,
			rect.position.y + 58.0, 30, INK)
		if not _mobile_ui:
			_text_wrapped(String(item["desc"]), rect.get_center().x,
				rect.position.y + 92.0, 19, rect.size.x - 44.0, MUTED)
		var price_rect := Rect2(rect.position.x + 22.0, rect.end.y - 66.0,
			rect.size.x - 44.0, 44.0)
		var price_poly := DrawUtil.rounded_rect(price_rect, 12.0, 6)
		draw_colored_polygon(price_poly, Color(accent, 0.12 if affordable else 0.05))
		_text_centered(Loc.t("%d 金币 · 下次 %d", "%d coins · next %d") % [price, next_price],
			price_rect.get_center().x, price_rect.position.y + 29.0, 19,
			Color(INK, 0.92 if affordable else 0.38))
		if not affordable:
			_text_centered(Loc.t("金币不足", "Not enough"), rect.get_center().x,
				rect.end.y - 78.0, 15, Color(ACCENT, 0.72))
		elif hovered:
			_text_centered(Loc.t("点击购买", "Click to buy"), rect.get_center().x,
				rect.end.y - 78.0, 15, Color(TEAL, 0.82))
		else:
			_text_centered(Loc.t("可购买", "Available"), rect.get_center().x,
				rect.end.y - 78.0, 15, Color(TEAL, 0.72))
	_text_centered(Loc.t("点击卡片购买 · 同种商品每次 +25% · 无购买上限 · Esc / B 关闭 · 游戏已暂停",
		"Click to buy · same item +25% each time · no limit · Esc / B close · paused"),
		cx, panel.end.y - 34.0, 19, Color(MUTED, 0.78))
	if toast_left > 0.0:
		var alpha := clampf(toast_left / 0.5, 0.0, 1.0)
		_text_centered(toast_text, cx, panel.end.y - 64.0, 19, Color(INK, alpha))


## HUD 半透明纸面板：地图变丰富后保证左上/右上文字可读
func _draw_panel(rect: Rect2) -> void:
	_draw_soft_shadow(rect, 14.0, 0.16, Vector2(0.0, 7.0))
	var poly := DrawUtil.rounded_rect(rect, 14.0, 8)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.94))
	draw_polyline(DrawUtil.closed(poly), Color(0.72, 0.69, 0.62, 0.42), 1.4, true)
	# 左缘强调条，像一张装订标签
	draw_line(rect.position + Vector2(3.0, 14.0), Vector2(rect.position.x + 3.0, rect.end.y - 14.0),
		Color(ACCENT, 0.55), 3.0, true)


## 12 小时制时钟：12 点在上、6 点在下；到了夜晚整块表盘变黑、指针变白。
func _draw_clock(vp: Vector2) -> void:
	var center := Vector2(vp.x - 88.0, 62.0)
	var radius := 34.0
	var strength := Simulation.night_strength(clock_hours)
	var face := Color("#FBF8F1").lerp(Color("#1C1C1E"), strength)
	# 悬浮表盘的柔和外圈 + 投影
	draw_circle(center + Vector2(0.0, 5.0), radius + 3.0, Color(0.04, 0.05, 0.06, 0.14), true, -1.0, true)
	draw_circle(center, radius + 10.0, Color(face, 0.10), true, -1.0, true)
	draw_circle(center, radius, face)
	draw_arc(center, radius + 1.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.28), 1.2, true)
	var hand_color := Color(0.12, 0.13, 0.15, 0.95).lerp(Color(1.0, 1.0, 1.0, 0.95), strength)
	var tick_color := Color(0.16, 0.17, 0.19, 0.5).lerp(Color(1.0, 1.0, 1.0, 0.55), strength)
	# 12 个刻度
	for i in 12:
		var a := TAU * float(i) / 12.0
		var dir := Vector2(sin(a), -cos(a))
		var inner := radius - (11.0 if i % 3 == 0 else 6.0)
		draw_line(center + dir * inner, center + dir * (radius - 2.0), tick_color, 1.6, true)
	# 时针：12 小时一圈
	var hour12 := fmod(clock_hours, 12.0)
	var hand_angle := TAU * hour12 / 12.0
	var hand_dir := Vector2(sin(hand_angle), -cos(hand_angle))
	draw_line(center, center + hand_dir * (radius - 9.0), hand_color, 3.5, true)
	draw_circle(center, 4.0, hand_color, true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 48,
		Color(1.0, 1.0, 1.0, 0.55) if strength > 0.5 else Color(0.16, 0.17, 0.19, 0.7), 2.5, true)
	# 数字时间（12 小时制 + 上午/下午）
	var hour := int(floor(fmod(clock_hours, 24.0) + 0.0001)) % 24
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	var minutes := int((clock_hours - floor(clock_hours)) * 60.0)
	var suffix := Loc.t("上午", "AM") if hour < 12 else Loc.t("下午", "PM")
	var clock_text := "%s  %02d:%02d %s" % [weekday, display_hour, mini(minutes, 59), suffix]
	if _mobile_ui:
		_text_right(clock_text, vp.x - 40.0, center.y + radius + 18.0, 20,
			Color(1.0, 1.0, 1.0, 0.86) if strength > 0.5 else Color(MUTED, 0.9))
	else:
		_text_centered(clock_text, center.x, center.y + radius + 18.0, 20,
			Color(1.0, 1.0, 1.0, 0.86) if strength > 0.5 else Color(MUTED, 0.9))


func _draw_speed_buttons(vp: Vector2) -> void:
	var labels := ["1x", "2x", "3x"]
	var size := Vector2(84.0, 72.0)
	var gap := 10.0
	var total := size.x * 3.0 + gap * 2.0
	var start := Vector2(vp.x - 400.0, vp.y - 104.0)
	# 暂停按钮放在倍速按钮左边；暂停期间仍可编辑线路/调动车厢
	_pause_rect = Rect2(start - Vector2(96.0, 0.0), size)
	# 设置按钮放在倍速按钮右边
	_settings_rect = Rect2(Vector2(vp.x - 116.0, vp.y - 104.0), size)
	var settings_center := _settings_rect.get_center()
	_draw_soft_shadow(_settings_rect, 12.0, 0.12, Vector2(0.0, 5.0))
	var settings_poly := DrawUtil.rounded_rect(_settings_rect, 12.0, 6)
	draw_colored_polygon(settings_poly, Color(1.0, 1.0, 1.0, 0.56))
	draw_polyline(DrawUtil.closed(settings_poly), Color(INK, 0.34), 1.4, true)
	draw_circle(settings_center, 15.0, Color(INK, 0.8), true, -1.0, true)
	draw_circle(settings_center, 6.0, Color(PAPER, 0.95), true, -1.0, true)
	for i in 8:
		var a := TAU * float(i) / 8.0
		draw_line(settings_center + Vector2(cos(a), sin(a)) * 17.0,
			settings_center + Vector2(cos(a), sin(a)) * 23.0, Color(INK, 0.8), 3.5, true)
	var mouse := get_global_mouse_position()
	var pause_hovered := _pause_rect.has_point(mouse)
	_draw_soft_shadow(_pause_rect, 12.0, 0.12, Vector2(0.0, 5.0))
	var pause_poly := DrawUtil.rounded_rect(_pause_rect, 12.0, 6)
	draw_colored_polygon(pause_poly,
		Color(ACCENT, 0.80) if paused else Color(1.0, 1.0, 1.0, 0.72 if pause_hovered else 0.52))
	draw_polyline(DrawUtil.closed(pause_poly), Color(ACCENT, 0.70) if paused else Color(INK, 0.34),
		1.4, true)
	var pc := _pause_rect.get_center()
	if paused:
		# 恢复播放：三角形
		var play := PackedVector2Array([
			pc + Vector2(-10.0, -16.0), pc + Vector2(18.0, 0.0), pc + Vector2(-10.0, 16.0),
		])
		draw_colored_polygon(play, Color(1.0, 1.0, 1.0, 0.95))
	else:
		# 暂停：两条竖线
		draw_rect(Rect2(pc + Vector2(-14.0, -16.0), Vector2(10.0, 32.0)), INK)
		draw_rect(Rect2(pc + Vector2(4.0, -16.0), Vector2(10.0, 32.0)), INK)
	_speed_rects = []
	for i in 3:
		var rect := Rect2(start + Vector2(float(i) * (size.x + gap), 0.0), size)
		_speed_rects.append(rect)
		var active := is_equal_approx(speed, float(i + 1))
		var hovered := rect.has_point(mouse)
		_draw_soft_shadow(rect, 12.0, 0.12, Vector2(0.0, 5.0))
		var poly := DrawUtil.rounded_rect(rect, 12.0, 6)
		if active:
			draw_colored_polygon(poly, Color(ACCENT, 0.88))
		else:
			draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.72 if hovered else 0.50))
		draw_polyline(DrawUtil.closed(poly),
			Color(ACCENT, 0.75) if active else Color(INK, 0.30), 1.4, true)
		_text_centered(String(labels[i]), rect.position.x + rect.size.x * 0.5,
			rect.position.y + 46.0, 26, Color(1.0, 1.0, 1.0, 0.95) if active else INK)


## 暂停按钮命中。
func pause_button_at(pos: Vector2) -> bool:
	return _pause_rect.has_point(pos)


## 设置按钮命中。
func settings_button_at(pos: Vector2) -> bool:
	return _settings_rect.has_point(pos)


## 点击倍速按钮：返回 1/2/3，0 = 没点中。
func speed_button_at(pos: Vector2) -> int:
	for i in _speed_rects.size():
		if _speed_rects[i].has_point(pos):
			return i + 1
	return 0


func _draw_resource_slots(vp: Vector2) -> void:
	var used := 0 if network == null else network.lines.size()
	var mouse := get_global_mouse_position()
	_text("资源 · 拖动图标到地图", Vector2(40.0, 60.0), 20, Color(INK, 0.65))
	# 线路颜色按钮：基础 62×34；商店不设上限后线路可能超过 10 条，宽度自动压缩
	var chip_y := 66.0
	var chip_h := 34.0
	var chip_gap := 8.0
	var line_count := maxi(level.start_lines, 1)
	var chip_w := minf(62.0, (700.0 - chip_gap * float(line_count - 1)) / float(line_count))
	chip_w = maxf(chip_w, 28.0)
	var chip_start_x := 40.0
	_line_chips = []
	for i in level.start_lines:
		var button := Rect2(Vector2(chip_start_x + float(i) * (chip_w + chip_gap), chip_y),
			Vector2(chip_w, chip_h))
		var capsule_w := clampf(chip_w - 20.0, 14.0, 40.0)
		if i < used:
			var line: MetroLine = network.lines[i]
			var hovered := button.has_point(mouse)
			var chip_poly := DrawUtil.rounded_rect(button, 9.0, 6)
			draw_colored_polygon(chip_poly, Color(1.0, 1.0, 1.0, 0.62 if hovered else 0.38))
			draw_polyline(DrawUtil.closed(chip_poly), Color(INK, 0.30), 1.2, true)
			_draw_capsule(Vector2(button.position.x + chip_w * 0.5 - 4.0, chip_y + chip_h * 0.5),
				line.color, capsule_w, 13.0)
			_text_centered("x", button.end.x - 12.0, chip_y + 24.0, 17, Color(INK, 0.62))
			# 放大后的点击区就是整只按钮
			_line_chips.append({"id": line.id, "rect": button})
		else:
			# 已拥有但尚未使用的线路：画出半透明空槽
			var empty_poly := DrawUtil.rounded_rect(button, 9.0, 6)
			draw_colored_polygon(empty_poly, Color(1.0, 1.0, 1.0, 0.16))
			draw_polyline(DrawUtil.closed(empty_poly), Color(INK, 0.16), 1.0, true)
			_draw_capsule_outline(
				Vector2(button.position.x + chip_w * 0.5 - 4.0, chip_y + chip_h * 0.5),
				Color(level.line_colors[i % level.line_colors.size()], 0.26), capsule_w, 13.0)
	# 显示“已用 / 总共拥有”的线路数量
	_text_right(Loc.t("线路 %d/%d", "Lines %d/%d") % [used, level.start_lines],
		740.0, chip_y + 23.0, 20, Color(INK, 0.70))

	# 第二行：可拖拽的资源卡片（列车 / 车厢 / 换乘中心 / 新干线）+ 桥梁余量
	var row_y := 226.0 if _mobile_ui else 140.0
	_stock_rects = {}
	var slots := [
		{"kind": "train", "x": 100.0, "label": Loc.t("列车", "Trains")},
		{"kind": "carriage", "x": 250.0, "label": Loc.t("车厢", "Cars")},
		{"kind": "interchange", "x": 400.0, "label": Loc.t("换乘", "Transfer")},
		{"kind": "express", "x": 550.0, "label": Loc.t("新干线", "Shinkansen")},
	]
	for slot in slots:
		var kind := String(slot["kind"])
		var center := Vector2(float(slot["x"]), row_y)
		var count := int(stock_counts.get(kind, 0))
		var card := Rect2(center - Vector2(60.0, 56.0 if _mobile_ui else 36.0),
			Vector2(120.0, 112.0 if _mobile_ui else 88.0))
		var hovered := card.has_point(mouse)
		_draw_soft_shadow(card, 12.0, 0.12 if hovered else 0.07, Vector2(0.0, 5.0))
		var card_poly := DrawUtil.rounded_rect(card, 14.0, 8)
		draw_colored_polygon(card_poly, Color(1.0, 1.0, 1.0, 0.88 if hovered else 0.58))
		draw_polyline(DrawUtil.closed(card_poly), Color(ACCENT, 0.38 if hovered else 0.16),
			1.8 if hovered else 1.2, true)
		_draw_stock_icon(kind, Vector2(center.x, row_y - 8.0), count > 0)
		_text("x%d" % count, Vector2(center.x + 24.0, row_y - 14.0), 24,
			Color(INK, 0.85) if count > 0 else Color(MUTED, 0.5))
		_text_centered(String(slot["label"]), center.x, row_y + 36.0, 18,
			Color(INK, 0.78) if count > 0 else Color(MUTED, 0.5))
		# 右上角拖动握把：提示这个卡片可以拖
		for dot in 3:
			draw_circle(Vector2(card.end.x - 16.0, card.position.y + 14.0 + dot * 5.0),
				1.7, Color(INK, 0.38), true, -1.0, true)
		_stock_rects[kind] = card

	# 桥梁不是库存，是预算：画桥图标 + 已用/上限
	var bridge_center := Vector2(690.0, row_y)
	var bridge_card := Rect2(bridge_center - Vector2(60.0, 56.0 if _mobile_ui else 36.0),
		Vector2(120.0, 112.0 if _mobile_ui else 88.0))
	_draw_soft_shadow(bridge_card, 12.0, 0.07, Vector2(0.0, 5.0))
	var bridge_poly := DrawUtil.rounded_rect(bridge_card, 14.0, 8)
	draw_colored_polygon(bridge_poly, Color(1.0, 1.0, 1.0, 0.46))
	draw_polyline(DrawUtil.closed(bridge_poly), Color(INK, 0.28), 1.4, true)
	_draw_stock_icon("bridge", Vector2(bridge_center.x, row_y - 8.0), true)
	var bridges := 0 if network == null else network.used_bridges()
	_text("%d/%d" % [bridges, level.start_bridges], Vector2(bridge_center.x + 16.0, row_y - 14.0),
		24, Color(INK, 0.75))
	_text_centered(Loc.t("桥梁", "Bridges"), bridge_center.x, row_y + 36.0, 18, Color(INK, 0.65))


## 左上角库存图标：列车 / 车厢 / 换乘中心 / 新干线 / 桥梁。
func _draw_stock_icon(kind: String, center: Vector2, enabled: bool) -> void:
	var ink := Color(INK, 0.9) if enabled else Color(MUTED, 0.45)
	var paper := Color(PAPER, 0.95) if enabled else Color(PAPER, 0.5)
	match kind:
		"train":
			_draw_capsule(center, paper, 42.0, 21.0)
			_draw_capsule_outline(center, ink, 42.0, 21.0)
			draw_rect(Rect2(center + Vector2(7.0, -7.0), Vector2(11.0, 14.0)), Color(ink, 0.25))
			draw_rect(Rect2(center + Vector2(10.0, -4.0), Vector2(5.0, 8.0)), ink)
		"carriage":
			_draw_capsule(center, paper, 30.0, 19.0)
			_draw_capsule_outline(center, ink, 30.0, 19.0)
			draw_rect(Rect2(center + Vector2(-9.0, -4.0), Vector2(7.0, 8.0)), Color(ink, 0.28))
			draw_rect(Rect2(center + Vector2(2.0, -4.0), Vector2(7.0, 8.0)), Color(ink, 0.28))
		"interchange":
			draw_circle(center, 17.0, paper, true, -1.0, true)
			draw_arc(center, 17.0, 0.0, TAU, 32, ink, 2.8, true)
			draw_circle(center, 8.0, Color(ink, 0.18), true, -1.0, true)
			draw_arc(center, 8.0, 0.0, TAU, 24, ink, 2.2, true)
		"express":
			# 新干线：更长的胶囊 + 尖头 + 两道速度线
			_draw_capsule(center + Vector2(-3.0, 0.0), paper, 46.0, 18.0)
			_draw_capsule_outline(center + Vector2(-3.0, 0.0), ink, 46.0, 18.0)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(20.0, -9.0), center + Vector2(30.0, 0.0),
				center + Vector2(20.0, 9.0),
			]), paper)
			draw_polyline(DrawUtil.closed(PackedVector2Array([
				center + Vector2(20.0, -9.0), center + Vector2(30.0, 0.0),
				center + Vector2(20.0, 9.0),
			])), ink, 2.2, true)
			draw_line(center + Vector2(-20.0, -4.0), center + Vector2(6.0, -4.0),
				Color(1.0, 1.0, 1.0, 0.75), 2.0, true)
			draw_line(center + Vector2(-23.0, 4.0), center + Vector2(3.0, 4.0),
				Color(1.0, 1.0, 1.0, 0.55), 2.0, true)
		"bridge":
			draw_line(center + Vector2(-16.0, 8.0), center + Vector2(16.0, 8.0), ink, 3.2, true)
			draw_arc(center + Vector2(0.0, 8.0), 16.0, PI, TAU, 24, ink, 2.8, true)
			draw_line(center + Vector2(-11.0, 8.0), center + Vector2(-11.0, 15.0), ink, 2.6, true)
			draw_line(center + Vector2(11.0, 8.0), center + Vector2(11.0, 15.0), ink, 2.6, true)


## 点中了哪个库存图标："train" / "carriage" / "interchange" / ""。
func stock_icon_at(pos: Vector2) -> String:
	for kind in _stock_rects.keys():
		if (_stock_rects[kind] as Rect2).has_point(pos):
			return String(kind)
	return ""


## 库存图标中心（截图姿态 / 拖拽起点用）。
func stock_icon_center(kind: String) -> Vector2:
	if _stock_rects.has(kind):
		var rect: Rect2 = _stock_rects[kind]
		return rect.get_center()
	return Vector2(118.0, 146.0)


# ---------------------------------------------------------------------------
# 周抽卡 / 换乘站点选
# ---------------------------------------------------------------------------

func _draw_week(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.07, 0.08, 0.66))
	_draw_vignette(vp, 1.2)
	var title := reward_title if reward_title != "" else \
		Loc.t("第 %d 周 · 选择升级", "Week %d · Choose an upgrade") % week
	var cx := vp.x * 0.5
	_text_centered(title, cx + 2.0, vp.y * 0.5 - 166.0, 42, Color(0.0, 0.0, 0.0, 0.25))
	_text_centered(title, cx, vp.y * 0.5 - 168.0, 42, Color(1.0, 1.0, 1.0, 0.98))
	_draw_accent_rule(Vector2(cx, vp.y * 0.5 - 136.0), 120.0, GOLD)
	var extra := clampf((ui_text_scale - 1.0) / 0.28, 0.0, 1.0)
	_card_rects = _compute_card_rects(vp, week_cards.size(), 400.0 + 80.0 * extra,
		220.0 + 72.0 * extra, 44.0)
	var mouse := get_global_mouse_position()
	var accents := [GOLD, TEAL]
	for i in _card_rects.size():
		var base: Rect2 = _card_rects[i]
		var hovered := base.has_point(mouse)
		var rect := Rect2(base.position + Vector2(0.0, -6.0 if hovered else 0.0), base.size)
		_draw_soft_shadow(rect, 20.0, 0.32 if hovered else 0.16, Vector2(0.0, 12.0))
		var poly := DrawUtil.rounded_rect(rect, 20.0, 10)
		draw_colored_polygon(poly, Color("#FFFFFF") if hovered else PAPER)
		var accent: Color = accents[i % accents.size()]
		draw_rect(Rect2(rect.position + Vector2(24.0, 0.0), Vector2(rect.size.x - 48.0, 5.0)),
			Color(accent, 0.92))
		draw_polyline(DrawUtil.closed(poly), Color(accent, 0.36 if hovered else 0.18),
			2.0 if hovered else 1.4, true)
		if i < week_cards.size():
			var card: Dictionary = week_cards[i]
			_text_centered(String(card["title"]),
				rect.position.x + rect.size.x * 0.5, rect.position.y + 92.0, 34, INK)
			_text_wrapped(String(card["desc"]),
				rect.position.x + rect.size.x * 0.5, rect.position.y + 146.0, 21,
				rect.size.x - 48.0, MUTED)
		_text_centered(Loc.t("按 %d", "Press %d") % (i + 1),
			rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y - 24.0, 18,
			Color(MUTED, 0.8))
	_text_centered(Loc.t("点击卡片，或按 1 / 2", "Click a card, or press 1 / 2"),
		cx, vp.y * 0.5 + 178.0, 21, Color(1.0, 1.0, 1.0, 0.7))


# ---------------------------------------------------------------------------
# 模式选择 / 暂停设置
# ---------------------------------------------------------------------------

func tutorial_skip_at(pos: Vector2) -> bool:
	return tutorial_active and not tutorial_complete and not tutorial_forced \
		and _tutorial_skip_rect.has_point(pos)


func tutorial_start_at(pos: Vector2) -> bool:
	return tutorial_complete and _tutorial_start_rect.has_point(pos)


func tutorial_menu_at(pos: Vector2) -> bool:
	return tutorial_complete and _tutorial_menu_rect.has_point(pos)


func _draw_tutorial(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	# 先给目标站点画呼吸环，帮助玩家找到要拖拽的位置
	var canvas := get_viewport().get_canvas_transform()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	for world_pos in tutorial_highlights:
		var screen_pos: Vector2 = canvas * world_pos
		draw_arc(screen_pos, 42.0 + pulse * 7.0, 0.0, TAU, 48,
			Color(0.83, 0.32, 0.24, 0.28 + pulse * 0.25), 7.0, true)
		draw_arc(screen_pos, 42.0 + pulse * 7.0, 0.0, TAU, 48,
			Color(0.83, 0.32, 0.24, 0.85), 2.0, true)
	if tutorial_complete:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.09, 0.10, 0.60))
		var end_panel := Rect2(cx - 430.0,
			vp.y * 0.5 - (230.0 if _mobile_ui else 190.0), 860.0,
			460.0 if _mobile_ui else 380.0)
		_draw_soft_shadow(end_panel, 22.0, 0.40, Vector2(0.0, 16.0))
		var poly := DrawUtil.rounded_rect(end_panel, 22.0, 10)
		draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.99))
		draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.55), 1.6, true)
		draw_rect(Rect2(end_panel.position + Vector2(40.0, 0.0),
			Vector2(end_panel.size.x - 80.0, 5.0)), Color(GOLD, 0.9))
		_text_centered(Loc.t("教程完成", "Tutorial complete"), cx,
			end_panel.position.y + (82.0 if _mobile_ui else 72.0), 44, INK)
		_text_centered(Loc.t("你已经学会画线、拆站、环线、过河、换乘和升级。",
			"You can draw, remove stations, loop, bridge, transfer and upgrade."),
			cx, end_panel.position.y + (144.0 if _mobile_ui else 120.0), 23, MUTED)
		_text_centered(Loc.t("接下来试试经典模式，看看能送多少人？",
			"Now try Classic and see how many you can deliver."),
			cx, end_panel.position.y + (194.0 if _mobile_ui else 158.0), 21, Color(MUTED, 0.85))
		_tutorial_start_rect = Rect2(cx - 310.0,
			end_panel.position.y + (260.0 if _mobile_ui else 220.0), 290.0, 78.0)
		_tutorial_menu_rect = Rect2(cx + 20.0,
			end_panel.position.y + (260.0 if _mobile_ui else 220.0), 290.0, 78.0)
		_draw_touch_button(_tutorial_start_rect,
			Loc.t("开始经典模式", "Start Classic"), _tutorial_start_rect.has_point(get_global_mouse_position()))
		_draw_touch_button(_tutorial_menu_rect,
			Loc.t("返回模式选择", "Mode menu"), _tutorial_menu_rect.has_point(get_global_mouse_position()))
		return
	var panel := Rect2(cx - 430.0, 118.0, 860.0, 260.0 if _mobile_ui else 154.0)
	_draw_soft_shadow(panel, 16.0, 0.28, Vector2(0.0, 10.0))
	var panel_poly := DrawUtil.rounded_rect(panel, 16.0, 8)
	draw_colored_polygon(panel_poly, Color(0.99, 0.97, 0.92, 0.98))
	draw_polyline(DrawUtil.closed(panel_poly), Color(GOLD, 0.50), 1.5, true)
	# 左侧步骤色条 + 底部进度条
	draw_rect(Rect2(panel.position + Vector2(0.0, 16.0), Vector2(4.0, panel.size.y - 32.0)),
		Color(ACCENT, 0.85))
	var progress := clampf((float(tutorial_step) + 1.0) / float(maxi(tutorial_total, 1)), 0.0, 1.0)
	draw_rect(Rect2(panel.position + Vector2(20.0, panel.size.y - 7.0),
		Vector2(panel.size.x - 40.0, 2.5)), Color(INK, 0.10))
	draw_rect(Rect2(panel.position + Vector2(20.0, panel.size.y - 7.0),
		Vector2((panel.size.x - 40.0) * progress, 2.5)), Color(ACCENT, 0.9))
	_text(Loc.t("教程 %d/%d", "Tutorial %d/%d") % [tutorial_step + 1, tutorial_total],
		panel.position + Vector2(22.0, 42.0 if _mobile_ui else 30.0), 19,
		Color(0.83, 0.32, 0.24, 0.95))
	_text_centered(tutorial_title, cx, panel.position.y + (82.0 if _mobile_ui else 50.0), 27, INK)
	_text_centered(tutorial_body, cx, panel.position.y + (134.0 if _mobile_ui else 84.0), 21,
		Color(INK, 0.9))
	_text_centered(tutorial_hint, cx, panel.position.y + (186.0 if _mobile_ui else 118.0), 18,
		MUTED)
	_tutorial_skip_rect = Rect2() if tutorial_forced else Rect2(panel.end.x - 138.0,
		panel.position.y + (10.0 if _mobile_ui else 14.0),
		118.0, 54.0 if _mobile_ui else 40.0)
	if not tutorial_forced:
		var skip_poly := DrawUtil.rounded_rect(_tutorial_skip_rect, 9.0, 6)
		draw_colored_polygon(skip_poly, Color(1.0, 1.0, 1.0, 0.65))
		draw_polyline(DrawUtil.closed(skip_poly), Color(INK, 0.35), 1.2, true)
		_text_centered(Loc.t("跳过", "Skip"), _tutorial_skip_rect.get_center().x,
			_tutorial_skip_rect.get_center().y + 13.0, 18, Color(INK, 0.8))


func _draw_mode_menu(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.07, 0.085, 0.095, 0.72))
	_draw_vignette(vp, 1.2)
	_draw_menu_ambient(vp)
	var cx := vp.x * 0.5
	# 顶部标题带：像控制室的总站牌
	_text_centered(Loc.t("METRO CONTROL · 线路控制台", "METRO CONTROL ROOM"),
		cx, 76.0, 17, Color(0.96, 0.78, 0.52, 0.78))
	_text_tracked_centered("MINI METRO", cx + 2.0, 156.0, 62,
		Color(0.0, 0.0, 0.0, 0.30), 9.0)
	_text_tracked_centered("MINI METRO", cx, 154.0, 62,
		Color(1.0, 1.0, 1.0, 0.98), 9.0)
	_text_centered(Loc.t("极简地铁调度 · 三轴配置", "MINIMAL METRO · THREE AXES"),
		cx, 194.0, 20, Color(0.96, 0.78, 0.52, 0.90))
	_draw_accent_rule(Vector2(cx, 212.0), 180.0, GOLD)
	# 标题下方一条“总线路”，连接左侧城市、中央配置、右侧简报
	var header_route_y := 234.0
	draw_line(Vector2(80.0, header_route_y), Vector2(vp.x - 80.0, header_route_y),
		Color(0.93, 0.89, 0.78, 0.20), 2.0, true)
	for x in [330.0, cx, vp.x - 330.0]:
		draw_circle(Vector2(x, header_route_y), 4.0, Color(PAPER, 0.78), true, -1.0, true)
		draw_arc(Vector2(x, header_route_y), 4.0, 0.0, TAU, 20, Color(GOLD, 0.55), 1.4, true)
	_draw_city_selector(vp)
	_draw_config_panel(vp)
	_draw_dispatch_panel(vp)
	_draw_menu_bottom_bar(vp)
	if not _mobile_ui:
		_text_centered(Loc.t("←/→ 切换城市 · 1/2 资源 · 3/4 结束 · 5/6 开局 · Enter 发车 · T 教程",
			"←/→ city · 1/2 resources · 3/4 ending · 5/6 start · Enter depart · T tutorial"),
			cx, 1050.0, 19, Color(1.0, 1.0, 1.0, 0.62))


## 左侧城市卡：把城市预览从顶部移到主区域，填满左侧。
func _draw_city_selector(vp: Vector2) -> void:
	var card := Rect2(80.0, 258.0, 500.0, 612.0)
	_draw_soft_shadow(card, 20.0, 0.30, Vector2(0.0, 14.0))
	var card_poly := DrawUtil.rounded_rect(card, 20.0, 10)
	draw_colored_polygon(card_poly, Color(0.94, 0.91, 0.84, 0.97))
	draw_polyline(DrawUtil.closed(card_poly), Color(GOLD, 0.42), 1.5, true)
	draw_rect(Rect2(card.position + Vector2(26.0, 0.0), Vector2(card.size.x - 52.0, 5.0)),
		Color(GOLD, 0.88))
	var city: CityMap = null
	if not menu_cities.is_empty():
		city_index = clampi(city_index, 0, menu_cities.size() - 1)
		city = menu_cities[city_index]
	_text(Loc.t("城市 / CITY", "CITY MAP") if _mobile_ui else Loc.t("当前城市 / CITY", "CITY MAP"),
		card.position + Vector2(26.0, 38.0), 16, Color(MUTED, 0.85))
	if city != null:
		_text(city.display_name(), card.position + Vector2(26.0, 78.0), 34, INK)
		_text_right(Loc.t("%02d / %02d", "%02d / %02d") % [city_index + 1, menu_cities.size()],
			card.end.x - 26.0, card.position.y + 42.0, 15, Color(MUTED, 0.72))
	var preview := Rect2(card.position.x + 24.0, card.position.y + 102.0,
		card.size.x - 48.0, 300.0)
	_draw_city_preview(preview, city)
	_city_arrow_rects = [
		Rect2(preview.position.x + 8.0, preview.get_center().y - 30.0, 60.0, 60.0),
		Rect2(preview.end.x - 68.0, preview.get_center().y - 30.0, 60.0, 60.0),
	]
	var mouse := get_global_mouse_position()
	for i in 2:
		var arrow_rect: Rect2 = _city_arrow_rects[i]
		var hovered := arrow_rect.has_point(mouse)
		var center := arrow_rect.get_center()
		draw_circle(center, 24.0, Color(0.08, 0.09, 0.10, 0.72 if hovered else 0.50), true, -1.0, true)
		draw_arc(center, 24.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.55 if hovered else 0.28), 1.4, true)
		var sign := 1.0 if i == 0 else -1.0
		draw_polyline(PackedVector2Array([
			center + Vector2(sign * 6.0, -10.0),
			center + Vector2(sign * -5.0, 0.0),
			center + Vector2(sign * 6.0, 10.0),
		]), Color(1.0, 1.0, 1.0, 0.95 if hovered else 0.72), 2.8, true)
	# 城市摘要：初始资源 / 河道 / 城市数量
	draw_line(Vector2(card.position.x + 26.0, card.position.y + 430.0),
		Vector2(card.end.x - 26.0, card.position.y + 430.0), Color(INK, 0.10), 1.0, true)
	if city != null:
		_text(Loc.t("初始资源", "STARTING RESOURCES"),
			card.position + Vector2(26.0, 466.0 if _mobile_ui else 462.0),
			15, Color(MUTED, 0.82))
		_text(Loc.t("%d 线 · %d 列车 · %d 桥", "%d lines · %d trains · %d bridges") % [
			city.start_lines, city.start_trains, city.start_bridges,
		], card.position + Vector2(26.0, 514.0 if _mobile_ui else 490.0), 21, INK)
		_text(Loc.t("河道 %d 条 · 可左右切换", "Rivers %d · use arrows to switch") % city.rivers.size(),
			card.position + Vector2(26.0, 562.0 if _mobile_ui else 520.0), 17, Color(MUTED, 0.86))
	# 一侧的线路色票，填满卡片底部
	if not _mobile_ui:
		_text(Loc.t("线路色 / LINE COLORS", "LINE COLORS"), card.position + Vector2(26.0, 558.0),
			14, Color(MUTED, 0.72))
	for i in mini(level.line_colors.size() if level != null else 0, 8):
		var color: Color = level.line_colors[i]
		_draw_capsule(Vector2(card.position.x + 46.0 + float(i) * 50.0,
			card.position.y + (594.0 if _mobile_ui else 588.0)), color, 36.0, 12.0)


func daily_board_button_at(pos: Vector2) -> bool:
	return _daily_board_rect.has_point(pos)


func map_hall_button_at(pos: Vector2) -> bool:
	return _map_hall_rect.has_point(pos)


func map_rank_button_at(pos: Vector2) -> bool:
	return _map_rank_rect.has_point(pos)


func editor_button_at(pos: Vector2) -> bool:
	return _editor_button_rect.has_point(pos)


func show_leaderboard(title: String, subtitle: String, lines: Array[String]) -> void:
	leaderboard_open = true
	leaderboard_title = title
	leaderboard_subtitle = subtitle
	leaderboard_lines = lines.duplicate()
	_leaderboard_categories = []
	_leaderboard_category_index = 0
	map_hall_open = false
	queue_redraw()


## 按模式配置分类的地图排行榜。
func show_rank_leaderboard(title: String, subtitle: String,
		categories: Array[Dictionary], selected: int = 0) -> void:
	leaderboard_open = true
	leaderboard_title = title
	leaderboard_subtitle = subtitle
	_leaderboard_categories = categories.duplicate(true)
	_leaderboard_category_index = clampi(selected, 0, maxi(categories.size() - 1, 0))
	_sync_leaderboard_category_lines()
	map_hall_open = false
	queue_redraw()


func _sync_leaderboard_category_lines() -> void:
	if _leaderboard_categories.is_empty():
		leaderboard_lines = []
		return
	var category: Dictionary = _leaderboard_categories[_leaderboard_category_index]
	leaderboard_lines = []
	var lines: Array = category.get("lines", [])
	for line in lines:
		leaderboard_lines.append(String(line))


func leaderboard_category_at(pos: Vector2) -> int:
	for i in _leaderboard_category_rects.size():
		if _leaderboard_category_rects[i].has_point(pos):
			return i
	return -1


func select_leaderboard_category(index: int) -> void:
	if _leaderboard_categories.is_empty():
		return
	_leaderboard_category_index = clampi(index, 0, _leaderboard_categories.size() - 1)
	_sync_leaderboard_category_lines()
	queue_redraw()


func hide_leaderboard() -> void:
	leaderboard_open = false
	queue_redraw()


func show_map_hall(entries: Array) -> void:
	map_hall_open = true
	map_hall_entries = entries.duplicate(true)
	leaderboard_open = false
	queue_redraw()


func hide_map_hall() -> void:
	map_hall_open = false
	queue_redraw()


func map_hall_row_at(pos: Vector2) -> int:
	for i in _map_hall_row_rects.size():
		if _map_hall_row_rects[i].has_point(pos):
			return i
	return -1


func leaderboard_back_at(pos: Vector2) -> bool:
	return _leaderboard_back_rect.has_point(pos)


func map_hall_back_at(pos: Vector2) -> bool:
	return _map_hall_back_rect.has_point(pos)


## 左上角线路颜色条的命中：返回线路 id，-1 表示没点中。
func line_chip_at(pos: Vector2) -> int:
	for raw in _line_chips:
		if (raw["rect"] as Rect2).has_point(pos):
			return int(raw["id"])
	return -1


func show_line_cancel(id: int) -> void:
	line_cancel_id = id
	queue_redraw()


func hide_line_cancel() -> void:
	line_cancel_id = -1
	_line_cancel_rect = Rect2()
	queue_redraw()


func line_cancel_at(pos: Vector2) -> bool:
	return line_cancel_id >= 0 and _line_cancel_rect.has_point(pos)


func _draw_leaderboard(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.07, 0.08, 0.80))
	_draw_vignette(vp, 1.1)
	var mobile := _mobile_ui
	var has_categories := not _leaderboard_categories.is_empty()
	var content_lines := leaderboard_lines.size()
	var mobile_tab_rows := 2 if mobile and has_categories else 1
	var panel_height := (360.0 if has_categories else 260.0) + float(content_lines) * 40.0
	if mobile:
		panel_height = (300.0 if not has_categories else 300.0) \
			+ (float(mobile_tab_rows) * 64.0 if has_categories else 0.0) \
			+ float(content_lines) * 46.0
	var panel_size := Vector2(minf(1760.0, vp.x - 120.0), panel_height)
	panel_size.y = minf(panel_size.y, vp.y - 100.0)
	var panel := Rect2((vp - panel_size) * 0.5, panel_size)
	_draw_soft_shadow(panel, 22.0, 0.40, Vector2(0.0, 16.0))
	var poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.99))
	draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.42), 1.5, true)
	draw_rect(Rect2(panel.position + Vector2(32.0, 0.0), Vector2(panel.size.x - 64.0, 4.0)),
		Color(GOLD, 0.85))
	_text_centered(leaderboard_title, panel.position.x + panel.size.x * 0.5,
		panel.position.y + 62.0, 38, INK)
	var subtitle := leaderboard_subtitle
	if has_categories and _leaderboard_category_index < _leaderboard_categories.size():
		var category: Dictionary = _leaderboard_categories[_leaderboard_category_index]
		subtitle = "%s · %s" % [subtitle, String(category.get("metric", ""))]
	_text_centered(subtitle, panel.position.x + panel.size.x * 0.5,
		panel.position.y + 98.0, 21, MUTED)
	var content_y := panel.position.y + (138.0 if not mobile else 156.0)
	_leaderboard_category_rects = []
	if has_categories:
		var count := _leaderboard_categories.size()
		var tab_gap := 6.0
		if mobile:
			var cols := 4
			var row_gap := 8.0
			var tab_w := (panel.size.x - 96.0 - 8.0 * float(cols - 1)) / float(cols)
			for i in count:
				var row := i / cols
				var col := i % cols
				var tab := Rect2(panel.position.x + 48.0 + float(col) * (tab_w + 8.0),
					panel.position.y + 124.0 + float(row) * 64.0, tab_w, 56.0)
				_leaderboard_category_rects.append(tab)
				var selected := i == _leaderboard_category_index
				var hovered := tab.has_point(get_global_mouse_position())
				var tab_poly := DrawUtil.rounded_rect(tab, 10.0, 6)
				draw_colored_polygon(tab_poly, Color(GOLD, 0.20 if selected else
					(0.10 if hovered else 0.035)))
				draw_polyline(DrawUtil.closed(tab_poly),
					Color(GOLD, 0.60 if selected else 0.16), 1.2, true)
				var name := String((_leaderboard_categories[i] as Dictionary).get("title", "?"))
				_text_centered(name, tab.get_center().x, tab.position.y + 35.0, 15,
					Color(INK, 0.92 if selected else 0.55))
			content_y = panel.position.y + 124.0 + float(mobile_tab_rows) * 64.0 + 20.0
		else:
			var tab_w := (panel.size.x - 96.0 - tab_gap * float(count - 1)) / float(maxi(count, 1))
			var tab_start := panel.position.x + 48.0
			for i in count:
				var tab := Rect2(tab_start + float(i) * (tab_w + tab_gap),
					panel.position.y + 124.0, tab_w, 40.0)
				_leaderboard_category_rects.append(tab)
				var selected := i == _leaderboard_category_index
				var hovered := tab.has_point(get_global_mouse_position())
				var tab_poly := DrawUtil.rounded_rect(tab, 10.0, 6)
				draw_colored_polygon(tab_poly, Color(GOLD, 0.20 if selected else
					(0.10 if hovered else 0.035)))
				draw_polyline(DrawUtil.closed(tab_poly),
					Color(GOLD, 0.60 if selected else 0.16), 1.2, true)
				var name := String((_leaderboard_categories[i] as Dictionary).get("title", "?"))
				_text_centered(name, tab.get_center().x, tab.position.y + 27.0, 15,
					Color(INK, 0.92 if selected else 0.55))
			content_y = panel.position.y + 188.0
	var y := content_y
	for line in leaderboard_lines:
		_text(line, Vector2(panel.position.x + 70.0, y), 23, INK)
		y += 46.0 if mobile else 38.0
		if y > panel.end.y - 110.0:
			break
	_leaderboard_back_rect = Rect2(Vector2(panel.position.x + panel.size.x * 0.5 - 160.0,
		panel.end.y - 96.0), Vector2(320.0, 80.0))
	_draw_touch_button(_leaderboard_back_rect, Loc.t("返回", "Back"),
		_leaderboard_back_rect.has_point(get_global_mouse_position()))


func _draw_line_cancel(vp: Vector2) -> void:
	var line: MetroLine = null
	if network != null:
		line = network.line_by_id(line_cancel_id)
	if line == null:
		return
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.07, 0.08, 0.62))
	var panel := Rect2(vp.x * 0.5 - 320.0, vp.y * 0.5 - 210.0, 640.0, 420.0)
	_draw_soft_shadow(panel, 22.0, 0.38, Vector2(0.0, 16.0))
	var poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.99))
	draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.48), 1.5, true)
	draw_rect(Rect2(panel.position + Vector2(28.0, 0.0), Vector2(panel.size.x - 56.0, 4.0)),
		Color(GOLD, 0.85))
	_draw_capsule(Vector2(vp.x * 0.5, panel.position.y + 70.0), line.color, 150.0, 26.0)
	_text_centered(Loc.t("取消整条线路？", "Cancel this line?"), vp.x * 0.5,
		panel.position.y + 132.0, 38, INK)
	_text_centered(Loc.t("线路上的列车和车厢会退回库存", "Trains and carriages return to inventory"),
		vp.x * 0.5, panel.position.y + 172.0, 22, MUTED)
	_line_cancel_rect = Rect2(Vector2(vp.x * 0.5 - 72.0, panel.position.y + 200.0),
		Vector2(144.0, 144.0))
	var center := _line_cancel_rect.get_center()
	var hovered := _line_cancel_rect.has_point(get_global_mouse_position())
	draw_circle(center, 70.0, Color(0.86, 0.28, 0.26, 0.94 if hovered else 0.82), true, -1.0, true)
	draw_polyline(PackedVector2Array([
		center + Vector2(-26.0, -26.0), center + Vector2(26.0, 26.0),
	]), Color.WHITE, 11.0, true)
	draw_polyline(PackedVector2Array([
		center + Vector2(26.0, -26.0), center + Vector2(-26.0, 26.0),
	]), Color.WHITE, 11.0, true)
	_text_centered(Loc.t("点击 x 确认 · 点其他位置关闭",
		"Tap x to confirm · tap elsewhere to close"),
		vp.x * 0.5, panel.end.y - 26.0, 20, MUTED)


func _draw_name_modal(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.09, 0.10, 0.62))
	var panel := Rect2(vp.x * 0.5 - 350.0, vp.y * 0.5 - 140.0, 700.0, 250.0)
	var poly := DrawUtil.rounded_rect(panel, 20.0, 10)
	draw_colored_polygon(poly, Color(0.12, 0.12, 0.13, 0.96))
	draw_polyline(DrawUtil.closed(poly), Color(1.0, 1.0, 1.0, 0.18), 2.0, true)
	_text_centered(Loc.t("先给自己取名", "Choose your name") if name_edit_required
		else Loc.t("玩家名", "Player name"), vp.x * 0.5,
		vp.y * 0.5 - 98.0, 36, Color(1.0, 1.0, 1.0, 0.96))
	_text_centered(Loc.t("输入后按 Enter 保存 · Esc 取消", "Enter to save · Esc to cancel")
		if not name_edit_required else
		Loc.t("名字不能为空", "Name cannot be empty") if name_edit_error else
		Loc.t("必须填写名字，随后进入新手教程", "Required · the tutorial starts next"),
		vp.x * 0.5, vp.y * 0.5 + (90.0 if _mobile_ui else 70.0), 20,
		Color(1.0, 0.55, 0.48, 0.92) if name_edit_error else Color(1.0, 1.0, 1.0, 0.58))


func _draw_map_hall_preview(entry: Dictionary, rect: Rect2) -> void:
	var city := CustomMapStore.to_city_map(entry)
	var border := DrawUtil.rounded_rect(rect, 8.0, 6)
	draw_colored_polygon(border, Color("#F3EFE6"))
	var inner := rect.grow(-2.0)
	draw_rect(inner, Color("#F3EFE6"))
	if city.rivers.is_empty():
		_text_centered("-", rect.get_center().x, rect.get_center().y + 6.0, 22, MUTED)
	else:
		var world := Vector2(2400.0, 1200.0)
		var scale := minf(inner.size.x / world.x, inner.size.y / world.y)
		var offset := inner.get_center() - world * scale * 0.5
		for river in city.rivers:
			var points := PackedVector2Array()
			for point in river:
				points.append(offset + point * scale)
			if points.size() >= 3:
				if Geometry2D.triangulate_polygon(points).is_empty():
					# 有些玩家上传的河道是窄条/自交多边形，退化成描边，避免预览空白
					draw_polyline(DrawUtil.closed(points), WATER, 2.5, true)
				else:
					draw_colored_polygon(points, WATER)
	draw_polyline(DrawUtil.closed(border), Color(0.55, 0.52, 0.47, 0.7), 1.5, true)


func _draw_map_hall(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.07, 0.08, 0.80))
	_draw_vignette(vp, 1.1)
	var mobile := _mobile_ui
	var panel_size := Vector2(minf(1760.0, vp.x - 120.0),
		(300.0 + float(map_hall_entries.size()) * 124.0) if mobile
		else (260.0 + float(map_hall_entries.size()) * 96.0))
	panel_size.y = minf(panel_size.y, vp.y - 100.0)
	var panel := Rect2((vp - panel_size) * 0.5, panel_size)
	_draw_soft_shadow(panel, 22.0, 0.40, Vector2(0.0, 16.0))
	var poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.99))
	draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.42), 1.5, true)
	draw_rect(Rect2(panel.position + Vector2(32.0, 0.0), Vector2(panel.size.x - 64.0, 4.0)),
		Color(GOLD, 0.85))
	_text_centered(Loc.t("地图大厅", "Map Hall"), panel.position.x + panel.size.x * 0.5,
		panel.position.y + 64.0, 40, INK)
	_text_centered(Loc.t("点击地图行即可下载到本地，随后会出现在城市列表",
		"Click a map row to download it; it appears in the city list"),
		panel.position.x + panel.size.x * 0.5, panel.position.y + 104.0, 21, MUTED)
	_map_hall_row_rects = []
	var y := panel.position.y + (160.0 if mobile else 140.0)
	var row_w := panel.size.x - 120.0
	var mouse := get_global_mouse_position()
	for i in map_hall_entries.size():
		var entry: Dictionary = map_hall_entries[i]
		var row := Rect2(panel.position.x + 60.0, y, row_w, 112.0 if mobile else 84.0)
		_map_hall_row_rects.append(row)
		var hovered := row.has_point(mouse)
		var row_poly := DrawUtil.rounded_rect(row, 12.0, 6)
		draw_colored_polygon(row_poly, Color(INK, 0.06 if hovered else 0.03))
		draw_polyline(DrawUtil.closed(row_poly), Color(0.72, 0.69, 0.62), 1.2, true)
		var preview := Rect2(row.position + Vector2(12.0, 10.0 if mobile else 8.0),
			Vector2(180.0, 92.0) if mobile else Vector2(150.0, 68.0))
		_draw_map_hall_preview(entry, preview)
		_text(String(entry.get("name_zh", entry.get("name_en", "未命名"))),
			row.position + Vector2(200.0 if mobile else 180.0, 48.0 if mobile else 36.0),
			28, INK)
		_text(Loc.t("作者 %s · 下载 %d", "by %s · %d downloads") % [
			String(entry.get("author", "?")), int(entry.get("downloads", 0)),
		], row.position + Vector2(200.0 if mobile else 180.0, 94.0 if mobile else 66.0),
			20, MUTED)
		_text_centered(Loc.t("下载", "Download"), row.end.x - 100.0,
			row.position.y + (68.0 if mobile else 50.0), 26, Color(INK, 0.8))
		y += 124.0 if mobile else 96.0
		if y > panel.end.y - 110.0:
			break
	_map_hall_back_rect = Rect2(Vector2(panel.position.x + panel.size.x * 0.5 - 160.0,
		panel.end.y - 96.0), Vector2(320.0, 80.0))
	_draw_touch_button(_map_hall_back_rect, Loc.t("返回", "Back"),
		_map_hall_back_rect.has_point(get_global_mouse_position()))


## 城市预览卡（具体布局由菜单里的 _draw_city_selector 负责）。
func _draw_city_preview(rect: Rect2, city: CityMap) -> void:
	_draw_soft_shadow(rect, 14.0, 0.34, Vector2(0.0, 12.0))
	# 预览边缘的暖色光晕
	draw_arc(rect.get_center(), rect.size.x * 0.56, 0.0, TAU, 64,
		Color(GOLD, 0.035), 26.0, true)
	var border := DrawUtil.rounded_rect(rect, 14.0, 8)
	draw_colored_polygon(border, WATER)
	var inner := rect.grow(-8.0)
	var land := DrawUtil.rounded_rect(inner, 8.0, 8)
	draw_colored_polygon(land, Color("#F3EFE6"))
	if city != null:
		var world_min := Vector2(-60, -60)
		var world_span := Vector2(CityMaps.WORLD_SIZE.x + 120.0, CityMaps.WORLD_SIZE.y + 120.0)
		for river in city.rivers:
			var points := PackedVector2Array()
			for point in river:
				var uv := (point - world_min) / world_span
				points.append(rect.position + uv * rect.size)
			draw_colored_polygon(points, WATER)
	# 预览里也铺三条游戏内线路，让它不是一张静态地图缩略图
	_draw_city_schematic(inner)
	# 内侧细线 + 外框，像一张装裱好的地图卡
	var inner_poly := DrawUtil.rounded_rect(inner, 8.0, 6)
	draw_polyline(DrawUtil.closed(inner_poly), Color(1.0, 1.0, 1.0, 0.28), 1.2, true)
	draw_polyline(DrawUtil.closed(border), Color(GOLD, 0.55), 2.0, true)


func _draw_city_schematic(rect: Rect2) -> void:
	var routes := [
		{
			"color": ACCENT,
			"points": [Vector2(0.10, 0.72), Vector2(0.34, 0.72), Vector2(0.45, 0.53),
				Vector2(0.64, 0.53), Vector2(0.76, 0.70), Vector2(0.91, 0.70)],
		},
		{
			"color": TEAL,
			"points": [Vector2(0.22, 0.25), Vector2(0.22, 0.46), Vector2(0.36, 0.60),
				Vector2(0.58, 0.60), Vector2(0.58, 0.82)],
		},
		{
			"color": GOLD,
			"points": [Vector2(0.72, 0.27), Vector2(0.72, 0.43), Vector2(0.88, 0.43)],
		},
	]
	var first_points := PackedVector2Array()
	for route_index in routes.size():
		var route: Dictionary = routes[route_index]
		var color: Color = route["color"]
		var normalized: Array = route["points"]
		var points := PackedVector2Array()
		for point in normalized:
			var uv: Vector2 = point
			points.append(rect.position + Vector2(uv.x * rect.size.x, uv.y * rect.size.y))
		draw_polyline(points, Color(color, 0.18), 9.0, true)
		draw_polyline(points, Color(color, 0.78), 3.2, true)
		for point in points:
			draw_circle(point, 4.2, Color(PAPER, 0.98), true, -1.0, true)
			draw_arc(point, 4.2, 0.0, TAU, 20, Color(color, 0.9), 1.8, true)
		if route_index == 0:
			first_points = points
	# 预览线路上的小车，缓慢往返，作为菜单里的“活的”游戏元素
	if first_points.size() >= 2:
		var total := 0.0
		for i in range(first_points.size() - 1):
			total += first_points[i].distance_to(first_points[i + 1])
		if total > 1.0:
			var phase := fmod(Time.get_ticks_msec() / 7200.0, 2.0)
			var progress := phase if phase <= 1.0 else 2.0 - phase
			var target := total * progress
			var walked := 0.0
			for i in range(first_points.size() - 1):
				var a := first_points[i]
				var b := first_points[i + 1]
				var segment := a.distance_to(b)
				if walked + segment >= target and segment > 0.01:
					var local := (target - walked) / segment
					var head := a.lerp(b, local)
					var angle := (b - a).angle()
					draw_set_transform(head, angle)
					_draw_capsule(Vector2.ZERO, Color(PAPER, 0.98), 24.0, 12.0)
					_draw_capsule(Vector2.ZERO, Color(ACCENT, 0.98), 19.0, 8.0)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					break
				walked += segment


func _draw_config_panel(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	var mouse := get_global_mouse_position()
	var mobile := _mobile_ui
	_menu_base_rects = []
	_menu_endless_rects = []
	_menu_manager_rects = []
	var panel := Rect2(608.0, 258.0, 1184.0, 612.0)
	_draw_soft_shadow(panel, 20.0, 0.34, Vector2(0.0, 16.0))
	var panel_poly := DrawUtil.rounded_rect(panel, 20.0, 10)
	draw_colored_polygon(panel_poly, Color(0.05, 0.065, 0.075, 0.68))
	draw_polyline(DrawUtil.closed(panel_poly), Color(1.0, 1.0, 1.0, 0.12), 1.4, true)
	draw_rect(Rect2(panel.position + Vector2(26.0, 0.0), Vector2(panel.size.x - 52.0, 5.0)),
		Color(1.0, 1.0, 1.0, 0.16))
	if not mobile:
		_text(Loc.t("运营配置 / BUILD", "BUILD / THREE AXES"),
			panel.position + Vector2(28.0, 48.0), 17, Color(GOLD, 0.82))
		_text(Loc.t("三条线路决定本局规则", "Three lines define this run"),
			panel.position + Vector2(28.0, 78.0), 26, Color(1.0, 1.0, 1.0, 0.92))
	else:
		_text(Loc.t("三条线路决定本局规则", "Three lines define this run"),
			panel.position + Vector2(28.0, 62.0), 26, Color(1.0, 1.0, 1.0, 0.92))
	draw_line(Vector2(panel.position.x + 28.0, panel.position.y + (96.0 if not mobile else 84.0)),
		Vector2(panel.end.x - 28.0, panel.position.y + (96.0 if not mobile else 84.0)),
		Color(1.0, 1.0, 1.0, 0.08), 1.0, true)
	var rows := [
		{
			"label": Loc.t("资源获取", "RESOURCES"),
			"options": [Loc.t("经典", "Classic"), Loc.t("发展", "Development")],
			"selected": 0 if menu_config.base == "classic" else 1,
			"desc": Loc.t("周奖励 · 抽卡升级", "Weekly cards · upgrades")
				if menu_config.base == "classic" else
				Loc.t("金币 · 商店购买", "Coins · resource shop"),
			"accent": ACCENT if menu_config.base == "classic" else GOLD,
		},
		{
			"label": Loc.t("结束 / 评价", "END / METRIC"),
			"options": [Loc.t("无", "None"), Loc.t("无尽", "Endless")],
			"selected": 1 if menu_config.endless else 0,
			"desc": Loc.t("拥堵会结束 · 计送达", "Overload ends · delivered")
				if not menu_config.endless else
				Loc.t("不判负 · 30秒统计", "No fail · 30s metric"),
			"accent": TEAL if not menu_config.endless else GOLD,
		},
		{
			"label": Loc.t("开局条件", "START"),
			"options": [Loc.t("无", "None"), Loc.t("管理", "Manager")],
			"selected": 1 if menu_config.manager else 0,
			"desc": Loc.t("城市逐步发展", "Normal city growth")
				if not menu_config.manager else
				Loc.t("40 站 · 7 线 · 5 隧道", "40 stations · fixed sandbox"),
			"accent": Color("#6F7C86") if not menu_config.manager else Color("#B26A2F"),
		},
	]
	for row_index in 3:
		var row: Dictionary = rows[row_index]
		var y := panel.position.y + (118.0 if not mobile else 110.0) \
			+ float(row_index) * (80.0 if not mobile else 88.0)
		var accent: Color = row["accent"]
		draw_circle(Vector2(cx - 574.0, y + 25.0), 5.0, accent, true, -1.0, true)
		draw_line(Vector2(cx - 574.0, y + 25.0), Vector2(cx - 562.0, y + 25.0),
			Color(accent, 0.45), 2.0, true)
		_text(String(row["label"]), Vector2(cx - 552.0, y + 31.0), 22,
			Color(1.0, 1.0, 1.0, 0.76))
		if not mobile:
			_text(String(row["desc"]), Vector2(cx + 255.0, y + 31.0), 17,
				Color(1.0, 1.0, 1.0, 0.48))
		var options: Array = row["options"]
		var selected := int(row["selected"])
		var rects: Array[Rect2] = []
		var centers: Array[Vector2] = []
		for option_index in 2:
			var option_rect := Rect2(cx - 300.0 + float(option_index) * 262.0,
				y, 250.0, 52.0 if not mobile else 82.0)
			rects.append(option_rect)
			centers.append(Vector2(option_rect.get_center().x, y + 14.0))
		draw_line(centers[0], centers[1], Color(accent, 0.48), 4.0, true)
		draw_line(centers[0], centers[1], Color(1.0, 1.0, 1.0, 0.20), 1.2, true)
		for option_index in 2:
			var option_rect: Rect2 = rects[option_index]
			var station: Vector2 = centers[option_index]
			var hovered := option_rect.has_point(mouse)
			var chosen := option_index == selected
			if chosen:
				var highlight := DrawUtil.rounded_rect(
					Rect2(option_rect.position.x + 46.0, y - 2.0, 158.0,
						56.0 if not mobile else 84.0), 28.0, 8)
				draw_colored_polygon(highlight, Color(accent, 0.10))
			draw_circle(station, 17.0 if chosen or hovered else 13.0,
				Color(accent, 0.16 if chosen or hovered else 0.07), true, -1.0, true)
			draw_circle(station, 9.0 if chosen else 8.0, Color(PAPER, 0.98), true, -1.0, true)
			draw_arc(station, 9.0 if chosen else 8.0, 0.0, TAU, 32,
				Color(accent, 0.95 if chosen else 0.55), 3.2 if chosen else 2.2, true)
			if chosen:
				draw_circle(station, 3.6, accent, true, -1.0, true)
			_text_centered(String(options[option_index]), option_rect.get_center().x,
				y + (44.0 if not mobile else 70.0), 22,
				Color(1.0, 1.0, 1.0, 0.98 if chosen else (0.80 if hovered else 0.62)))
		match row_index:
			0:
				_menu_base_rects = rects
			1:
				_menu_endless_rects = rects
			2:
				_menu_manager_rects = rects
		if row_index < 2:
			draw_line(Vector2(panel.position.x + 26.0, y + (64.0 if not mobile else 82.0)),
				Vector2(panel.end.x - 26.0, y + (64.0 if not mobile else 82.0)),
				Color(1.0, 1.0, 1.0, 0.055), 1.0, true)

	var config_summary := "%s · %s · %s" % [
		menu_config.resource_title(),
		Loc.t("无尽", "Endless") if menu_config.endless else Loc.t("无", "None"),
		Loc.t("管理", "Manager") if menu_config.manager else Loc.t("无", "None"),
	]
	_text_centered(Loc.t("配置：%s", "Build: %s") % config_summary,
		cx - 170.0 if not mobile else cx - 190.0,
		panel.position.y + (382.0 if not mobile else 424.0), 21,
		Color(1.0, 1.0, 1.0, 0.80))
	_text_centered(Loc.t("评价：%s · 最高 %d", "Metric: %s · Best %d") % [
		menu_config.metric_label(), menu_best,
	], (cx + 292.0) if not mobile else (cx + 250.0),
		panel.position.y + (382.0 if not mobile else 424.0), 19, Color(GOLD, 0.86))
	_menu_start_rect = Rect2(cx - 210.0,
		panel.position.y + (414.0 if not mobile else 450.0), 420.0, 104.0)
	_draw_departure_button(_menu_start_rect, Loc.t("发车", "DEPART"),
		_menu_start_rect.has_point(mouse))
	if not mobile:
		_text_centered(Loc.t("每日挑战与新手教程固定使用经典规则", "Daily & tutorial always use classic rules"),
			cx, panel.position.y + 570.0, 17, Color(1.0, 1.0, 1.0, 0.46))


## 右侧运营简报：把当前配置、评价指标、最高分和规则说明集中起来。
func _draw_dispatch_panel(vp: Vector2) -> void:
	var card := Rect2(1820.0, 258.0, 500.0, 612.0)
	_draw_soft_shadow(card, 20.0, 0.30, Vector2(0.0, 14.0))
	var poly := DrawUtil.rounded_rect(card, 20.0, 10)
	draw_colored_polygon(poly, Color(0.97, 0.94, 0.88, 0.98))
	draw_polyline(DrawUtil.closed(poly), Color(GOLD, 0.45), 1.5, true)
	draw_rect(Rect2(card.position + Vector2(26.0, 0.0), Vector2(card.size.x - 52.0, 5.0)),
		Color(GOLD, 0.88))
	if _mobile_ui:
		_text(menu_config.resource_title(), card.position + Vector2(24.0, 66.0), 34, INK)
		_text_right(Loc.t("本配置最高 %d", "BEST %d") % menu_best,
			card.end.x - 24.0, card.position.y + 108.0, 17, Color(MUTED, 0.82))
		var mobile_rows := [
			Loc.t("资源  %s", "RES  %s") % (Loc.t("经典·周奖励", "Classic·weekly")
				if menu_config.base == "classic" else Loc.t("发展·金币店", "Dev·shop")),
			Loc.t("结束  %s", "END  %s") % (Loc.t("无尽·不判负", "Endless·no fail")
				if menu_config.endless else Loc.t("普通·会结束", "Normal·ends")),
			Loc.t("开局  %s", "START  %s") % (Loc.t("管理·沙盘", "Manager·sandbox")
				if menu_config.manager else Loc.t("普通·城市", "Normal·city")),
			Loc.t("评价  %s", "METRIC  %s") % menu_config.metric_label(),
		]
		var mobile_y := card.position.y + 166.0
		for row_text in mobile_rows:
			_text(String(row_text), Vector2(card.position.x + 24.0, mobile_y), 20, INK)
			mobile_y += 64.0
		for i in mini(level.line_colors.size() if level != null else 0, 7):
			_draw_capsule(Vector2(card.position.x + 36.0 + float(i) * 62.0,
				card.end.y - 24.0), level.line_colors[i], 44.0, 12.0)
		return
	_text(Loc.t("运营简报 / DISPATCH", "DISPATCH"), card.position + Vector2(24.0, 40.0),
		16, Color(MUTED, 0.85))
	_text(menu_config.resource_title(), card.position + Vector2(24.0, 82.0), 34, INK)
	_text_right(Loc.t("本配置最高 %d", "BEST %d") % menu_best,
		card.end.x - 24.0, card.position.y + 56.0, 17, Color(MUTED, 0.82))
	draw_line(Vector2(card.position.x + 24.0, card.position.y + 102.0),
		Vector2(card.end.x - 24.0, card.position.y + 102.0), Color(INK, 0.10), 1.0, true)
	var rows := [
		{Loc.t("资源获取", "RESOURCES"): Loc.t("经典 · 周奖励", "Classic · weekly") if menu_config.base == "classic" else Loc.t("发展 · 金币商店", "Development · shop")},
		{Loc.t("结束条件", "END"): Loc.t("无尽 · 不判负", "Endless · no fail") if menu_config.endless else Loc.t("普通 · 拥堵会结束", "Normal · overload ends")},
		{Loc.t("开局条件", "START"): Loc.t("管理 · 40 站沙盘", "Manager · 40-station sandbox") if menu_config.manager else Loc.t("普通 · 城市逐步发展", "Normal · growing city")},
		{Loc.t("评价指标", "METRIC"): menu_config.metric_label()},
	]
	var y := card.position.y + 138.0
	for row in rows:
		for key in row.keys():
			_text(String(key), Vector2(card.position.x + 24.0, y), 16, Color(MUTED, 0.80))
			_text(String(row[key]), Vector2(card.position.x + 24.0, y + 24.0), 21, INK)
		y += 64.0
	# 本局资源规则
	var rule_rect := Rect2(card.position.x + 24.0, card.position.y + 392.0,
		card.size.x - 48.0, 74.0)
	var rule_poly := DrawUtil.rounded_rect(rule_rect, 13.0, 8)
	draw_colored_polygon(rule_poly, Color(ACCENT if menu_config.is_development() else GOLD, 0.09))
	_text(Loc.t("本局资源规则", "RUN ECONOMY"), rule_rect.position + Vector2(14.0, 22.0),
		14, Color(MUTED, 0.85))
	var economy := Loc.t("周奖励抽卡", "Weekly upgrade cards") if not menu_config.is_development() \
		else Loc.t("送达赚金币 · 商店购买", "Earn coins · buy in shop")
	_text(economy, rule_rect.position + Vector2(14.0, 48.0), 19, INK)
	# 快捷键速查
	var hint_y := card.position.y + 506.0
	_text(Loc.t("操作速查", "KEY GUIDE"), Vector2(card.position.x + 24.0, hint_y - 26.0),
		14, Color(MUTED, 0.72))
	_text(Loc.t("1/2 资源   3/4 结束   5/6 开局", "1/2 resource   3/4 ending   5/6 start"),
		Vector2(card.position.x + 24.0, hint_y), 16, Color(INK, 0.72))
	_text(Loc.t("Enter 发车   T 教程    B 商店", "Enter depart   T tutorial   B shop"),
		Vector2(card.position.x + 24.0, hint_y + 26.0), 16, Color(INK, 0.72))
	_text(Loc.t("每日挑战 / 新手教程固定经典", "Daily & tutorial: classic rules"),
		Vector2(card.position.x + 24.0, hint_y + 54.0), 15, Color(MUTED, 0.75))
	# 底部线路色票
	for i in mini(level.line_colors.size() if level != null else 0, 7):
		_draw_capsule(Vector2(card.position.x + 36.0 + float(i) * 62.0,
			card.end.y - 24.0), level.line_colors[i], 44.0, 12.0)


## 底部命令条：每日挑战、教程、地图/排行榜入口，全部铺满宽度。
func _draw_menu_bottom_bar(vp: Vector2) -> void:
	var bar := Rect2(80.0, 896.0, vp.x - 160.0, 112.0)
	_draw_soft_shadow(bar, 18.0, 0.26, Vector2(0.0, 9.0))
	var poly := DrawUtil.rounded_rect(bar, 18.0, 10)
	draw_colored_polygon(poly, Color(0.05, 0.065, 0.075, 0.72))
	draw_polyline(DrawUtil.closed(poly), Color(1.0, 1.0, 1.0, 0.12), 1.2, true)
	var mouse := get_global_mouse_position()
	_daily_card_rect = Rect2(bar.position.x + 20.0, bar.position.y + 16.0, 286.0, 80.0)
	_tutorial_card_rect = Rect2(bar.position.x + 322.0, bar.position.y + 16.0, 286.0, 80.0)
	_draw_quick_config_card(_daily_card_rect, Loc.t("每日挑战", "Daily Challenge"),
		Loc.t("经典规则 · 每天 1 次", "Classic rules · 1/day"), GOLD,
		_daily_card_rect.has_point(mouse), false)
	_draw_quick_config_card(_tutorial_card_rect, Loc.t("新手教程", "Tutorial"),
		Loc.t("经典规则 · 12 步", "Classic rules · 12 steps"), TEAL,
		_tutorial_card_rect.has_point(mouse), true)
	# 中间用一条迷你线路连接三个入口语境
	var route_y := bar.position.y + 56.0
	var route_left := bar.position.x + 670.0
	var route_right := bar.position.x + 1190.0
	draw_line(Vector2(route_left, route_y), Vector2(route_right, route_y),
		Color(0.93, 0.89, 0.78, 0.20), 2.0, true)
	for x in [route_left, (route_left + route_right) * 0.5, route_right]:
		draw_circle(Vector2(x, route_y), 4.0, Color(PAPER, 0.70), true, -1.0, true)
		draw_arc(Vector2(x, route_y), 4.0, 0.0, TAU, 20, Color(GOLD, 0.55), 1.2, true)
	if not _mobile_ui:
		_text_centered(Loc.t("8 种组合 · 自由配置", "8 builds · configure freely"),
			(route_left + route_right) * 0.5, route_y - 14.0, 16, Color(1.0, 1.0, 1.0, 0.48))
	var menu_buttons := [
		{"text": Loc.t("每日排行榜", "Daily board"), "action": "daily"},
		{"text": Loc.t("地图大厅", "Map hall"), "action": "hall"},
		{"text": Loc.t("地图排行榜", "Map ranks"), "action": "rank"},
		{"text": Loc.t("地图编辑器", "Map editor"), "action": "editor"},
	]
	var button_w := 240.0
	var button_gap := 12.0
	var total_w := button_w * 4.0 + button_gap * 3.0
	var start_x := bar.end.x - 20.0 - total_w
	for i in menu_buttons.size():
		var rect := Rect2(Vector2(start_x + float(i) * (button_w + button_gap),
			bar.position.y + 16.0), Vector2(button_w, 80.0))
		match String(menu_buttons[i]["action"]):
			"daily": _daily_board_rect = rect
			"hall": _map_hall_rect = rect
			"rank": _map_rank_rect = rect
			"editor": _editor_button_rect = rect
		_draw_touch_button(rect, String(menu_buttons[i]["text"]), rect.has_point(mouse))


func _draw_quick_config_card(rect: Rect2, title: String, desc: String, accent: Color,
		hovered: bool, square_station: bool = false) -> void:
	_draw_soft_shadow(rect, 14.0, 0.18 if hovered else 0.10, Vector2(0.0, 7.0))
	var poly := DrawUtil.rounded_rect(rect, 15.0, 8)
	draw_colored_polygon(poly, Color(0.07, 0.08, 0.09, 0.72 if hovered else 0.50))
	draw_polyline(DrawUtil.closed(poly), Color(accent, 0.55 if hovered else 0.28), 1.5, true)
	var station := Vector2(rect.position.x + 26.0, rect.position.y + 34.0)
	if square_station:
		var pts := PackedVector2Array([
			station + Vector2(-9.0, -9.0), station + Vector2(9.0, -9.0),
			station + Vector2(9.0, 9.0), station + Vector2(-9.0, 9.0),
		])
		draw_colored_polygon(pts, Color(PAPER, 0.98))
		draw_polyline(DrawUtil.closed(pts), Color(accent, 0.9), 2.5, true)
	else:
		draw_circle(station, 10.0, Color(PAPER, 0.98), true, -1.0, true)
		draw_arc(station, 10.0, 0.0, TAU, 28, Color(accent, 0.9), 2.5, true)
	_text_centered(title, rect.get_center().x,
		rect.position.y + (49.0 if _mobile_ui else 32.0), 24,
		Color(1.0, 1.0, 1.0, 0.94))
	if not _mobile_ui:
		_text_centered(desc, rect.get_center().x, rect.position.y + 58.0, 16,
			Color(1.0, 1.0, 1.0, 0.54))


func _draw_departure_button(rect: Rect2, label: String, hovered: bool) -> void:
	_draw_soft_shadow(rect, 18.0, 0.30 if hovered else 0.18, Vector2(0.0, 10.0))
	var poly := DrawUtil.rounded_rect(rect, 18.0, 10)
	draw_colored_polygon(poly, Color("#FFFFFF") if hovered else Color(PAPER, 0.98))
	draw_rect(Rect2(rect.position + Vector2(24.0, 0.0), Vector2(rect.size.x - 48.0, 5.0)),
		Color(GOLD, 0.95))
	draw_polyline(DrawUtil.closed(poly), Color(INK, 0.30), 1.4, true)
	# 发车按钮左侧放一列小列车，直接借用游戏里的车身元素
	var train_center := Vector2(rect.position.x + 54.0, rect.get_center().y + 2.0)
	_draw_capsule(train_center, Color(PAPER, 0.98), 62.0, 28.0)
	_draw_capsule(train_center, Color(ACCENT, 0.96), 54.0, 21.0)
	draw_line(train_center + Vector2(-14.0, 0.0), train_center + Vector2(14.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.55), 2.0, true)
	draw_circle(train_center + Vector2(18.0, 8.0), 4.0, Color(INK, 0.82), true, -1.0, true)
	draw_circle(train_center + Vector2(-18.0, 8.0), 4.0, Color(INK, 0.82), true, -1.0, true)
	var text_x := rect.position.x + 96.0
	_text(label, Vector2(text_x, rect.position.y + (62.0 if _mobile_ui else 39.0)), 29, INK)
	if not _mobile_ui:
		_text("START RUN", Vector2(text_x + 2.0, rect.position.y + 61.0),
			14, Color(MUTED, 0.82))
	# 右侧出发箭头
	var arrow := Vector2(rect.end.x - 34.0, rect.get_center().y)
	draw_line(arrow - Vector2(10.0, 0.0), arrow + Vector2(10.0, 0.0), Color(ACCENT, 0.82), 2.5, true)
	draw_line(arrow + Vector2(10.0, 0.0), arrow + Vector2(2.0, -8.0), Color(ACCENT, 0.82), 2.5, true)
	draw_line(arrow + Vector2(10.0, 0.0), arrow + Vector2(2.0, 8.0), Color(ACCENT, 0.82), 2.5, true)


func _mode_kind_at(index: int) -> int:
	match index:
		1:
			return GameMode.Kind.ENDLESS
		2:
			return GameMode.Kind.DAILY
		3:
			return GameMode.Kind.MANAGER
		4:
			return GameMode.Kind.TUTORIAL
		5:
			return GameMode.Kind.DEVELOPMENT
		_:
			return GameMode.Kind.CLASSIC


func _draw_settings(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.07, 0.08, 0.62))
	_draw_vignette(vp, 1.1)
	var panel := Rect2(vp.x * 0.5 - 450.0, vp.y * 0.5 - 410.0, 900.0, 820.0)
	_draw_soft_shadow(panel, 22.0, 0.42, Vector2(0.0, 18.0))
	var panel_poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(panel_poly, Color(0.10, 0.11, 0.12, 0.86))
	draw_polyline(DrawUtil.closed(panel_poly), Color(1.0, 1.0, 1.0, 0.14), 1.5, true)
	draw_rect(Rect2(panel.position + Vector2(30.0, 0.0), Vector2(panel.size.x - 60.0, 4.0)),
		Color(GOLD, 0.85))
	_text_centered(Loc.t("暂停 · 设置", "Paused · Settings"), vp.x * 0.5,
		vp.y * 0.5 - 365.0, 38, Color(1.0, 1.0, 1.0, 0.98))
	_draw_accent_rule(Vector2(vp.x * 0.5, vp.y * 0.5 - 338.0), 90.0, GOLD)
	var labels := [
		Loc.t("继续", "Resume"),
		Loc.t("主音量", "Master volume"),
		Loc.t("音乐音量", "Music volume"),
		Loc.t("全屏", "Fullscreen"),
		Loc.t("语言", "Language"),
		Loc.t("长按移站", "Hold to remove"),
		Loc.t("玩家名", "Player name"),
		Loc.t("重新开始", "Restart"),
		Loc.t("返回模式选择", "Mode menu"),
	]
	var values := [
		"", _percent(float(settings_values.get("master_volume", 0.8))),
		_percent(float(settings_values.get("music_volume", 0.7))),
		Loc.t("开", "On") if bool(settings_values.get("fullscreen", false)) else Loc.t("关", "Off"),
		"中文" if String(settings_values.get("language", "zh")) == "zh" else "English",
		"%.1fs" % float(settings_values.get("station_remove_time", 0.8)),
		String(settings_values.get("player_name", "玩家")),
		"", "",
	]
	var row_width := 820.0
	var row_height := 72.0
	var step := 80.0
	var start_x := (vp.x - row_width) * 0.5
	var start_y := vp.y * 0.5 - 360.0
	_settings_minus_rects = []
	_settings_plus_rects = []
	_settings_minus_rows = []
	_settings_plus_rows = []
	for i in labels.size():
		var row := Rect2(start_x, start_y + float(i) * step, row_width, row_height)
		if i == settings_index:
			_draw_soft_shadow(row, 12.0, 0.20, Vector2(0.0, 5.0))
			var poly := DrawUtil.rounded_rect(row, 12.0, 6)
			draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.13))
			draw_line(row.position + Vector2(10.0, 14.0),
				Vector2(row.position.x + 10.0, row.end.y - 14.0), Color(GOLD, 0.8), 3.0, true)
		_text(String(labels[i]), Vector2(row.position.x + 40.0, row.position.y + 47.0), 34,
			Color(1.0, 1.0, 1.0, 0.94 if i == settings_index else 0.78))
		if i in [1, 2, 5]:
			var minus_rect := Rect2(row.end.x - 290.0, row.position.y + 9.0, 54.0, 54.0)
			var plus_rect := Rect2(row.end.x - 220.0, row.position.y + 9.0, 54.0, 54.0)
			_settings_minus_rects.append(minus_rect)
			_settings_plus_rects.append(plus_rect)
			_settings_minus_rows.append(i)
			_settings_plus_rows.append(i)
			for pair in [{"rect": minus_rect, "text": "-"}, {"rect": plus_rect, "text": "+"}]:
				var br: Rect2 = pair["rect"]
				var bp := DrawUtil.rounded_rect(br, 12.0, 6)
				draw_colored_polygon(bp, Color(1.0, 1.0, 1.0, 0.14))
				draw_polyline(DrawUtil.closed(bp), Color(1.0, 1.0, 1.0, 0.35), 1.5, true)
				_text_centered(String(pair["text"]), br.position.x + 27.0,
					br.position.y + 39.0, 34, Color(1.0, 1.0, 1.0, 0.9))
		if values[i] != "":
			var text := String(values[i])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				_scaled_size(32)).x
			_text(text, Vector2(row.position.x + row.size.x - 40.0 - width, row.position.y + 47.0),
				32, Color(1.0, 1.0, 1.0, 0.88))
	_text_centered(Loc.t("点击行切换/确认 · 音量与移站时间可点 - / + · Esc 返回",
		"Tap a row · use - / + for volume or remove time · Esc back"),
		vp.x * 0.5, vp.y * 0.5 + 382.0, 20, Color(1.0, 1.0, 1.0, 0.65))


func _draw_game_over(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var extra := clampf((ui_text_scale - 1.0) / 0.28, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.065, 0.075, 0.70))
	_draw_vignette(vp, 1.4)
	# 失败红晕，中心亮、边缘暗
	draw_circle(Vector2(cx, cy - 70.0), 250.0, Color(ACCENT, 0.035), true, -1.0, true)
	draw_circle(Vector2(cx, cy - 70.0), 170.0, Color(ACCENT, 0.045), true, -1.0, true)
	_text_centered(Loc.t("本次运营结束", "RUN ENDED"), cx, cy - 168.0 - 42.0 * extra, 18,
		Color(GOLD, 0.85))
	_text_centered(Loc.t("拥堵失控", "Overcrowded"), cx + 2.0, cy - 96.0, 68,
		Color(0.0, 0.0, 0.0, 0.30))
	_text_centered(Loc.t("拥堵失控", "Overcrowded"), cx, cy - 98.0, 68,
		Color(1.0, 1.0, 1.0, 0.98))
	_draw_accent_rule(Vector2(cx, cy - 62.0 - 6.0 * extra), 220.0, ACCENT)
	# 两个数据卡
	var score_title := Loc.t("送达乘客", "DELIVERED")
	if development_mode:
		score_title = Loc.t("累计金币", "COINS EARNED") if not endless_mode \
			else Loc.t("每30秒金币", "COINS / 30S")
	elif endless_mode:
		score_title = Loc.t("每30秒客运量", "PASSENGERS / 30S")
	var card_w := 250.0
	var card_h := 104.0 + 48.0 * extra
	var gap := 22.0
	var stats_total := card_w * 2.0 + gap
	var stat_y := cy - 28.0 - 12.0 * extra
	var cards := [
		{"title": score_title, "value": final_score, "accent": GOLD},
		{"title": Loc.t("历史最高", "BEST"), "value": best_score, "accent": ACCENT},
	]
	for i in 2:
		var rect := Rect2(cx - stats_total * 0.5 + float(i) * (card_w + gap), stat_y,
			card_w, card_h)
		_draw_soft_shadow(rect, 16.0, 0.30, Vector2(0.0, 8.0))
		var poly := DrawUtil.rounded_rect(rect, 16.0, 8)
		draw_colored_polygon(poly, Color(0.09, 0.10, 0.11, 0.72))
		draw_polyline(DrawUtil.closed(poly), Color(1.0, 1.0, 1.0, 0.12), 1.2, true)
		_text_centered(String(cards[i]["title"]), rect.get_center().x,
			rect.position.y + (40.0 if _mobile_ui else 28.0), 16, Color(1.0, 1.0, 1.0, 0.55))
		_text_centered(str(cards[i]["value"]), rect.get_center().x,
			rect.position.y + (110.0 if _mobile_ui else 76.0), 46, Color(cards[i]["accent"], 0.98))
	var button_size := Vector2(340.0, 88.0)
	var button_gap := 32.0
	var button_y := cy + 104.0 + 36.0 * extra
	if game_over_can_restart:
		_game_over_restart_rect = Rect2(
			Vector2(cx - button_size.x - button_gap * 0.5, button_y), button_size)
		_game_over_menu_rect = Rect2(
			Vector2(cx + button_gap * 0.5, button_y), button_size)
	else:
		_game_over_restart_rect = Rect2()
		_game_over_menu_rect = Rect2(Vector2(cx - button_size.x * 0.5, button_y), button_size)
	_draw_touch_button(_game_over_restart_rect,
		Loc.t("重新开始", "Restart"), _game_over_restart_rect.has_point(get_global_mouse_position()))
	_draw_touch_button(_game_over_menu_rect,
		Loc.t("返回模式选择", "Mode menu"), _game_over_menu_rect.has_point(get_global_mouse_position()))
	_text_centered(Loc.t("也可按 R 重新开始 · M 返回模式选择",
		"Keyboard: R restart · M mode menu"), cx, cy + 232.0 + 28.0 * extra, 19,
		Color(1.0, 1.0, 1.0, 0.48))


## 大号触屏按钮：绘制 + 文本。
func _draw_touch_button(rect: Rect2, label: String, hovered: bool) -> void:
	if rect.size.x <= 0.0:
		return
	_draw_soft_shadow(rect, 15.0, 0.22 if hovered else 0.12, Vector2(0.0, 7.0))
	var poly := DrawUtil.rounded_rect(rect, 16.0, 10)
	draw_colored_polygon(poly, Color("#FFFFFF") if hovered else Color("#FBF8F1", 0.96))
	# 顶部一条极浅高光，底部一条强调色细线
	draw_line(rect.position + Vector2(18.0, 2.0), Vector2(rect.end.x - 18.0, rect.position.y + 2.0),
		Color(1.0, 1.0, 1.0, 0.72), 1.5, true)
	draw_line(rect.position + Vector2(24.0, rect.size.y - 3.0),
		Vector2(rect.end.x - 24.0, rect.position.y + rect.size.y - 3.0),
		Color(ACCENT, 0.50 if hovered else 0.26), 2.0, true)
	draw_polyline(DrawUtil.closed(poly), Color(INK, 0.34 if hovered else 0.20), 1.4, true)
	_text_centered(label, rect.get_center().x,
		rect.position.y + rect.size.y * 0.5 + 10.0, 30, INK)


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------

func _compute_card_rects(vp: Vector2, count: int, width: float, height: float,
		gap: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if count <= 0:
		return rects
	var total := width * count + gap * (count - 1)
	var start_x := (vp.x - total) * 0.5
	var y := vp.y * 0.5 - height * 0.5
	for i in count:
		rects.append(Rect2(Vector2(start_x + float(i) * (width + gap), y), Vector2(width, height)))
	return rects


## 边缘暗角：用一圈低透明横向/纵向色带模拟柔和 vignette。
func _draw_vignette(vp: Vector2, strength: float = 1.0) -> void:
	for i in 9:
		var depth := float(i) * 16.0
		var band := 16.0
		var alpha := 0.028 * strength * (1.0 - float(i) / 12.0)
		draw_rect(Rect2(Vector2(0.0, depth), Vector2(vp.x, band)), Color(DEEP, alpha))
		draw_rect(Rect2(Vector2(0.0, vp.y - depth - band), Vector2(vp.x, band)), Color(DEEP, alpha))
		draw_rect(Rect2(Vector2(depth, 0.0), Vector2(band, vp.y)), Color(DEEP, alpha))
		draw_rect(Rect2(Vector2(vp.x - depth - band, 0.0), Vector2(band, vp.y)), Color(DEEP, alpha))


## 卡片背后的柔和投影（CanvasItem 没有 blur，用几层 alpha 叠出层次）。
func _draw_soft_shadow(rect: Rect2, radius: float, strength: float = 0.18,
		offset: Vector2 = Vector2(0.0, 9.0)) -> void:
	var base := Rect2(rect.position + offset, rect.size)
	for i in 3:
		var grow := 5.0 + float(i) * 5.0
		var alpha := strength * (0.42 - float(i) * 0.10)
		var poly := DrawUtil.rounded_rect(base.grow(grow), radius + grow, 8)
		draw_colored_polygon(poly, Color(0.04, 0.05, 0.06, alpha))


func _draw_accent_rule(center: Vector2, width: float, color: Color = ACCENT) -> void:
	draw_line(center - Vector2(width * 0.5, 0.0), center + Vector2(width * 0.5, 0.0),
		Color(color, 0.85), 3.0, true)
	draw_circle(center + Vector2(width * 0.5 + 9.0, 0.0), 2.2, Color(color, 0.7), true, -1.0, true)


## 启动动画：一条线路先被"画"出来，列车沿线路驶入，标题像站牌一样亮起。
func _draw_startup_intro(vp: Vector2) -> void:
	var t := clampf(startup_intro_time / STARTUP_INTRO_DURATION, 0.0, 1.0)
	var alpha := 1.0 - smoothstep(0.84, 1.0, t)
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	draw_rect(Rect2(Vector2.ZERO, vp), Color("#111518", alpha))
	# 中心暖光与低对比度网格
	for i in 4:
		draw_circle(Vector2(cx, cy - 40.0), 240.0 + float(i) * 120.0,
			Color(ACCENT, (0.026 - float(i) * 0.005) * alpha), true, -1.0, true)
	for i in 7:
		var gy := fmod(float(i) * 190.0 + t * 8.0, vp.y + 120.0) - 60.0
		draw_line(Vector2(0.0, gy), Vector2(vp.x, gy), Color(1.0, 1.0, 1.0, 0.028 * alpha), 1.0, true)

	var reveal := smoothstep(0.06, 0.64, t)
	var route := PackedVector2Array([
		Vector2(vp.x * 0.05, vp.y * 0.75),
		Vector2(vp.x * 0.23, vp.y * 0.75),
		Vector2(vp.x * 0.34, vp.y * 0.63),
		Vector2(vp.x * 0.58, vp.y * 0.63),
		Vector2(vp.x * 0.69, vp.y * 0.75),
		Vector2(vp.x * 0.95, vp.y * 0.75),
	])
	var colors := [ACCENT, TEAL, GOLD, ACCENT, TEAL]
	var total := 0.0
	for i in range(route.size() - 1):
		total += route[i].distance_to(route[i + 1])
	var remaining := total * reveal
	var cumulative := 0.0
	for i in range(route.size() - 1):
		var a := route[i]
		var b := route[i + 1]
		var seg_len := a.distance_to(b)
		var color: Color = colors[i % colors.size()]
		if remaining > 0.01 and seg_len > 0.01:
			var take := minf(seg_len, remaining)
			var partial := a.lerp(b, take / seg_len)
			draw_line(a, partial, Color(color, 0.13 * alpha), 30.0, true)
			draw_line(a, partial, Color(color, 0.92 * alpha), 8.0, true)
			draw_line(a, partial, Color(1.0, 1.0, 1.0, 0.38 * alpha), 2.0, true)
		cumulative += seg_len
		if reveal * total >= cumulative - 1.0:
			draw_circle(b, 10.0, Color(PAPER, alpha), true, -1.0, true)
			draw_arc(b, 10.0, 0.0, TAU, 32, Color(color, alpha), 3.5, true)
		remaining -= seg_len
	# 起点站也画出来
	if reveal > 0.01:
		draw_circle(route[0], 10.0, Color(PAPER, alpha), true, -1.0, true)
		draw_arc(route[0], 10.0, 0.0, TAU, 32, Color(ACCENT, alpha), 3.5, true)

	# 车头沿线行驶
	if reveal > 0.02:
		var target_len := total * reveal
		var walked := 0.0
		for i in range(route.size() - 1):
			var a := route[i]
			var b := route[i + 1]
			var seg_len := a.distance_to(b)
			if walked + seg_len >= target_len:
				var local := 0.0 if seg_len <= 0.01 else (target_len - walked) / seg_len
				var head := a.lerp(b, clampf(local, 0.0, 1.0))
				var angle := (b - a).angle()
				draw_circle(head, 20.0, Color(ACCENT, 0.09 * alpha), true, -1.0, true)
				draw_set_transform(head, angle)
				_draw_capsule(Vector2.ZERO, Color(PAPER, alpha), 62.0, 30.0)
				_draw_capsule(Vector2.ZERO, Color(ACCENT, alpha), 54.0, 23.0)
				draw_line(Vector2(-15.0, 0.0), Vector2(15.0, 0.0),
					Color(1.0, 1.0, 1.0, 0.55 * alpha), 2.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				break
			walked += seg_len

	var title_ease := smoothstep(0.16, 0.48, t)
	var title_y := cy - 58.0 + (1.0 - title_ease) * 26.0
	var title_alpha := title_ease * alpha
	_text_tracked_centered("MINI METRO", cx + 2.0, title_y + 2.0, 76,
		Color(0.0, 0.0, 0.0, 0.30 * title_alpha), 11.0)
	_text_tracked_centered("MINI METRO", cx, title_y, 76,
		Color(1.0, 1.0, 1.0, 0.98 * title_alpha), 11.0)
	var rule_w := 190.0 * smoothstep(0.30, 0.55, t)
	if rule_w > 0.5:
		draw_line(Vector2(cx - rule_w * 0.5, cy + 22.0), Vector2(cx + rule_w * 0.5, cy + 22.0),
			Color(GOLD, 0.8 * alpha), 2.5, true)
	var sub_alpha := smoothstep(0.42, 0.62, t) * alpha
	_text_centered(Loc.t("纸感地铁调度", "A PAPER METRO"), cx, cy + 60.0, 23,
		Color(0.96, 0.80, 0.56, 0.85 * sub_alpha))

	# 底部进度条与状态文案
	var bar_y := vp.y - 104.0
	var bar_w := 360.0
	draw_rect(Rect2(cx - bar_w * 0.5, bar_y, bar_w, 2.0), Color(1.0, 1.0, 1.0, 0.10 * alpha))
	draw_rect(Rect2(cx - bar_w * 0.5, bar_y, bar_w * t, 2.0), Color(GOLD, 0.85 * alpha))
	_text_centered(Loc.t("正在铺开线路图", "Laying out the lines"), cx, bar_y - 18.0, 18,
		Color(1.0, 1.0, 1.0, 0.44 * alpha))
	_text_centered(Loc.t("点击或按键跳过", "Click or press any key to skip"), cx,
		bar_y + 24.0, 15, Color(1.0, 1.0, 1.0, 0.26 * alpha))


## 模式菜单背景的呼吸路径与光晕。
func _draw_menu_ambient(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var t := float(Time.get_ticks_msec()) / 1000.0
	for i in 4:
		var radius := 180.0 + float(i) * 95.0 + sin(t * 0.5 + float(i)) * 8.0
		draw_circle(Vector2(cx, cy - 245.0), radius, Color(ACCENT, 0.010 - float(i) * 0.002),
			true, -1.0, true)
	# 低对比度装饰轨道：缓慢漂移的 45°/水平线
	var offset := fmod(t * 9.0, 120.0)
	for i in 5:
		var y := 100.0 + float(i) * 235.0 + offset
		draw_line(Vector2(-60.0, y), Vector2(vp.x + 60.0, y),
			Color(0.9, 0.88, 0.80, 0.045), 1.2, true)
		draw_line(Vector2(-60.0 + y * 0.4, vp.y + 60.0), Vector2(vp.x + 60.0, -60.0),
			Color(GOLD, 0.018), 2.0, true)
	for i in 22:
		var px := fmod(float(i * 157) + t * (5.0 + float(i % 3) * 2.0), vp.x + 80.0) - 40.0
		var py := 90.0 + fmod(float(i * 91), vp.y - 180.0) + sin(t * 0.7 + float(i)) * 6.0
		draw_circle(Vector2(px, py), 1.6 + float(i % 3) * 0.6,
			Color(1.0, 1.0, 1.0, 0.12), true, -1.0, true)


func _percent(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


func _draw_capsule(center: Vector2, color: Color, w: float, h: float) -> void:
	var r := h * 0.5
	var half := w * 0.5 - r
	var a := center - Vector2(half, 0.0)
	var b := center + Vector2(half, 0.0)
	draw_line(a, b, color, h, true)
	draw_circle(a, r, color, true, -1.0, true)
	draw_circle(b, r, color, true, -1.0, true)


func _draw_capsule_outline(center: Vector2, color: Color, w: float, h: float) -> void:
	var r := h * 0.5
	var half := w * 0.5 - r
	var a := center - Vector2(half, 0.0)
	var b := center + Vector2(half, 0.0)
	draw_line(a + Vector2(0.0, -r), b + Vector2(0.0, -r), color, 2.0, true)
	draw_line(a + Vector2(0.0, r), b + Vector2(0.0, r), color, 2.0, true)
	draw_arc(a, r, 0.5 * PI, 1.5 * PI, 16, color, 2.0, true)
	draw_arc(b, r, -0.5 * PI, 0.5 * PI, 16, color, 2.0, true)


func _speed_label() -> String:
	if is_equal_approx(speed, 1.0):
		return "1"
	if is_equal_approx(speed, 2.0):
		return "2"
	return "3"


func _text(s: String, pos: Vector2, size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var scaled := _scaled_size(size)
	draw_string(font, pos, s, align, -1.0, scaled, color)


func _text_centered(s: String, center_x: float, baseline_y: float, size: int, color: Color) -> void:
	var scaled := _scaled_size(size)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled).x
	draw_string(font, Vector2(center_x - w * 0.5, baseline_y), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled, color)


## 字距拉开的标题：像车站站牌上的大写字，而不是普通居中文本。
func _text_tracked_centered(s: String, center_x: float, baseline_y: float, size: int,
		color: Color, tracking: float) -> void:
	var scaled := _scaled_size(size)
	var scaled_tracking := _scaled_tracking(tracking)
	var total := 0.0
	for i in s.length():
		total += font.get_string_size(s[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled).x
	total += scaled_tracking * float(maxi(s.length() - 1, 0))
	var x := center_x - total * 0.5
	for i in s.length():
		var ch := s[i]
		draw_string(font, Vector2(x, baseline_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled, color)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled).x + scaled_tracking


func _text_right(s: String, right_x: float, baseline_y: float, size: int, color: Color) -> void:
	var scaled := _scaled_size(size)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled).x
	draw_string(font, Vector2(right_x - w, baseline_y), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled, color)


## 按空格断行并居中（中文没有空格，会整行绘制）。
func _text_wrapped(s: String, center_x: float, baseline_y: float, size: int,
		max_width: float, color: Color) -> void:
	var scaled := _scaled_size(size)
	var words := s.split(" ", false)
	var lines: Array[String] = []
	var current := ""
	for word in words:
		var candidate := word if current == "" else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled).x <= max_width:
			current = candidate
		else:
			if current != "":
				lines.append(current)
			current = word
	if current != "":
		lines.append(current)
	for i in lines.size():
		var line_width := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled).x
		draw_string(font, Vector2(center_x - line_width * 0.5,
			baseline_y + float(i) * (scaled + 6.0 * ui_text_scale)),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, scaled, color)
