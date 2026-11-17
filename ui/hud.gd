class_name Hud
extends Control
## HUD 与全部菜单：资源/分数、周抽卡、换乘站点选、模式选择、暂停/设置、结束遮罩。
## 文本全部走 Loc 双语；中文字体用 SystemFont 取系统字体（不打包字体文件）。

const INK := Color("#2B2B2B")
const MUTED := Color("#7C7568")
const PAPER := Color("#FBF8F1")
const WATER := Color("#CFE4EA")
const CHIP_W := 38.0
const CHIP_H := 11.0
const CHIP_GAP := 12.0

var network: MetroNetwork = null
var level: LevelData = null
var font: SystemFont = null

var paused := false
var speed := 1.0
var score := 0
var week := 1
var best_score := 0
## 游戏内时钟（1 现实秒 = 1 游戏小时）
var clock_hours := 7.0
var is_night := false
var weekday := ""
## 城镇发展阶段（村庄/小镇/城市/大都市 · 车站数）
var stage_label := ""
## 操作提示显示剩余时间；超时后隐藏，避免长期占着底部
var hint_left := 18.0
## 鼠标悬停车站时显示的地标名称
var hover_landmark := ""
var hover_screen := Vector2.ZERO
## 库存（可拖到地图上的资源）
var stock_counts := {"train": 0, "carriage": 0, "interchange": 0}
var _speed_rects: Array[Rect2] = []
var _stock_rects := {}

var game_over := false
var final_score := 0

var week_modal := false
var week_cards: Array = []
var _card_rects: Array[Rect2] = []

var mode_menu := false
var mode_bests := {}
var _mode_rects: Array[Rect2] = []
## 模式菜单里的城市选择
var menu_cities: Array = []
var city_index := 0
var _city_arrow_rects: Array[Rect2] = []

var settings_menu := false
var settings_index := 0
## 主循环每帧回填：master_volume / music_volume / fullscreen / language
var settings_values := {}

var toast_text := ""
var toast_left := 0.0


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
	set_process(true)


func setup(net: MetroNetwork, lvl: LevelData) -> void:
	network = net
	level = lvl
	queue_redraw()


func show_toast(message: String) -> void:
	toast_text = message
	toast_left = 2.0
	queue_redraw()


func show_game_over(final: int, best: int) -> void:
	game_over = true
	final_score = final
	best_score = best
	queue_redraw()


func show_week(cards: Array, week_number: int) -> void:
	week_cards = cards
	week = week_number
	week_modal = true
	queue_redraw()


func hide_week() -> void:
	week_modal = false
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
	return 7


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


# ---------------------------------------------------------------------------
# 游戏内 HUD
# ---------------------------------------------------------------------------

func _draw_game_hud(vp: Vector2) -> void:
	# 减负版 HUD：左上只留线色/库存，右上不再画面板（避免挡地图）
	_draw_panel(Rect2(34.0, 66.0, 486.0, 104.0))
	_draw_clock(vp)
	_text_right(Loc.t("已送达 %d", "Delivered %d") % score, vp.x - 40.0, 152.0, 24, INK)
	if stage_label != "":
		_text_right(stage_label, vp.x - 40.0, 176.0, 13, Color(MUTED, 0.75))
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
	var size := Vector2(54.0, 34.0)
	var gap := 8.0
	var total := size.x * 3.0 + gap * 2.0
	var start := Vector2(vp.x - 72.0 - total, vp.y - 118.0)
	_speed_rects = []
	var mouse := get_global_mouse_position()
	for i in 3:
		var rect := Rect2(start + Vector2(float(i) * (size.x + gap), 0.0), size)
		_speed_rects.append(rect)
		var active := is_equal_approx(speed, float(i + 1))
		var hovered := rect.has_point(mouse)
		var poly := DrawUtil.rounded_rect(rect, 8.0, 6)
		if active:
			draw_colored_polygon(poly, Color(INK, 0.85))
		else:
			draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.55 if hovered else 0.35))
		draw_polyline(DrawUtil.closed(poly), Color(INK, 0.4), 1.5, true)
		_text_centered(String(labels[i]), rect.position.x + rect.size.x * 0.5,
			rect.position.y + 23.0, 17, Color(1.0, 1.0, 1.0, 0.95) if active else INK)


## 点击倍速按钮：返回 1/2/3，0 = 没点中。
func speed_button_at(pos: Vector2) -> int:
	for i in _speed_rects.size():
		if _speed_rects[i].has_point(pos):
			return i + 1
	return 0


func _draw_resource_slots(vp: Vector2) -> void:
	var used := 0 if network == null else network.lines.size()
	var y := 100.0
	for i in level.start_lines:
		var x := 64.0 + float(i) * (CHIP_W + CHIP_GAP)
		if i < used:
			_draw_capsule(Vector2(x, y), level.line_colors[i % level.line_colors.size()], CHIP_W, CHIP_H)
		else:
			_draw_capsule_outline(Vector2(x, y),
				Color(level.line_colors[i % level.line_colors.size()], 0.32), CHIP_W, CHIP_H)

	# 第二行：可拖拽的库存图标（列车 / 车厢 / 换乘中心）+ 桥梁余量
	var row_y := 146.0
	_stock_rects = {}
	var slots := [
		{"kind": "train", "x": 118.0, "label": Loc.t("列车", "Trains")},
		{"kind": "carriage", "x": 226.0, "label": Loc.t("车厢", "Cars")},
		{"kind": "interchange", "x": 334.0, "label": Loc.t("换乘", "Transfer")},
	]
	for slot in slots:
		var kind := String(slot["kind"])
		var center := Vector2(float(slot["x"]), row_y)
		var count := int(stock_counts.get(kind, 0))
		_draw_stock_icon(kind, center, count > 0)
		_text("x%d" % count, Vector2(center.x + 24.0, row_y + 6.0), 18,
			Color(INK, 0.8) if count > 0 else Color(MUTED, 0.5))
		_stock_rects[kind] = Rect2(center - Vector2(17.0, 15.0), Vector2(60.0, 30.0))

	# 桥梁不是库存，是预算：画桥图标 + 已用/上限
	var bridge_center := Vector2(452.0, row_y)
	_draw_stock_icon("bridge", bridge_center, true)
	var bridges := 0 if network == null else network.used_bridges()
	_text("%d/%d" % [bridges, level.start_bridges], Vector2(bridge_center.x + 24.0, row_y + 6.0),
		18, Color(INK, 0.75))


## 左上角库存图标：列车 / 车厢 / 换乘中心 / 桥梁。
func _draw_stock_icon(kind: String, center: Vector2, enabled: bool) -> void:
	var ink := Color(INK, 0.9) if enabled else Color(MUTED, 0.45)
	var paper := Color(PAPER, 0.95) if enabled else Color(PAPER, 0.5)
	match kind:
		"train":
			_draw_capsule(center, paper, 30.0, 15.0)
			_draw_capsule_outline(center, ink, 30.0, 15.0)
			draw_rect(Rect2(center + Vector2(5.0, -5.0), Vector2(8.0, 10.0)), Color(ink, 0.25))
			draw_rect(Rect2(center + Vector2(7.0, -3.0), Vector2(4.0, 6.0)), ink)
		"carriage":
			var rect := Rect2(center - Vector2(8.0, 10.0), Vector2(16.0, 20.0))
			draw_rect(rect, paper)
			draw_rect(rect, ink, false, 2.0)
			draw_rect(Rect2(rect.position + Vector2(3.5, 5.0), Vector2(9.0, 4.0)), Color(ink, 0.35))
		"interchange":
			draw_circle(center, 12.0, paper, true, -1.0, true)
			draw_arc(center, 12.0, 0.0, TAU, 32, ink, 2.4, true)
			draw_circle(center, 5.5, Color(ink, 0.18), true, -1.0, true)
			draw_arc(center, 5.5, 0.0, TAU, 24, ink, 2.0, true)
		"bridge":
			draw_line(center + Vector2(-13.0, 6.0), center + Vector2(13.0, 6.0), ink, 2.6, true)
			draw_arc(center + Vector2(0.0, 6.0), 13.0, PI, TAU, 24, ink, 2.2, true)
			draw_line(center + Vector2(-9.0, 6.0), center + Vector2(-9.0, 12.0), ink, 2.2, true)
			draw_line(center + Vector2(9.0, 6.0), center + Vector2(9.0, 12.0), ink, 2.2, true)


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
	_text_centered(Loc.t("第 %d 周 · 选择升级", "Week %d · Choose an upgrade") % week,
		vp.x * 0.5, vp.y * 0.5 - 168.0, 40, Color(1.0, 1.0, 1.0, 0.96))
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
	_text_centered(Loc.t("← → 切换城市 · 点击卡片或按 1 / 2 / 3 开始",
		"Left / Right city · click a card or press 1 / 2 / 3"),
		cx, cy + 246.0, 18, Color(1.0, 1.0, 1.0, 0.7))


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
		Rect2(cx - 232.0, cy - 140.0, 48.0, 48.0),
		Rect2(cx + 184.0, cy - 140.0, 48.0, 48.0),
	]
	var mouse := get_global_mouse_position()
	for i in 2:
		var arrow_rect: Rect2 = _city_arrow_rects[i]
		var hovered := arrow_rect.has_point(mouse)
		var color := Color(1.0, 1.0, 1.0, 0.95 if hovered else 0.55)
		_text_centered("‹" if i == 0 else "›", arrow_rect.position.x + 24.0,
			arrow_rect.position.y + 36.0, 40, color)


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
	var width := 360.0
	var height := 190.0
	var gap := 30.0
	var total := width * 3.0 + gap * 2.0
	var start_x := cx - total * 0.5
	var top := cy + 8.0
	_mode_rects = []
	var mouse := get_global_mouse_position()
	for i in 3:
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
		_:
			return GameMode.Kind.CLASSIC


func _draw_settings(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.10, 0.11, 0.55))
	var panel := Rect2(vp.x * 0.5 - 330.0, vp.y * 0.5 - 214.0, 660.0, 452.0)
	var panel_poly := DrawUtil.rounded_rect(panel, 22.0, 10)
	draw_colored_polygon(panel_poly, Color(0.12, 0.12, 0.13, 0.72))
	draw_polyline(DrawUtil.closed(panel_poly), Color(1.0, 1.0, 1.0, 0.12), 2.0, true)
	_text_centered(Loc.t("暂停 · 设置", "Paused · Settings"), vp.x * 0.5,
		vp.y * 0.5 - 232.0 + 18.0 + 22.0, 34, Color(1.0, 1.0, 1.0, 0.96))
	var labels := [
		Loc.t("继续", "Resume"),
		Loc.t("主音量", "Master volume"),
		Loc.t("音乐音量", "Music volume"),
		Loc.t("全屏", "Fullscreen"),
		Loc.t("语言", "Language"),
		Loc.t("重新开始", "Restart"),
		Loc.t("返回模式选择", "Mode menu"),
	]
	var values := [
		"", _percent(float(settings_values.get("master_volume", 0.8))),
		_percent(float(settings_values.get("music_volume", 0.7))),
		Loc.t("开", "On") if bool(settings_values.get("fullscreen", false)) else Loc.t("关", "Off"),
		"中文" if String(settings_values.get("language", "zh")) == "zh" else "English",
		"", "",
	]
	var row_width := 560.0
	var row_height := 46.0
	var step := 54.0
	var start_x := (vp.x - row_width) * 0.5
	var start_y := vp.y * 0.5 - 160.0
	for i in labels.size():
		var row := Rect2(start_x, start_y + float(i) * step, row_width, row_height)
		if i == settings_index:
			var poly := DrawUtil.rounded_rect(row, 12.0, 6)
			draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.16))
		_text(String(labels[i]), Vector2(row.position.x + 26.0, row.position.y + 30.0), 21,
			Color(1.0, 1.0, 1.0, 0.94 if i == settings_index else 0.72))
		if values[i] != "":
			var text := String(values[i])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
			_text(text, Vector2(row.position.x + row.size.x - 26.0 - width, row.position.y + 30.0),
				20, Color(1.0, 1.0, 1.0, 0.85))
	_text_centered(Loc.t("↑↓ 选择 · ←→ 调整 · Enter 确认 · Esc 返回",
		"Up/Down select · Left/Right adjust · Enter confirm · Esc back"),
		vp.x * 0.5, vp.y * 0.5 + 268.0, 16, Color(1.0, 1.0, 1.0, 0.6))


func _draw_game_over(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.10, 0.11, 0.58))
	_text_centered(Loc.t("拥堵失控", "Overcrowded"), vp.x * 0.5, vp.y * 0.5 - 40.0, 60,
		Color(1.0, 1.0, 1.0, 0.96))
	_text_centered(Loc.t("送达 %d 名乘客 · 最高 %d", "Delivered %d · Best %d") % [
		final_score, best_score,
	], vp.x * 0.5, vp.y * 0.5 + 20.0, 26, Color(1.0, 1.0, 1.0, 0.9))
	_text_centered(Loc.t("按 R 重新开始 · M 返回模式选择",
		"R restart · M mode menu"), vp.x * 0.5, vp.y * 0.5 + 76.0, 20,
		Color(1.0, 1.0, 1.0, 0.65))


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
