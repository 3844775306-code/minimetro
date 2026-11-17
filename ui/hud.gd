class_name Hud
extends Control
## HUD 与全部菜单：资源/分数、周抽卡、换乘站点选、模式选择、暂停/设置、结束遮罩。
## 文本全部走 Loc 双语；中文字体用 SystemFont 取系统字体（不打包字体文件）。

const INK := Color("#2B2B2B")
const MUTED := Color("#7C7568")
const PAPER := Color("#FBF8F1")
const WATER := Color("#CFE4EA")
const CHIP_W := 46.0
const CHIP_H := 13.0
const CHIP_GAP := 12.0

var network: MetroNetwork = null
var level: LevelData = null
var font: SystemFont = null

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

var game_over := false
var final_score := 0
var game_over_can_restart := true
var _game_over_restart_rect := Rect2()
var _game_over_menu_rect := Rect2()

var week_modal := false
var reward_title := ""
var week_cards: Array = []
var _card_rects: Array[Rect2] = []

var mode_menu := false
var mode_bests := {}
var _mode_rects: Array[Rect2] = []
var _editor_button_rect := Rect2()
var _daily_board_rect := Rect2()
var _map_hall_rect := Rect2()
var _map_rank_rect := Rect2()

## 排行榜 / 地图大厅浮层
var leaderboard_open := false
var leaderboard_title := ""
var leaderboard_subtitle := ""
var leaderboard_lines: Array[String] = []
var _leaderboard_back_rect := Rect2()
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

var toast_text := ""
var toast_left := 0.0
## 玩家名输入框（设置菜单中的"玩家名"）
var name_edit: LineEdit = null
var name_edit_open := false
signal name_submitted(player_name: String)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Source Han Sans SC", "sans-serif",
	])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	name_edit = LineEdit.new()
	name_edit.visible = false
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.max_length = 16
	name_edit.add_theme_font_size_override("font_size", 26)
	name_edit.text_submitted.connect(_on_name_edit_submitted)
	add_child(name_edit)
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


func mode_card_at(pos: Vector2) -> int:
	for i in _mode_rects.size():
		if _mode_rects[i].has_point(pos):
			return i
	return -1


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
	return 8


## 音量行的触屏 - / + 按钮命中（返回行号，-1 表示没点中）。
func settings_minus_at(pos: Vector2) -> int:
	for i in _settings_minus_rects.size():
		if _settings_minus_rects[i].has_point(pos):
			return i
	return -1


func settings_plus_at(pos: Vector2) -> int:
	for i in _settings_plus_rects.size():
		if _settings_plus_rects[i].has_point(pos):
			return i
	return -1


func show_name_editor(current_name: String) -> void:
	if name_edit == null:
		return
	name_edit_open = true
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
	if name_edit != null:
		name_edit.visible = false
		name_edit.release_focus()
	queue_redraw()


func _on_name_edit_submitted(text: String) -> void:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		cleaned = "玩家"
	hide_name_editor()
	name_submitted.emit(cleaned)


func _process(delta: float) -> void:
	if toast_left > 0.0:
		toast_left = maxf(0.0, toast_left - delta)
	if not mode_menu and not paused:
		hint_left = maxf(0.0, hint_left - delta)
	queue_redraw()


func _draw() -> void:
	if font == null or level == null:
		return
	var vp := get_viewport_rect().size
	if not mode_menu:
		_draw_game_hud(vp)
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
	if name_edit_open:
		_draw_name_modal(vp)


# ---------------------------------------------------------------------------
# 游戏内 HUD
# ---------------------------------------------------------------------------

func _draw_game_hud(vp: Vector2) -> void:
	# 减负版 HUD：左上只留线色/库存，右上不再画面板（避免挡地图）
	_draw_panel(Rect2(34.0, 46.0, 720.0, 156.0))
	if map_name != "":
		_text_centered(map_name, vp.x * 0.5, 54.0, 22, Color(MUTED, 0.8))
	_draw_clock(vp)
	if endless_mode:
		# 无尽模式的评价主指标：最近 30 秒送达量（人 / 30 秒）
		_text_right(Loc.t("平均每30秒 %.0f 人", "%.0f per 30s") % throughput,
			vp.x - 40.0, 152.0, 22, INK)
		_text_right(Loc.t("已送达 %d", "Delivered %d") % score,
			vp.x - 40.0, 182.0, 16, Color(MUTED, 0.9))
	else:
		_text_right(Loc.t("已送达 %d", "Delivered %d") % score, vp.x - 40.0, 152.0, 24, INK)
	if stage_label != "":
		_text_right(stage_label, vp.x - 40.0, 206.0, 13, Color(MUTED, 0.75))
	_draw_resource_slots(vp)
	var show_hint := hint_left > 0.0 or (network != null and network.lines.is_empty())
	if show_hint:
		var hint_alpha: float = 1.0
		if hint_left > 0.0:
			hint_alpha = clampf(hint_left / 2.0, 0.0, 1.0)
		_text_centered(Loc.t(
			"拖拽画线 · 拖端点延伸 · 拖线段插站 · 轻点翻折 · 拖左上角图标放车 · Ctrl+Z 撤销 · Esc 设置",
			"Drag to draw · drag endpoint to extend · drag a segment to insert · tap to flip · drag top-left icons for vehicles · Ctrl+Z undo · Esc settings"
		), vp.x * 0.5, vp.y - 46.0, 16, Color(MUTED, 0.9 * hint_alpha))
	if paused and not game_over and not settings_menu and not week_modal \
			and not mode_menu:
		_text_centered(Loc.t("已暂停", "Paused"), vp.x * 0.5, vp.y * 0.5, 44, Color(INK, 0.75))
		_text_centered(Loc.t("可继续修改线路、调动车厢", "You can still edit lines and move carriages"),
			vp.x * 0.5, vp.y * 0.5 + 36.0, 18, Color(MUTED, 0.75))
	_draw_speed_buttons(vp)
	if toast_left > 0.0:
		var alpha: float = clampf(toast_left / 0.5, 0.0, 1.0)
		_text_centered(toast_text, vp.x * 0.5, vp.y - 120.0, 22, Color(INK, alpha))
	# 悬停车站：显示这个形状代表的地标
	if hover_landmark != "":
		var text_size := font.get_string_size(hover_landmark, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15)
		var rect := Rect2(hover_screen + Vector2(20.0, -40.0),
			Vector2(text_size.x + 22.0, 28.0))
		rect.position.x = clampf(rect.position.x, 12.0, vp.x - rect.size.x - 12.0)
		rect.position.y = clampf(rect.position.y, 12.0, vp.y - rect.size.y - 12.0)
		var poly := DrawUtil.rounded_rect(rect, 9.0, 6)
		draw_colored_polygon(poly, Color("#FBF8F1", 0.96))
		draw_polyline(DrawUtil.closed(poly), Color(0.55, 0.52, 0.47), 1.6, true)
		_text(hover_landmark, rect.position + Vector2(11.0, 20.0), 15, INK)


## HUD 半透明纸面板：地图变丰富后保证左上/右上文字可读
func _draw_panel(rect: Rect2) -> void:
	var poly := DrawUtil.rounded_rect(rect, 14.0, 8)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.92))
	draw_polyline(DrawUtil.closed(poly), Color(0.72, 0.69, 0.62, 0.5), 1.5, true)


## 12 小时制时钟：12 点在上、6 点在下；到了夜晚整块表盘变黑、指针变白。
func _draw_clock(vp: Vector2) -> void:
	var center := Vector2(vp.x - 70.0, 64.0)
	var radius := 30.0
	var strength := Simulation.night_strength(clock_hours)
	var face := Color("#FBF8F1").lerp(Color("#1C1C1E"), strength)
	draw_circle(center, radius, face)
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
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.16, 0.17, 0.19, 0.7), 2.5, true)
	# 数字时间（12 小时制 + 上午/下午）
	var hour := int(floor(fmod(clock_hours, 24.0) + 0.0001)) % 24
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	var minutes := int((clock_hours - floor(clock_hours)) * 60.0)
	var suffix := Loc.t("上午", "AM") if hour < 12 else Loc.t("下午", "PM")
	_text_centered("%s  %02d:%02d %s" % [weekday, display_hour, mini(minutes, 59), suffix],
		center.x, center.y + radius + 18.0, 14, Color(MUTED, 0.9))


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
	var settings_poly := DrawUtil.rounded_rect(_settings_rect, 12.0, 6)
	draw_colored_polygon(settings_poly, Color(1.0, 1.0, 1.0, 0.42))
	draw_polyline(DrawUtil.closed(settings_poly), Color(INK, 0.4), 1.5, true)
	draw_circle(settings_center, 15.0, Color(INK, 0.8), true, -1.0, true)
	draw_circle(settings_center, 6.0, Color(PAPER, 0.95), true, -1.0, true)
	for i in 8:
		var a := TAU * float(i) / 8.0
		draw_line(settings_center + Vector2(cos(a), sin(a)) * 17.0,
			settings_center + Vector2(cos(a), sin(a)) * 23.0, Color(INK, 0.8), 3.5, true)
	var mouse := get_global_mouse_position()
	var pause_hovered := _pause_rect.has_point(mouse)
	var pause_poly := DrawUtil.rounded_rect(_pause_rect, 12.0, 6)
	draw_colored_polygon(pause_poly,
		Color(INK, 0.85) if paused else Color(1.0, 1.0, 1.0, 0.65 if pause_hovered else 0.42))
	draw_polyline(DrawUtil.closed(pause_poly), Color(INK, 0.4), 1.5, true)
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
		var poly := DrawUtil.rounded_rect(rect, 12.0, 6)
		if active:
			draw_colored_polygon(poly, Color(INK, 0.85))
		else:
			draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.65 if hovered else 0.42))
		draw_polyline(DrawUtil.closed(poly), Color(INK, 0.4), 1.5, true)
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
	var y := 88.0
	for i in level.start_lines:
		var x := 64.0 + float(i) * (CHIP_W + CHIP_GAP)
		if i < used:
			_draw_capsule(Vector2(x, y), level.line_colors[i % level.line_colors.size()], CHIP_W, CHIP_H)
		else:
			_draw_capsule_outline(Vector2(x, y),
				Color(level.line_colors[i % level.line_colors.size()], 0.32), CHIP_W, CHIP_H)

	# 第二行：可拖拽的库存图标（列车 / 车厢 / 换乘中心 / 新干线）+ 桥梁余量
	var row_y := 140.0
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
		_draw_stock_icon(kind, center, count > 0)
		_text("x%d" % count, Vector2(center.x + 34.0, row_y + 8.0), 22,
			Color(INK, 0.85) if count > 0 else Color(MUTED, 0.5))
		_stock_rects[kind] = Rect2(center - Vector2(56.0, 48.0), Vector2(120.0, 96.0))

	# 桥梁不是库存，是预算：画桥图标 + 已用/上限
	var bridge_center := Vector2(690.0, row_y)
	_draw_stock_icon("bridge", bridge_center, true)
	var bridges := 0 if network == null else network.used_bridges()
	_text("%d/%d" % [bridges, level.start_bridges], Vector2(bridge_center.x + 34.0, row_y + 8.0),
		22, Color(INK, 0.75))


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
		return rect.position + Vector2(17.0, rect.size.y * 0.5)
	return Vector2(118.0, 146.0)


# ---------------------------------------------------------------------------
# 周抽卡 / 换乘站点选
# ---------------------------------------------------------------------------

func _draw_week(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.10, 0.11, 0.52))
	var title := reward_title if reward_title != "" else \
		Loc.t("第 %d 周 · 选择升级", "Week %d · Choose an upgrade") % week
	_text_centered(title, vp.x * 0.5, vp.y * 0.5 - 168.0, 40, Color(1.0, 1.0, 1.0, 0.96))
	_card_rects = _compute_card_rects(vp, week_cards.size(), 400.0, 220.0, 44.0)
	var mouse := get_global_mouse_position()
	for i in _card_rects.size():
		var rect: Rect2 = _card_rects[i]
		var hovered := rect.has_point(mouse)
		var poly := DrawUtil.rounded_rect(rect, 20.0, 10)
		draw_colored_polygon(poly, Color("#FFFFFF") if hovered else PAPER)
		draw_polyline(DrawUtil.closed(poly), Color(0.72, 0.69, 0.62), 2.5, true)
		if i < week_cards.size():
			var card: Dictionary = week_cards[i]
			_text_centered(String(card["title"]),
				rect.position.x + rect.size.x * 0.5, rect.position.y + 94.0, 32, INK)
			_text_wrapped(String(card["desc"]),
				rect.position.x + rect.size.x * 0.5, rect.position.y + 148.0, 18,
				rect.size.x - 48.0, MUTED)
		_text_centered(Loc.t("按 %d", "Press %d") % (i + 1),
			rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y - 26.0, 16,
			Color(MUTED, 0.8))
	_text_centered(Loc.t("点击卡片，或按 1 / 2", "Click a card, or press 1 / 2"),
		vp.x * 0.5, vp.y * 0.5 + 178.0, 18, Color(1.0, 1.0, 1.0, 0.7))


# ---------------------------------------------------------------------------
# 模式选择 / 暂停设置
# ---------------------------------------------------------------------------

func _draw_mode_menu(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.09, 0.10, 0.11, 0.62))
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	_text_centered("MINI METRO", cx, cy - 290.0, 54, Color(1.0, 1.0, 1.0, 0.97))
	_text_centered(Loc.t("极简地铁调度 · 选择模式与城市", "Minimal metro puzzle · pick a mode and a city"),
		cx, cy - 254.0, 20, Color(1.0, 1.0, 1.0, 0.72))
	_draw_city_selector(vp)
	_draw_mode_cards(vp)
	_text_centered(Loc.t("← → 切换城市 · 点击卡片或按 1 / 2 / 3 / 4 开始",
		"Left / Right city · click a card or press 1 / 2 / 3 / 4"),
		cx, cy + 350.0, 18, Color(1.0, 1.0, 1.0, 0.7))
	# 底部入口：每日榜 / 地图大厅 / 地图排行 / 地图编辑器
	var menu_buttons := [
		{"rect": _daily_board_rect, "text": Loc.t("每日排行榜", "Daily board"),
			"action": "daily", "key": "D"},
		{"rect": _map_hall_rect, "text": Loc.t("地图大厅", "Map hall"),
			"action": "hall", "key": "H"},
		{"rect": _map_rank_rect, "text": Loc.t("地图排行榜", "Map ranks"),
			"action": "rank", "key": "L"},
		{"rect": _editor_button_rect, "text": Loc.t("地图编辑器", "Map editor"),
			"action": "editor", "key": "E"},
	]
	var mouse := get_global_mouse_position()
	var button_w := 250.0
	var button_gap := 16.0
	var total_w := button_w * menu_buttons.size() + button_gap * (menu_buttons.size() - 1)
	var start_x := cx - total_w * 0.5
	for i in menu_buttons.size():
		var rect := Rect2(Vector2(start_x + float(i) * (button_w + button_gap), cy + 218.0),
			Vector2(button_w, 88.0))
		match String(menu_buttons[i]["action"]):
			"daily": _daily_board_rect = rect
			"hall": _map_hall_rect = rect
			"rank": _map_rank_rect = rect
			"editor": _editor_button_rect = rect
		_draw_touch_button(rect, String(menu_buttons[i]["text"]),
			rect.has_point(mouse))


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
	map_hall_open = false
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


func _draw_leaderboard(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.09, 0.10, 0.78))
	var panel_size := Vector2(minf(1760.0, vp.x - 120.0), 260.0 + float(leaderboard_lines.size()) * 44.0)
	panel_size.y = minf(panel_size.y, vp.y - 100.0)
	var panel := Rect2((vp - panel_size) * 0.5, panel_size)
	var poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.98))
	draw_polyline(DrawUtil.closed(poly), Color(0.55, 0.52, 0.47), 2.0, true)
	_text_centered(leaderboard_title, panel.position.x + panel.size.x * 0.5,
		panel.position.y + 68.0, 36, INK)
	_text_centered(leaderboard_subtitle, panel.position.x + panel.size.x * 0.5,
		panel.position.y + 106.0, 18, MUTED)
	var y := panel.position.y + 156.0
	for line in leaderboard_lines:
		_text(line, Vector2(panel.position.x + 70.0, y), 21, INK)
		y += 40.0
		if y > panel.end.y - 110.0:
			break
	_leaderboard_back_rect = Rect2(Vector2(panel.position.x + panel.size.x * 0.5 - 160.0,
		panel.end.y - 96.0), Vector2(320.0, 80.0))
	_draw_touch_button(_leaderboard_back_rect, Loc.t("返回", "Back"),
		_leaderboard_back_rect.has_point(get_global_mouse_position()))


func _draw_name_modal(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.09, 0.10, 0.62))
	var panel := Rect2(vp.x * 0.5 - 350.0, vp.y * 0.5 - 140.0, 700.0, 250.0)
	var poly := DrawUtil.rounded_rect(panel, 20.0, 10)
	draw_colored_polygon(poly, Color(0.12, 0.12, 0.13, 0.96))
	draw_polyline(DrawUtil.closed(poly), Color(1.0, 1.0, 1.0, 0.18), 2.0, true)
	_text_centered(Loc.t("玩家名", "Player name"), vp.x * 0.5,
		vp.y * 0.5 - 98.0, 30, Color(1.0, 1.0, 1.0, 0.96))
	_text_centered(Loc.t("输入后按 Enter 保存 · Esc 取消", "Enter to save · Esc to cancel"),
		vp.x * 0.5, vp.y * 0.5 + 70.0, 16, Color(1.0, 1.0, 1.0, 0.58))


func _draw_map_hall(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.08, 0.09, 0.10, 0.78))
	var panel_size := Vector2(minf(1760.0, vp.x - 120.0), 260.0 + float(map_hall_entries.size()) * 96.0)
	panel_size.y = minf(panel_size.y, vp.y - 100.0)
	var panel := Rect2((vp - panel_size) * 0.5, panel_size)
	var poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(poly, Color(0.99, 0.97, 0.92, 0.98))
	draw_polyline(DrawUtil.closed(poly), Color(0.55, 0.52, 0.47), 2.0, true)
	_text_centered(Loc.t("地图大厅", "Map Hall"), panel.position.x + panel.size.x * 0.5,
		panel.position.y + 64.0, 36, INK)
	_text_centered(Loc.t("点击地图行即可下载到本地，随后会出现在城市列表",
		"Click a map row to download it; it appears in the city list"),
		panel.position.x + panel.size.x * 0.5, panel.position.y + 102.0, 17, MUTED)
	_map_hall_row_rects = []
	var y := panel.position.y + 140.0
	var row_w := panel.size.x - 120.0
	var mouse := get_global_mouse_position()
	for i in map_hall_entries.size():
		var entry: Dictionary = map_hall_entries[i]
		var row := Rect2(panel.position.x + 60.0, y, row_w, 84.0)
		_map_hall_row_rects.append(row)
		var hovered := row.has_point(mouse)
		var row_poly := DrawUtil.rounded_rect(row, 12.0, 6)
		draw_colored_polygon(row_poly, Color(INK, 0.06 if hovered else 0.03))
		draw_polyline(DrawUtil.closed(row_poly), Color(0.72, 0.69, 0.62), 1.2, true)
		_text(String(entry.get("name_zh", entry.get("name_en", "未命名"))),
			row.position + Vector2(28.0, 34.0), 24, INK)
		_text(Loc.t("作者 %s · 下载 %d", "by %s · %d downloads") % [
			String(entry.get("author", "?")), int(entry.get("downloads", 0)),
		], row.position + Vector2(28.0, 64.0), 17, MUTED)
		_text_centered(Loc.t("下载", "Download"), row.end.x - 100.0,
			row.position.y + 48.0, 22, Color(INK, 0.75))
		y += 96.0
		if y > panel.end.y - 110.0:
			break
	_map_hall_back_rect = Rect2(Vector2(panel.position.x + panel.size.x * 0.5 - 160.0,
		panel.end.y - 96.0), Vector2(320.0, 80.0))
	_draw_touch_button(_map_hall_back_rect, Loc.t("返回", "Back"),
		_map_hall_back_rect.has_point(get_global_mouse_position()))


## 城市切换：左右箭头 + 城市名 + 迷你河道预览。
func _draw_city_selector(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var city: CityMap = null
	if not menu_cities.is_empty():
		city_index = clampi(city_index, 0, menu_cities.size() - 1)
		city = menu_cities[city_index]
	if city != null:
		_text_centered(city.display_name(), cx, cy - 216.0, 30, Color(1.0, 1.0, 1.0, 0.95))
	_draw_city_preview(Rect2(cx - 180.0, cy - 204.0, 360.0, 176.0), city)
	_city_arrow_rects = [
		Rect2(cx - 292.0, cy - 160.0, 90.0, 90.0),
		Rect2(cx + 202.0, cy - 160.0, 90.0, 90.0),
	]
	var mouse := get_global_mouse_position()
	for i in 2:
		var arrow_rect: Rect2 = _city_arrow_rects[i]
		var hovered := arrow_rect.has_point(mouse)
		var color := Color(1.0, 1.0, 1.0, 0.95 if hovered else 0.55)
		_text_centered("‹" if i == 0 else "›", arrow_rect.position.x + 45.0,
			arrow_rect.position.y + 67.0, 62, color)


func _draw_city_preview(rect: Rect2, city: CityMap) -> void:
	var border := DrawUtil.rounded_rect(rect, 14.0, 8)
	draw_colored_polygon(border, WATER)
	var inner := rect.grow(-8.0)
	var land := DrawUtil.rounded_rect(inner, 8.0, 8)
	draw_colored_polygon(land, Color("#F3EFE6"))
	if city != null:
		# 世界坐标（含河道越界的一点余量）→ 预览矩形
		var world_min := Vector2(-60, -60)
		var world_span := Vector2(CityMaps.WORLD_SIZE.x + 120.0, CityMaps.WORLD_SIZE.y + 120.0)
		for river in city.rivers:
			var points := PackedVector2Array()
			for point in river:
				var uv := (point - world_min) / world_span
				points.append(rect.position + uv * rect.size)
			draw_colored_polygon(points, WATER)
	draw_polyline(DrawUtil.closed(border), Color(0.72, 0.69, 0.62), 2.0, true)


func _draw_mode_cards(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var width := 300.0
	var height := 188.0
	var gap := 22.0
	var total := width * 4.0 + gap * 3.0
	var start_x := cx - total * 0.5
	var top := cy + 8.0
	_mode_rects = []
	var mouse := get_global_mouse_position()
	for i in 4:
		var rect := Rect2(start_x + float(i) * (width + gap), top, width, height)
		_mode_rects.append(rect)
		var kind := _mode_kind_at(i)
		var hovered := rect.has_point(mouse)
		var poly := DrawUtil.rounded_rect(rect, 20.0, 10)
		draw_colored_polygon(poly, Color("#FFFFFF") if hovered else PAPER)
		draw_polyline(DrawUtil.closed(poly), Color(0.72, 0.69, 0.62), 2.5, true)
		_text_centered(GameMode.title(kind), rect.position.x + rect.size.x * 0.5,
			rect.position.y + 60.0, 32, INK)
		_text_wrapped(GameMode.description(kind), rect.position.x + rect.size.x * 0.5,
			rect.position.y + 102.0, 16, rect.size.x - 44.0, MUTED)
		var mode_key := GameMode.key(kind)
		var best := int(mode_bests.get(mode_key, 0))
		_text_centered(Loc.t("最高 %d", "Best %d") % best,
			rect.position.x + rect.size.x * 0.5, rect.position.y + 142.0, 17, Color(MUTED, 0.85))
		_text_centered(Loc.t("按 %d", "Press %d") % (i + 1),
			rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y - 20.0, 15,
			Color(MUTED, 0.7))


func _mode_kind_at(index: int) -> int:
	match index:
		1:
			return GameMode.Kind.ENDLESS
		2:
			return GameMode.Kind.DAILY
		3:
			return GameMode.Kind.MANAGER
		_:
			return GameMode.Kind.CLASSIC


func _draw_settings(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.10, 0.11, 0.55))
	var panel := Rect2(vp.x * 0.5 - 450.0, vp.y * 0.5 - 410.0, 900.0, 820.0)
	var panel_poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(panel_poly, Color(0.12, 0.12, 0.13, 0.72))
	draw_polyline(DrawUtil.closed(panel_poly), Color(1.0, 1.0, 1.0, 0.12), 2.0, true)
	_text_centered(Loc.t("暂停 · 设置", "Paused · Settings"), vp.x * 0.5,
		vp.y * 0.5 - 365.0, 34, Color(1.0, 1.0, 1.0, 0.96))
	var labels := [
		Loc.t("继续", "Resume"),
		Loc.t("主音量", "Master volume"),
		Loc.t("音乐音量", "Music volume"),
		Loc.t("全屏", "Fullscreen"),
		Loc.t("语言", "Language"),
		Loc.t("玩家名", "Player name"),
		Loc.t("重新开始", "Restart"),
		Loc.t("返回模式选择", "Mode menu"),
	]
	var values := [
		"", _percent(float(settings_values.get("master_volume", 0.8))),
		_percent(float(settings_values.get("music_volume", 0.7))),
		Loc.t("开", "On") if bool(settings_values.get("fullscreen", false)) else Loc.t("关", "Off"),
		"中文" if String(settings_values.get("language", "zh")) == "zh" else "English",
		String(settings_values.get("player_name", "玩家")),
		"", "",
	]
	var row_width := 820.0
	var row_height := 78.0
	var step := 86.0
	var start_x := (vp.x - row_width) * 0.5
	var start_y := vp.y * 0.5 - 350.0
	_settings_minus_rects = [Rect2(), Rect2()]
	_settings_plus_rects = [Rect2(), Rect2()]
	for i in labels.size():
		var row := Rect2(start_x, start_y + float(i) * step, row_width, row_height)
		if i == settings_index:
			var poly := DrawUtil.rounded_rect(row, 12.0, 6)
			draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.16))
		_text(String(labels[i]), Vector2(row.position.x + 40.0, row.position.y + 50.0), 30,
			Color(1.0, 1.0, 1.0, 0.94 if i == settings_index else 0.72))
		if i in [1, 2]:
			var minus_rect := Rect2(row.end.x - 290.0, row.position.y + 12.0, 54.0, 54.0)
			var plus_rect := Rect2(row.end.x - 220.0, row.position.y + 12.0, 54.0, 54.0)
			_settings_minus_rects[i - 1] = minus_rect
			_settings_plus_rects[i - 1] = plus_rect
			for pair in [{"rect": minus_rect, "text": "−"}, {"rect": plus_rect, "text": "+"}]:
				var br: Rect2 = pair["rect"]
				var bp := DrawUtil.rounded_rect(br, 12.0, 6)
				draw_colored_polygon(bp, Color(1.0, 1.0, 1.0, 0.14))
				draw_polyline(DrawUtil.closed(bp), Color(1.0, 1.0, 1.0, 0.35), 1.5, true)
				_text_centered(String(pair["text"]), br.position.x + 27.0,
					br.position.y + 38.0, 30, Color(1.0, 1.0, 1.0, 0.9))
		if values[i] != "":
			var text := String(values[i])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28).x
			_text(text, Vector2(row.position.x + row.size.x - 40.0 - width, row.position.y + 50.0),
				28, Color(1.0, 1.0, 1.0, 0.85))
	_text_centered(Loc.t("点击行切换/确认 · 音量行可点 − / + · Esc 返回",
		"Tap a row to toggle/confirm · tap − / + for volume · Esc back"),
		vp.x * 0.5, vp.y * 0.5 + 382.0, 18, Color(1.0, 1.0, 1.0, 0.6))


func _draw_game_over(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.10, 0.11, 0.58))
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	_text_centered(Loc.t("拥堵失控", "Overcrowded"), cx, cy - 40.0, 60,
		Color(1.0, 1.0, 1.0, 0.96))
	_text_centered(Loc.t("送达 %d 名乘客 · 最高 %d", "Delivered %d · Best %d") % [
		final_score, best_score,
	], cx, cy + 20.0, 26, Color(1.0, 1.0, 1.0, 0.9))
	var button_size := Vector2(340.0, 96.0)
	var gap := 40.0
	if game_over_can_restart:
		_game_over_restart_rect = Rect2(
			Vector2(cx - button_size.x - gap * 0.5, cy + 78.0), button_size)
		_game_over_menu_rect = Rect2(
			Vector2(cx + gap * 0.5, cy + 78.0), button_size)
	else:
		_game_over_restart_rect = Rect2()
		_game_over_menu_rect = Rect2(Vector2(cx - button_size.x * 0.5, cy + 78.0), button_size)
	_draw_touch_button(_game_over_restart_rect,
		Loc.t("重新开始", "Restart"), _game_over_restart_rect.has_point(get_global_mouse_position()))
	_draw_touch_button(_game_over_menu_rect,
		Loc.t("返回模式选择", "Mode menu"), _game_over_menu_rect.has_point(get_global_mouse_position()))
	_text_centered(Loc.t("也可按 R 重新开始 · M 返回模式选择",
		"Keyboard: R restart · M mode menu"), cx, cy + 208.0, 18,
		Color(1.0, 1.0, 1.0, 0.55))


## 大号触屏按钮：绘制 + 文本。
func _draw_touch_button(rect: Rect2, label: String, hovered: bool) -> void:
	if rect.size.x <= 0.0:
		return
	var poly := DrawUtil.rounded_rect(rect, 16.0, 10)
	draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.92 if hovered else 0.80))
	draw_polyline(DrawUtil.closed(poly), Color(0.42, 0.39, 0.35), 2.0, true)
	_text_centered(label, rect.get_center().x, rect.position.y + 58.0, 28, INK)


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
	draw_string(font, pos, s, align, -1.0, size, color)


func _text_centered(s: String, center_x: float, baseline_y: float, size: int, color: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(font, Vector2(center_x - w * 0.5, baseline_y), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _text_right(s: String, right_x: float, baseline_y: float, size: int, color: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(font, Vector2(right_x - w, baseline_y), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


## 按空格断行并居中（中文没有空格，会整行绘制）。
func _text_wrapped(s: String, center_x: float, baseline_y: float, size: int,
		max_width: float, color: Color) -> void:
	var words := s.split(" ", false)
	var lines: Array[String] = []
	var current := ""
	for word in words:
		var candidate := word if current == "" else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x <= max_width:
			current = candidate
		else:
			if current != "":
				lines.append(current)
			current = word
	if current != "":
		lines.append(current)
	for i in lines.size():
		var line_width := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		draw_string(font, Vector2(center_x - line_width * 0.5, baseline_y + float(i) * (size + 6.0)),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
