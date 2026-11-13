@tool
class_name TankWater
extends Node2D
## 生態缸的水：底色、從上面照下來的光、慢慢飄的水紋、往上冒的氣泡，最下面是沙地。
## 放了背景圖就畫背景圖。顏色和背景圖由生態缸（Tank）的「外觀」屬性設定。

## 水的顏色
@export var water_color: Color = Color("#123c46"):
	set(value):
		water_color = value
		queue_redraw()
## 沙地的顏色
@export var sand_color: Color = Color("#6b5a3e"):
	set(value):
		sand_color = value
		queue_redraw()
## 沙地的高度（像素）
@export_range(0, 200, 1) var sand_height: float = 30.0:
	set(value):
		sand_height = value
		queue_redraw()
## 背景圖：放了就蓋過水的顏色（光、水紋和氣泡還是會畫）
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


## 畫面大小（1280 × 720）
static func screen_size() -> Vector2:
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))


func _draw() -> void:
	var size: Vector2 = screen_size()
	if background != null:
		draw_texture_rect(background, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), water_color)
	_draw_light(size)
	_draw_ripples(size)
	_draw_bubbles(size)
	if background == null and sand_height > 0.0:
		draw_rect(Rect2(0, size.y - sand_height, size.x, sand_height), sand_color)
		draw_line(Vector2(0, size.y - sand_height), Vector2(size.x, size.y - sand_height), sand_color.lightened(0.2), 3.0)


## 光：幾道從水面斜斜照下來的淡淡光柱，慢慢晃
func _draw_light(size: Vector2) -> void:
	for i: int in 5:
		var x: float = size.x * (i + 0.5) / 5.0 + sin(_time * 0.3 + i * 1.7) * 40.0
		var width: float = 60.0 + (i % 3) * 30.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - width / 2, 0), Vector2(x + width / 2, 0), Vector2(x + width + 80, size.y), Vector2(x + 80, size.y)]), Color(1, 1, 1, 0.025))


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
