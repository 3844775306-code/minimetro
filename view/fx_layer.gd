class_name FxLayer
extends Node2D
## 轻量反馈特效：送达飘字、超载扩散环。
## 用列表 + 集中 _draw 实现，不产生/销毁节点，帧开销稳定。

const INK := Color("#2B2B2B")
const WARN := Color("#D64545")

var font: Font = null
var _texts: Array[Dictionary] = []
var _rings: Array[Dictionary] = []


func _ready() -> void:
	font = UiFonts.get_font()


## 送达 N 名乘客：在站点上方飘出 "+N"。
func spawn_delivery(pos: Vector2, count: int) -> void:
	if count <= 0:
		return
	_texts.append({
		"pos": pos + Vector2(0.0, -34.0),
		"age": 0.0,
		"life": 1.0,
		"text": "+%d" % count,
	})


## 站点开始超载：向外扩散的红环。
func spawn_overload(pos: Vector2) -> void:
	_rings.append({"pos": pos, "age": 0.0, "life": 1.1})


func _process(delta: float) -> void:
	var index := _texts.size() - 1
	while index >= 0:
		_texts[index]["age"] = float(_texts[index]["age"]) + delta
		if float(_texts[index]["age"]) >= float(_texts[index]["life"]):
			_texts.remove_at(index)
		index -= 1
	index = _rings.size() - 1
	while index >= 0:
		_rings[index]["age"] = float(_rings[index]["age"]) + delta
		if float(_rings[index]["age"]) >= float(_rings[index]["life"]):
			_rings.remove_at(index)
		index -= 1
	queue_redraw()


func _draw() -> void:
	if font == null:
		return
	for item in _texts:
		var t: float = float(item["age"]) / float(item["life"])
		var alpha := 1.0 - t
		var pos: Vector2 = item["pos"] + Vector2(0.0, -40.0 * t)
		var text: String = item["text"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
		draw_string(font, pos - Vector2(width * 0.5, 0.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(INK, alpha))
	for item in _rings:
		var t: float = float(item["age"]) / float(item["life"])
		var radius := 30.0 + 44.0 * t
		draw_arc(item["pos"], radius, 0.0, TAU, 48, Color(WARN, 0.7 * (1.0 - t)), 3.0, true)
