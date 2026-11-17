extends Control
## 地图编辑器：拖拽自由绘制河流，保存到 user://custom_maps.json，
## 通过剪贴板 Base64 分享码导出/导入整张地图。

const WORLD := Vector2(2400.0, 1200.0)
const LAND := Color("#F3EFE6")
const WATER := Color("#CFE4EA")
const WATER_EDGE := Color("#B7D3DB")
const DESK := Color("#D8D0C1")
const INK := Color("#2B2B2B")
const MUTED := Color("#7C7568")
const PAPER := Color("#FBF8F1")

var rivers: Array[PackedVector2Array] = []
var current_center := PackedVector2Array()
var width := 100.0
var drawing := false
var map_origin := Vector2.ZERO
var map_scale := 1.0
var editing_id := ""
var _buttons: Array = []
var _undo_stack: Array = []
var _toast := ""
var _toast_left := 0.0
var _font: SystemFont
var _shot_path := ""
var _demo_editor := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg == "--editor-demo":
			_demo_editor = true
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Source Han Sans SC", "sans-serif",
	])
	# 恢复上次最后保存的自定义地图，方便继续修改
	var maps := CustomMapStore.load_maps()
	if not maps.is_empty():
		var map: Dictionary = maps[maps.size() - 1]
		_apply_map(map)
	if _demo_editor:
		rivers.append(CityMaps.editor_band(PackedVector2Array([
			Vector2(300, 380), Vector2(700, 520), Vector2(1100, 430),
			Vector2(1500, 620), Vector2(2000, 500),
		]), 110.0))
	queue_redraw()
	if _shot_path != "":
		_capture_and_quit()


func _capture_and_quit() -> void:
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	print("EDITOR_SCREENSHOT ", _shot_path, " err=", err)
	get_tree().quit(0 if err == OK else 1)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left = maxf(0.0, _toast_left - delta)
		if _toast_left <= 0.0:
			_toast = ""
		queue_redraw()


func _apply_map(map: Dictionary) -> void:
	var city := CustomMapStore.to_city_map(map)
	rivers = city.rivers.duplicate()
	editing_id = city.id
	width = float(map.get("width", 100.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var action := _button_at(event.position)
			if action != "":
				_run_action(action)
				return
			if _map_rect().has_point(event.position):
				drawing = true
				current_center = PackedVector2Array([_screen_to_world(event.position)])
				queue_redraw()
		elif drawing:
			_finish_stroke()
		return
	if event is InputEventMouseMotion and drawing:
		_add_point(event.position)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var action := _button_at(event.position)
			if action != "":
				_run_action(action)
				return
			if _map_rect().has_point(event.position):
				drawing = true
				current_center = PackedVector2Array([_screen_to_world(event.position)])
				queue_redraw()
		elif drawing:
			_finish_stroke()
		return
	if event is InputEventScreenDrag and drawing:
		_add_point(event.position)


func _add_point(screen_pos: Vector2) -> void:
	var world := _screen_to_world(screen_pos)
	if current_center.is_empty() or current_center[current_center.size() - 1].distance_to(world) >= 8.0:
		current_center.append(world)
		queue_redraw()


func _finish_stroke() -> void:
	drawing = false
	if current_center.size() >= 2:
		_undo_stack.append(rivers.duplicate(true))
		var band := CityMaps.editor_band(current_center, width)
		if band.size() >= 3:
			rivers.append(band)
	current_center = PackedVector2Array()
	queue_redraw()


func _run_action(action: String) -> void:
	match action:
		"new":
			_undo_stack.append(rivers.duplicate(true))
			rivers.clear()
			editing_id = ""
		"undo":
			if not _undo_stack.is_empty():
				rivers = _undo_stack.pop_back()
		"clear":
			_undo_stack.append(rivers.duplicate(true))
			rivers.clear()
		"width_minus":
			width = maxf(40.0, width - 20.0)
		"width_plus":
			width = minf(240.0, width + 20.0)
		"save":
			_save_map()
		"share":
			_share_map()
		"upload":
			_upload_map()
		"import":
			_import_share()
		"back":
			get_tree().change_scene_to_file("res://main.tscn")
	queue_redraw()


func _save_map() -> void:
	if rivers.is_empty():
		_toast_now("先画一条河再保存")
		return
	var map := CustomMapStore.new_map(rivers, width, "自定义地图 %d" % (CustomMapStore.load_maps().size() + 1))
	if editing_id != "":
		map["id"] = editing_id
		map["name_zh"] = "自定义地图"
		map["name_en"] = "Custom Map"
	if CustomMapStore.save_map(map):
		editing_id = String(map["id"])
		CityMaps.reload()
		_toast_now("已保存到自定义地图列表")
	else:
		_toast_now("保存失败（user:// 不可写）")


func _share_map() -> void:
	if rivers.is_empty():
		_toast_now("先画一条河再分享")
		return
	var map := CustomMapStore.new_map(rivers, width, "分享地图")
	if editing_id != "":
		map["id"] = editing_id
	var code := CustomMapStore.share_code(map)
	DisplayServer.clipboard_set(code)
	_toast_now("分享码已复制到剪贴板（%d 字符）" % code.length())


func _upload_map() -> void:
	if rivers.is_empty():
		_toast_now("先画一条河再上传")
		return
	var map := CustomMapStore.new_map(rivers, width, "自定义地图 %d" % (CustomMapStore.load_maps().size() + 1))
	if editing_id != "":
		map["id"] = editing_id
	if Cloud != null and Cloud.upload_map(map):
		_toast_now("已上传到地图大厅")
	else:
		_toast_now("上传失败")


func _import_share() -> void:
	var map := CustomMapStore.decode_share(DisplayServer.clipboard_get())
	if map.is_empty():
		_toast_now("剪贴板里没有有效分享码")
		return
	_undo_stack.append(rivers.duplicate(true))
	_apply_map(map)
	editing_id = ""
	_toast_now("已从剪贴板导入地图")


func _toast_now(text: String) -> void:
	_toast = text
	_toast_left = 2.6
	queue_redraw()


func _map_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var avail := Vector2(vp.x - 72.0, vp.y - 390.0)
	map_scale = minf(avail.x / WORLD.x, avail.y / WORLD.y)
	map_scale = maxf(map_scale, 0.1)
	var size := WORLD * map_scale
	map_origin = Vector2((vp.x - size.x) * 0.5, 292.0 + (avail.y - size.y) * 0.5)
	return Rect2(map_origin, size)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - map_origin) / map_scale


func _world_to_screen(world_pos: Vector2) -> Vector2:
	return map_origin + world_pos * map_scale


func _button_at(pos: Vector2) -> String:
	for raw in _buttons:
		var button: Dictionary = raw
		if (button["rect"] as Rect2).has_point(pos):
			return String(button["action"])
	return ""


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), DESK)
	_map_rect()
	# 地图本体
	draw_set_transform(map_origin, 0.0, Vector2(map_scale, map_scale))
	draw_rect(Rect2(Vector2.ZERO, WORLD), WATER)
	var land := DrawUtil.rounded_rect(Rect2(Vector2(110, 110), WORLD - Vector2(220, 220)), 72.0, 12)
	draw_colored_polygon(land, LAND)
	for river in rivers:
		if river.size() < 3:
			continue
		draw_colored_polygon(river, WATER)
		draw_polyline(DrawUtil.closed(river), WATER_EDGE, 4.0, true)
	if current_center.size() >= 2:
		var screen_points := PackedVector2Array()
		for p in current_center:
			screen_points.append(p)
		draw_polyline(screen_points, Color(INK, 0.55), 6.0 / maxf(map_scale, 0.1), true)
		for p in current_center:
			draw_circle(p, 4.0 / maxf(map_scale, 0.1), Color(INK, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 工具栏
	_buttons.clear()
	var cx := vp.x * 0.5
	_text_centered("地图编辑器 · 拖拽自由绘制河流", cx, 56.0, 34, INK)
	_text_centered("保存后会出现在模式选择的城市列表里；分享码通过剪贴板交换",
		cx, 94.0, 20, MUTED)
	var labels := [
		{"action": "new", "text": "新建"},
		{"action": "undo", "text": "撤销"},
		{"action": "clear", "text": "清空"},
		{"action": "width_minus", "text": "河宽 -"},
		{"action": "width_plus", "text": "河宽 +"},
		{"action": "save", "text": "保存"},
		{"action": "share", "text": "分享码"},
		{"action": "upload", "text": "上传大厅"},
		{"action": "import", "text": "导入"},
		{"action": "back", "text": "返回"},
	]
	var button_size := Vector2(180.0, 70.0)
	var gap := 14.0
	var per_row := 5
	var total := button_size.x * per_row + gap * (per_row - 1)
	var start_x := cx - total * 0.5
	for i in labels.size():
		var row := i / per_row
		var col := i % per_row
		var rect := Rect2(Vector2(start_x + float(col) * (button_size.x + gap),
			112.0 + float(row) * (button_size.y + 14.0)), button_size)
		_buttons.append({"rect": rect, "action": String(labels[i]["action"])})
		var hovered := rect.has_point(get_global_mouse_position())
		var poly := DrawUtil.rounded_rect(rect, 14.0, 8)
		draw_colored_polygon(poly, Color(PAPER, 0.96) if hovered else Color(PAPER, 0.82))
		draw_polyline(DrawUtil.closed(poly), Color(0.55, 0.52, 0.47, 0.7), 1.5, true)
		_text_centered(String(labels[i]["text"]), rect.position.x + rect.size.x * 0.5,
			rect.position.y + 46.0, 26, INK)
	_text_centered("河宽 %d px · 已画 %d 条河" % [int(width), rivers.size()],
		cx, vp.y - 34.0, 20, MUTED)
	if _toast != "":
		_text_centered(_toast, cx, vp.y - 76.0, 22, Color(INK, 0.9))


func _text_centered(text: String, center_x: float, baseline_y: float, size: int,
		color: Color) -> void:
	if _font == null:
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(_font, Vector2(center_x - w * 0.5, baseline_y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
