class_name Hud
extends Control
## M1 HUD：标题、线路资源槽、站点数、操作提示、Toast、暂停/倍速状态。
## 用 SystemFont 取系统中文字体（不随项目分发字体文件），避免中文变成豆腐块。

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
	_text_right("%d 座车站" % (0 if network == null else network.stations.size()),
		vp.x - 72.0, 107.0, 18, MUTED)
	_text_centered(
		"按住车站拖拽连线 · 拖端点继续延伸 · 拖中途车站调整顺序 · Ctrl+Z 撤销 · 空格暂停",
		vp.x * 0.5, vp.y - 46.0, 18, Color(MUTED, 0.9))
	if paused:
		_text_centered("已暂停", vp.x * 0.5, vp.y * 0.5, 44, Color(INK, 0.75))
	_text_right("%s 倍速" % _speed_label(), vp.x - 72.0, vp.y - 46.0, 16, Color(MUTED, 0.7))
	if toast_left > 0.0:
		var alpha: float = clampf(toast_left / 0.5, 0.0, 1.0)
		_text_centered(toast_text, vp.x * 0.5, vp.y - 120.0, 22, Color(INK, alpha))


func _draw_resource_slots(vp: Vector2) -> void:
	var used := 0 if network == null else network.lines.size()
	_text("线路", Vector2(72.0, 107.0), 18, MUTED)
	var y := 100.0
	for i in level.start_lines:
		var x := 130.0 + float(i) * (CHIP_W + CHIP_GAP)
		if i < used:
			_draw_capsule(Vector2(x, y), level.line_colors[i % level.line_colors.size()], CHIP_W, CHIP_H)
		else:
			_draw_capsule_outline(Vector2(x, y), Color(level.line_colors[i % level.line_colors.size()], 0.32),
				CHIP_W, CHIP_H)
	var count_x := 130.0 + float(level.start_lines) * (CHIP_W + CHIP_GAP) + 6.0
	_text("%d/%d" % [used, level.start_lines], Vector2(count_x, 107.0), 16, Color(MUTED, 0.85))
	_text("列车", Vector2(72.0, 143.0), 18, MUTED)
	_text("%d" % level.start_trains, Vector2(130.0, 143.0), 18, Color(INK, 0.75))
	_text("桥梁", Vector2(196.0, 143.0), 18, MUTED)
	_text("%d" % level.start_bridges, Vector2(252.0, 143.0), 18, Color(INK, 0.75))


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
