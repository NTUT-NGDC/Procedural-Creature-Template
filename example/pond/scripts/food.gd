extends Node2D
## 池塘裡的食物：發光的小圓點，慢慢飄。被玩家的頭碰到就被吃掉，換到隨機的地方重生。
## 「食物會逃跑」打開時，玩家靠近會躲開。
##
## 由池塘（pond.gd）產生，屬性也由池塘設定，不用自己放進場景。

## 食物的半徑（像素）
const RADIUS: float = 7.0
## 平常飄的速度、逃跑的速度（像素／秒）
const DRIFT_SPEED: float = 20.0
const FLEE_SPEED: float = 130.0
## 玩家多近時開始逃跑、重生時至少離玩家多遠
const FLEE_RANGE: float = 160.0
const RESPAWN_DISTANCE: float = 200.0

## 顏色
var color: Color = Color("#ffd84d")
## 會不會躲開玩家
var flees: bool = false
## 玩家（要躲的對象、只有他吃得到）
var player: Creature

var _velocity: Vector2 = Vector2.ZERO
var _area: Area2D
var _time: float = 0.0


func _ready() -> void:
	add_to_group("food")
	_velocity = Vector2.from_angle(randf() * TAU) * DRIFT_SPEED
	_time = randf() * 10.0
	# 碰撞區：在「食物」層，只偵測「玩家」層
	_area = Area2D.new()
	_area.collision_layer = 4
	_area.collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	_area.add_child(shape)
	add_child(_area)
	_area.area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	_time += delta
	if flees and player != null and global_position.distance_to(player.global_position) < FLEE_RANGE:
		_velocity = player.global_position.direction_to(global_position) * FLEE_SPEED
	elif _velocity.length() > DRIFT_SPEED:
		_velocity = _velocity.normalized() * lerpf(_velocity.length(), DRIFT_SPEED, 1.0 - exp(-2.0 * delta))
	global_position += _velocity * delta
	_bounce_inside_screen()
	queue_redraw()


func _draw() -> void:
	var glow: float = 1.8 + sin(_time * 3.0) * 0.3
	draw_circle(Vector2.ZERO, RADIUS * glow, Color(color, 0.2), true, -1.0, true)
	draw_circle(Vector2.ZERO, RADIUS, color, true, -1.0, true)
	draw_circle(Vector2(-2, -2), RADIUS * 0.35, Color(1, 1, 1, 0.6), true, -1.0, true)


## 碰到畫面邊緣就反彈
func _bounce_inside_screen() -> void:
	var area: Rect2 = get_viewport_rect().grow(-RADIUS)
	if global_position.x < area.position.x or global_position.x > area.end.x:
		_velocity.x = -_velocity.x
	if global_position.y < area.position.y or global_position.y > area.end.y:
		_velocity.y = -_velocity.y
	global_position = global_position.clamp(area.position, area.end)


## 玩家的頭碰到就吃掉（身體碰到不算）
func _on_area_entered(area: Area2D) -> void:
	if player != null and area == player.head_area and is_in_group("food"):
		player.eat(self)


## Creature.eat() 會呼叫這個：換到隨機的地方重生
func on_eaten(_creature: Creature) -> void:
	respawn()


## 換到畫面上隨機的地方，離玩家遠一點
func respawn() -> void:
	var area: Rect2 = get_viewport_rect().grow(-40.0)
	for i: int in 20:
		global_position = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		if player == null or global_position.distance_to(player.global_position) > RESPAWN_DISTANCE:
			break
	_velocity = Vector2.from_angle(randf() * TAU) * DRIFT_SPEED
	add_to_group("food")  # 觸手吃的時候會先移出群組，重生後加回來
