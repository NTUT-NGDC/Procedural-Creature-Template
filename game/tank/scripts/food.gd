class_name Food
extends Node2D
## 飼料：發光的小圓點，浮在水裡、被水流輕輕帶著飄（不會往下沉）。分小顆和大顆，大顆算好幾個。
## 生物的頭碰到（或觸手抓到）就被吃掉。由生態缸（tank.gd）產生，不用自己放進場景。

## 小顆、大顆的半徑（像素）
const RADIUS: float = 6.0
const BIG_RADIUS: float = 10.0
## 被水流帶著走的比例
const FLOW_FOLLOW: float = 0.5

## 顏色
var color: Color = Color("#ffd84d")
## 吃到算幾個（小顆 1，大顆看平衡資料的 big_food_value）
var value: int = 1
## 半徑：小顆 RADIUS，大顆 BIG_RADIUS（生態缸放的時候設好）
var radius: float = RADIUS
## 地板的高度（全局 y）：飄到這裡就擋住
var floor_y: float = 690.0
## 左右的範圍（全局 x），飄出去會被擋回來
var min_x: float = 0.0
var max_x: float = 1280.0
## 幾秒之後才能吃（生物掉出來的飼料，不然撞到的那隻馬上又吃回去）
var wait: float = 0.0

var _time: float = 0.0


func _ready() -> void:
	if wait <= 0.0:
		add_to_group("food")  # 生態缸、觸手用這個群組找能吃的飼料
	_time = randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	if wait > 0.0:
		wait -= delta
		if wait <= 0.0:
			add_to_group("food")
	modulate.a = 0.5 if wait > 0.0 else 1.0  # 還不能吃：淡一點
	# 浮在水裡，被水流輕輕帶著飄；飄到邊上就擋住
	global_position += WaterFlow.at(global_position) * FLOW_FOLLOW * delta
	global_position.x = clampf(global_position.x, min_x + radius, max_x - radius)
	global_position.y = clampf(global_position.y, radius, floor_y)
	queue_redraw()


func _draw() -> void:
	var glow: float = 1.8 + sin(_time * 3.0) * 0.3
	FastDraw.circle(self, Vector2.ZERO, radius * glow, Color(color, 0.2))
	FastDraw.circle(self, Vector2.ZERO, radius, color)
	FastDraw.circle(self, Vector2(-radius, -radius) / 3.0, radius * 0.35, Color(1, 1, 1, 0.6))


## Creature.eat() 會呼叫這個：被吃掉就消失
func on_eaten(_creature: Creature) -> void:
	remove_from_group("food")
	queue_free()
