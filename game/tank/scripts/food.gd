class_name Food
extends Node2D
## 飼料：發光的小圓點，慢慢往下沉，被水流帶著走，沉到底就停在地上。
## 生物的頭碰到（或觸手抓到）就被吃掉。由生態缸（tank.gd）產生，不用自己放進場景。

## 半徑（像素）
const RADIUS: float = 6.0
## 往下沉的速度（像素／秒）
const SINK_SPEED: float = 16.0
## 被水流帶著走的比例
const FLOW_FOLLOW: float = 0.8

## 顏色
var color: Color = Color("#ffd84d")
## 地板的高度（全局 y）：沉到這裡就停
var floor_y: float = 690.0
## 左右的範圍（全局 x），飄出去會被擋回來
var min_x: float = 0.0
var max_x: float = 1280.0

var _time: float = 0.0


func _ready() -> void:
	add_to_group("food")
	_time = randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	if global_position.y < floor_y:
		# 在水裡：往下沉、被水流帶著走
		global_position += (WaterFlow.at(global_position) * FLOW_FOLLOW + Vector2(0, SINK_SPEED)) * delta
	global_position.x = clampf(global_position.x, min_x + RADIUS, max_x - RADIUS)
	global_position.y = minf(global_position.y, floor_y)
	queue_redraw()


func _draw() -> void:
	var glow: float = 1.8 + sin(_time * 3.0) * 0.3
	draw_circle(Vector2.ZERO, RADIUS * glow, Color(color, 0.2), true, -1.0, true)
	draw_circle(Vector2.ZERO, RADIUS, color, true, -1.0, true)
	draw_circle(Vector2(-2, -2), RADIUS * 0.35, Color(1, 1, 1, 0.6), true, -1.0, true)


## Creature.eat() 會呼叫這個：被吃掉就消失
func on_eaten(_creature: Creature) -> void:
	remove_from_group("food")
	queue_free()
