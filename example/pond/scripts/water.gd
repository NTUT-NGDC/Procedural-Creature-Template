@tool
extends Node2D
## 池塘的水面：底色，加上慢慢飄的水紋和往上冒的氣泡。放了背景圖就畫背景圖。
## 顏色和背景圖由池塘（Pond）的「外觀」屬性設定。

## 水的顏色
@export var water_color: Color = Color("#123c46"):
	set(value):
		water_color = value
		queue_redraw()
## 背景圖：放了就蓋過水的顏色（水紋和氣泡還是會畫）
@export var background: Texture2D:
	set(value):
		background = value
		queue_redraw()

var _time: float = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	var size: Vector2 = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	if background != null:
		draw_texture_rect(background, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), water_color)
	_draw_ripples(size)
	_draw_bubbles(size)


## 水紋：十幾個淡淡的弧線，慢慢往右飄
func _draw_ripples(size: Vector2) -> void:
	var ripple_color: Color = Color(water_color.lightened(0.5), 0.12)
	for i: int in 14:
		var x: float = fposmod(i * 97.3 + _time * 8.0 * (1 + i % 3), size.x + 80.0) - 40.0
		var y: float = fposmod(i * 153.1, size.y) + sin(_time * 0.4 + i) * 12.0
		var radius: float = 18.0 + (i % 4) * 8.0
		draw_arc(Vector2(x, y), radius, PI * 1.1, PI * 1.9, 12, ripple_color, 2.0, true)


## 氣泡：小圓圈從下面慢慢往上冒，左右晃
func _draw_bubbles(size: Vector2) -> void:
	var bubble_color: Color = Color(1, 1, 1, 0.15)
	for i: int in 10:
		var y: float = size.y - fposmod(_time * 18.0 * (1 + i % 2) + i * 73.0, size.y + 20.0)
		var x: float = fposmod(i * 131.7, size.x) + sin(_time * 1.3 + i) * 6.0
		draw_arc(Vector2(x, y), 3.0 + (i % 3), 0.0, TAU, 12, bubble_color, 1.0, true)
