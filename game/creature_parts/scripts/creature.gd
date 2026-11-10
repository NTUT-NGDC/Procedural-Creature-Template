@tool
class_name Creature
extends Node2D
## 生物本體：負責移動、吃東西變長、被咬變短。節點的位置就是「頭」。
## 本身不畫東西、不旋轉；身體、腳、觸手、眼睛、掛件都是加在它底下的零件。
##
## 用法：新增一個 Creature 節點，底下加一個 ChainBody 當身體，再加其他零件。
## 在編輯器裡看到的是「預覽姿勢」：頭朝右，身體往左拉直。按 F5 執行才會動。

## 吃到東西變長時發出，level 是成長後的等級
signal grew(level: int)
## 被咬（變短）時發出
signal hurt()
## 長度短到剩 2 時發出（被吃掉了）
signal died()
## 吃掉一個食物時發出（用頭吃、用觸手抓都算），在 grew 之前
signal ate(food: Node)

## 長度最少是多少，到這裡就算死掉
const MIN_LENGTH: int = 2
## 每隻生物一開始的長度（遊戲裡的長度＝這個數字＋等級，見 get_length()）
const START_LENGTH: int = 10

## 控制方式的編號，跟下面「控制方式」選單的順序一樣
enum Mode { MOUSE, WASD, WANDER, CHASE, FLEE }

@export_group("動作")
## 誰在控制這隻生物。漫遊、追玩家、躲玩家是電腦控制
@export_enum("玩家（滑鼠）", "玩家（WASD）", "漫遊", "追玩家", "躲玩家") var control_mode: int = Mode.MOUSE:
	set(value):
		control_mode = value
		_update_player_group()
## 移動速度（像素／秒）
@export_range(0, 1000, 10) var speed: float = 240.0
## 轉向速度（度／秒）：越小轉彎越大、越像在游
@export_range(30, 1080, 10, "radians_as_degrees") var turn_speed: float = deg_to_rad(270.0)
## 偵測距離（像素）：電腦控制時，玩家多近會被發現
@export_range(0, 1000, 10) var detect_range: float = 250.0

@export_group("形狀")
## 頭的碰撞半徑（像素）：吃東西、被咬都用這個圓判斷
@export_range(2, 100, 1) var head_radius: float = 14.0:
	set(value):
		head_radius = value
		if _head_shape != null:
			_head_shape.radius = value

## 現在的速度向量（像素／秒）
var velocity: Vector2 = Vector2.ZERO
## 頭朝向的角度（弧度），0 是朝右
var heading: float = 0.0
## 成長等級：吃一次 +1、被咬一次 -N
var level: int = 0

## 頭的碰撞區（執行時才建立）
var head_area: Area2D
var _head_shape: CircleShape2D
## 現在的移動速度（會慢慢加速、減速）
var _current_speed: float = 0.0
## 漫遊：多久之後換方向、要往哪個方向
var _wander_timer: float = 0.0
var _wander_angle: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_wander_angle = heading
	_update_player_group()
	_create_head_area()
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var target: Dictionary = _get_move_target()
	_steer(target.angle, target.speed, delta)


## 回傳這一幀想往哪個角度走、想走多快：{"angle": 弧度, "speed": 像素／秒}
func _get_move_target() -> Dictionary:
	match control_mode:
		Mode.MOUSE:
			var to_mouse: Vector2 = get_global_mouse_position() - global_position
			# 滑鼠就在頭上：停下來、不轉頭，不然會原地打轉、身體捲成一團
			if to_mouse.length() < head_radius:
				return {"angle": heading, "speed": 0.0}
			# 離滑鼠越近走越慢，不然會在滑鼠旁邊一直繞圈
			return {"angle": to_mouse.angle(), "speed": speed * clampf((to_mouse.length() - head_radius) / 80.0, 0.0, 1.0)}
		Mode.WASD:
			var input: Vector2 = _read_wasd()
			return {"angle": input.angle() if input != Vector2.ZERO else heading, "speed": speed if input != Vector2.ZERO else 0.0}
		Mode.CHASE, Mode.FLEE:
			var player: Creature = _find_player()
			if player != null and global_position.distance_to(player.global_position) < detect_range:
				var to_player: float = (player.global_position - global_position).angle()
				return {"angle": to_player if control_mode == Mode.CHASE else to_player + PI, "speed": speed}
	return {"angle": _wander(), "speed": speed * 0.6}


## 轉向目標角度（每秒最多轉 turn_speed）、往前走，最後留在畫面裡
func _steer(target_angle: float, target_speed: float, delta: float) -> void:
	var max_turn: float = turn_speed * delta
	heading += clampf(angle_difference(heading, target_angle), -max_turn, max_turn)
	_current_speed = lerpf(_current_speed, target_speed, 1.0 - exp(-8.0 * delta))
	velocity = Vector2.from_angle(heading) * _current_speed
	global_position += velocity * delta
	var area: Rect2 = _get_screen_rect()
	global_position = global_position.clamp(area.position, area.end)


## 漫遊：每隔 1～3 秒隨機換個方向；靠近畫面邊緣就轉回中間
func _wander() -> float:
	_wander_timer -= get_process_delta_time()
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.0, 3.0)
		_wander_angle = heading + randf_range(-PI / 2.0, PI / 2.0)
	var area: Rect2 = _get_screen_rect().grow(-80.0)
	if not area.has_point(global_position):
		_wander_angle = (area.get_center() - global_position).angle()
	return _wander_angle


func _read_wasd() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	return input


## 找最近的玩家生物（玩家控制的生物會自動加進 "player" 群組）
func _find_player() -> Creature:
	var nearest: Creature = null
	for node: Node in get_tree().get_nodes_in_group("player"):
		var other: Creature = node as Creature
		if other == null or other == self:
			continue
		if nearest == null or global_position.distance_to(other.global_position) < global_position.distance_to(nearest.global_position):
			nearest = other
	return nearest


## 畫面範圍（全局座標），有攝影機時跟著攝影機
func _get_screen_rect() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()


func _update_player_group() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	if control_mode == Mode.MOUSE or control_mode == Mode.WASD:
		add_to_group("player")
	else:
		remove_from_group("player")


func _create_head_area() -> void:
	head_area = Area2D.new()
	head_area.name = "HeadArea"
	head_area.set_meta("creature", self)
	_head_shape = CircleShape2D.new()
	_head_shape.radius = head_radius
	var shape := CollisionShape2D.new()
	shape.shape = _head_shape
	head_area.add_child(shape)
	add_child(head_area)


# ---------------------------------------------------------------- 對外的功能


## 長大：等級 +amount，通知所有零件（身體會變長），發出 grew 訊號
func grow(amount: int = 1) -> void:
	level += amount
	_notify_parts()
	grew.emit(level)


## 吃掉一個食物：通知食物「被吃了」（食物有 on_eaten() 的話），發出 ate，再長大 1
func eat(food: Node) -> void:
	if food.has_method("on_eaten"):
		food.call("on_eaten", self)
	ate.emit(food)
	grow(1)


## 換腳協調：另一組有腳在空中時回傳 false（group 這組的腳先等一下）。
## 腳分 A、B 兩組輪流走，看起來才像真的在走路
func can_step(group: int) -> bool:
	for node: Node in find_children("*", "", true, false):
		if node is IKLeg and (node as IKLeg).is_group_stepping(1 - group):
			return false
	return true


## 變短：等級 -amount，通知所有零件，發出 hurt 訊號；長度短到剩 2 時再發出 died
func shrink(amount: int = 1) -> void:
	level -= amount
	_notify_parts()
	hurt.emit()
	if get_length() <= MIN_LENGTH:
		died.emit()


## 遊戲裡的「長度」：每隻生物都從 START_LENGTH 開始，吃一個 +1、被咬 -N。
## 跟身體有幾節無關，身體短的生物（章魚、水母）才不會一下就輸
func get_length() -> int:
	return maxi(START_LENGTH + level, MIN_LENGTH)


## 身體（第一個 ChainBody 子節點），沒有就是 null
func get_body() -> ChainBody:
	for child: Node in get_children():
		if child is ChainBody:
			return child
	return null


## 把姿勢擺回「預覽姿勢」：身體往頭的反方向拉直、腳放在理想落腳點、觸手拉直。
## 把生物瞬間移到別的地方之後要呼叫，不然身體會從原本的位置被拖過來
func reset_pose() -> void:
	for node: Node in find_children("*", "", true, false):
		if node.has_method("reset_pose"):
			node.call("reset_pose")


## 設定所有碰撞區（頭、身體）的碰撞層和遮罩。池塘用這個區分玩家、天敵
func set_collision(layer: int, mask: int) -> void:
	for node: Node in find_children("*", "Area2D", true, false):
		var area: Area2D = node as Area2D
		area.collision_layer = layer
		area.collision_mask = mask


func _notify_parts() -> void:
	for node: Node in find_children("*", "", true, false):
		if node.has_method("on_grow"):
			node.call("on_grow", level)
