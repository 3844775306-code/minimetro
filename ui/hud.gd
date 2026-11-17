class_name Hud
extends Control
## HUD：标题、资源槽、送达分数、周数、操作提示、Toast、暂停/倍速、
## 周结算升级卡弹窗、游戏结束遮罩。
## 中文字体用 SystemFont 取系统字体（不随项目分发字体文件），避免豆腐块。

const INK := Color("#2B2B2B")
const MUTED := Color("#7C7568")
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

var game_over := false
var final_score := 0

var week_modal := false
var week_cards: Array = []
var _card_rects: Array[Rect2] = []

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


func show_game_over(final: int) -> void:
	game_over = true
	final_score = final
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


## 返回点击命中的卡片下标（-1 = 没点中）。
func card_at(pos: Vector2) -> int:
	for i in _card_rects.size():
		if _card_rects[i].has_point(pos):
			return i
	return -1


func _process(delta: float) -> void:
	if toast_left > 0.0:
		toast_left = maxf(0.0, toast_left - delta)
	queue_redraw()


func _draw() -> void:
	if font == null or level == null:
		return
	var vp := get_viewport_rect().size
	_text_centered("MINI METRO · 手势原型", vp.x * 0.5, 74.0, 17, Color(MUTED, 0.8))
	_draw_resource_slots(vp)
	_text_right("已送达 %d" % score, vp.x - 72.0, 116.0, 28, INK)
	_text_right("车站 %d · 列车 %d" % [
		0 if network == null else network.stations.size(),
		0 if network == null else network.train_count(),
	], vp.x - 72.0, 146.0, 16, Color(MUTED, 0.85))
	_text_right("第 %d 周 · 车厢 %d" % [
		week, 0 if network == null else network.total_carriages(),
	], vp.x - 72.0, 172.0, 16, Color(MUTED, 0.7))
	_text_centered(
		"拖拽连线 · 拖端点延伸 · 拖中途站换序 · 拖线段插站 · 轻点线路翻折 · Ctrl+Z 撤销",
		vp.x * 0.5, vp.y - 46.0, 18, Color(MUTED, 0.9))
	if paused and not game_over:
		_text_centered("已暂停", vp.x * 0.5, vp.y * 0.5, 44, Color(INK, 0.75))
	_text_right("%s 倍速" % _speed_label(), vp.x - 72.0, vp.y - 46.0, 16, Color(MUTED, 0.7))
	if toast_left > 0.0:
		var alpha: float = clampf(toast_left / 0.5, 0.0, 1.0)
		_text_centered(toast_text, vp.x * 0.5, vp.y - 120.0, 22, Color(INK, alpha))
	if week_modal:
		_draw_week(vp)
	if game_over:
		_draw_game_over(vp)


func _draw_resource_slots(vp: Vector2) -> void:
	var used := 0 if network == null else network.lines.size()
	_text("线路", Vector2(72.0, 107.0), 18, MUTED)
	var y := 100.0
	for i in level.start_lines:
		var x := 130.0 + float(i) * (CHIP_W + CHIP_GAP)
		if i < used:
			_draw_capsule(Vector2(x, y), level.line_colors[i % level.line_colors.size()], CHIP_W, CHIP_H)
		else:
			_draw_capsule_outline(Vector2(x, y),
				Color(level.line_colors[i % level.line_colors.size()], 0.32), CHIP_W, CHIP_H)
	var count_x := 130.0 + float(level.start_lines) * (CHIP_W + CHIP_GAP) + 6.0
	_text("%d/%d" % [used, level.start_lines], Vector2(count_x, 107.0), 16, Color(MUTED, 0.85))
	_text("列车", Vector2(72.0, 143.0), 18, MUTED)
	var trains := 0 if network == null else network.train_count()
	_text("%d/%d" % [trains, level.start_trains], Vector2(130.0, 143.0), 18, Color(INK, 0.75))
	_text("车厢", Vector2(212.0, 143.0), 18, MUTED)
	var carriages := 0 if network == null else network.total_carriages()
	_text("%d" % carriages, Vector2(268.0, 143.0), 18, Color(INK, 0.75))
	_text("桥梁", Vector2(302.0, 143.0), 18, MUTED)
	_text("%d" % level.start_bridges, Vector2(358.0, 143.0), 18, Color(INK, 0.75))


func _draw_week(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.10, 0.11, 0.52))
	_text_centered("第 %d 周 · 选择升级" % week, vp.x * 0.5, vp.y * 0.5 - 168.0, 40,
		Color(1.0, 1.0, 1.0, 0.96))
	_card_rects = _compute_card_rects(vp)
	var mouse := get_global_mouse_position()
	for i in _card_rects.size():
		var rect: Rect2 = _card_rects[i]
		var hovered := rect.has_point(mouse)
		var fill := Color("#FFFFFF") if hovered else Color("#FBF8F1")
		var poly := DrawUtil.rounded_rect(rect, 20.0, 10)
		draw_colored_polygon(poly, fill)
		draw_polyline(DrawUtil.closed(poly), Color(0.72, 0.69, 0.62), 2.5, true)
		if i < week_cards.size():
			var card: Dictionary = week_cards[i]
			_text_centered(String(card["title"]),
				rect.position.x + rect.size.x * 0.5, rect.position.y + 94.0, 34, INK)
			_text_centered(String(card["desc"]),
				rect.position.x + rect.size.x * 0.5, rect.position.y + 148.0, 18, MUTED)
		_text_centered("按 %d" % (i + 1),
			rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y - 26.0, 16,
			Color(MUTED, 0.8))
	_text_centered("点击卡片，或按 1 / 2", vp.x * 0.5, vp.y * 0.5 + 178.0, 18,
		Color(1.0, 1.0, 1.0, 0.7))


func _compute_card_rects(vp: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var count := week_cards.size()
	if count == 0:
		return rects
	var width := 400.0
	var height := 220.0
	var gap := 44.0
	var total := width * count + gap * (count - 1)
	var start_x := (vp.x - total) * 0.5
	var y := vp.y * 0.5 - height * 0.5
	for i in count:
		rects.append(Rect2(Vector2(start_x + float(i) * (width + gap), y), Vector2(width, height)))
	return rects


func _draw_game_over(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.10, 0.11, 0.58))
	_text_centered("拥堵失控", vp.x * 0.5, vp.y * 0.5 - 16.0, 64, Color(1.0, 1.0, 1.0, 0.96))
	_text_centered("送达 %d 名乘客" % final_score, vp.x * 0.5, vp.y * 0.5 + 44.0, 26,
		Color(1.0, 1.0, 1.0, 0.9))
	_text_centered("按 R 重新开始", vp.x * 0.5, vp.y * 0.5 + 96.0, 20, Color(1.0, 1.0, 1.0, 0.65))


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


## draw_string 的 alignment 只在给定宽度时生效，这里自己量宽度做右对齐。
func _text_right(s: String, right_x: float, baseline_y: float, size: int, color: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(font, Vector2(right_x - w, baseline_y), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
