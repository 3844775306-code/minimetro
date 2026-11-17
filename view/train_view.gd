class_name TrainView
extends Node2D
## 列车表现：纸色描边的圆角胶囊车身，沿线路弧长采样位置 + 切线朝向。
## 纸色描边让列车从同色线路里"抠"出来，始终可辨认。

const BODY := Vector2(40.0, 18.0)
const OUTLINE := 3.0
const PAPER := Color("#F3EFE6")

var _line_color := Color.WHITE
var _drawn_color := Color.TRANSPARENT


func update_from(train: Train, line: MetroLine) -> void:
	var xf := line.geometry.sample(train.dist)
	position = xf.origin
	rotation = xf.x.angle()
	if line.color != _drawn_color:
		_drawn_color = line.color
		queue_redraw()


func _draw() -> void:
	_capsule(Vector2.ZERO, BODY + Vector2(OUTLINE * 2.0, OUTLINE * 2.0), PAPER)
	_capsule(Vector2.ZERO, BODY, _drawn_color)
	# 车顶浅色带：提示车头朝向
	draw_line(Vector2(-11.0, -4.5), Vector2(9.0, -4.5), Color(1.0, 1.0, 1.0, 0.42), 4.0, true)


func _capsule(center: Vector2, size: Vector2, color: Color) -> void:
	var half := size * 0.5
	var radius := half.y
	var a := center - Vector2(half.x - radius, 0.0)
	var b := center + Vector2(half.x - radius, 0.0)
	draw_line(a, b, color, size.y, true)
	draw_circle(a, radius, color, true, -1.0, true)
	draw_circle(b, radius, color, true, -1.0, true)
