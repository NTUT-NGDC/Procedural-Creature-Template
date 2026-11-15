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
## 加速消耗了一個飼料時發出，at 是身體尾端（生態缸在這裡放一個飼料）
signal boost_spent(at: Vector2)

## 長度最少是多少，到這裡就算死掉
const MIN_LENGTH: int = 2
## 每隻生物一開始的長度（遊戲裡的長度＝這個數字＋等級，見 get_length()）
const START_LENGTH: int = 10
## 水流推生物的比例（生物自己會游，只被推一點點）
const FLOW_DRIFT: float = 0.3
## 電腦控制的大腦多久想一次（秒）
const BRAIN_INTERVAL: float = 0.1

## 控制方式的編號，跟下面「控制方式」選單的順序一樣
enum Mode { MOUSE, WASD, WANDER }

## 設計檔：拖一份 design.tres 進來，身體和零件會自己長出來（不用自己加節點）。
## 自己長出來的節點不會存進場景檔，改了設計檔就會跟著變
@export var design: CreatureDesign:
	set(value):
		design = value
		if is_inside_tree():
			apply_design()

@export_group("動作")
## 誰在控制這隻生物。漫遊是電腦控制
@export_enum("玩家（滑鼠）", "玩家（WASD）", "漫遊") var control_mode: int = Mode.MOUSE:
	set(value):
		control_mode = value
		_update_player_group()
## 移動速度（像素／秒）
@export_range(0, 1000, 10) var speed: float = 240.0
## 轉向速度（度／秒）：越小轉彎越大、越像在游
@export_range(30, 1080, 10, "radians_as_degrees") var turn_speed: float = deg_to_rad(270.0)

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
## 這一級吃了幾個（有設計檔的生物，吃滿「升一級要吃幾個」就升級）
var food_progress: int = 0

## 頭的碰撞區（執行時才建立）
var head_area: Area2D
var _head_shape: CircleShape2D
## 現在的移動速度（會慢慢加速、減速）
var _current_speed: float = 0.0
## 漫遊：多久之後換方向、要往哪個方向
var _wander_timer: float = 0.0
var _wander_angle: float = 0.0
## 電腦控制的「大腦」：有設定的話，每一幀問它要往哪走（回傳跟 _get_move_target() 一樣的字典，
## 回傳空的字典就照控制方式走）。生態缸的 NPC 用 game/tank/scripts/npc_brain.gd
## 大腦每 BRAIN_INTERVAL 秒想一次（一秒 10 次就夠了），中間照上一次的決定走
var brain: Callable
## 還要等多久才再想一次（每隻一開始隨機，才不會全部擠在同一幀想）
var _brain_wait: float = randf() * BRAIN_INTERVAL
## 大腦上一次的決定
var _brain_decision: Dictionary = {}
## 最高幾級（-1 是沒有上限）：到了就不會再長大。生態缸的 NPC 用
var max_level: int = -1
## 無敵還剩幾秒：撞到別人、被別人撞都沒事，身體一閃一閃
var invincible_time: float = 0.0
## 被彈開的速度（像素／秒），會慢慢變小
var knockback: Vector2 = Vector2.ZERO
## 生態缸的玩家操作（像 Slither）：一直全速往前衝、滑鼠或方向鍵只管方向；
## 按住任何鍵、滑鼠左鍵或右鍵加速。生態缸會打開；工坊、沙盒維持「跟著滑鼠、會停」、不能加速
var tank_controls: bool = false
## 這一幀有沒有在加速
var boosting: bool = false
## 現在按住的鍵（加速用：按住任何鍵都算）
var _held_keys: Dictionary = {}
## 加速累積消耗了多少飼料（滿 1 個就真的扣掉一個）
var _boost_spent: float = 0.0
## 可以游的範圍（全局座標）。空的就是畫面範圍；生態缸會設成整張地圖
var bounds: Rect2 = Rect2()
## 平衡資料：體型、能力的係數。空的就用預設的 balance.tres
var balance: CreatureBalance
## 現在的形狀：設計檔照現在的等級長大後的樣子（CreatureGrowth.shape_at() 的結果）。沒有設計檔是 null
var shape: CreatureDesign
## 所有的腳（_get_legs() 用），_legs_dirty 是「零件變了，要重找」
var _legs: Array[IKLeg] = []
var _legs_dirty: bool = true
## 現在的能力（apply_design() 時算好）
var _stats: CreatureStats
## 依設計檔長出來的節點：身體、零件（順序跟 shape.all_parts() 一樣）
var _built_body: ChainBody
var _built_parts: Array[Node] = []
## 長出來時的「結構」（零件數量、左右、圖）。結構沒變就只更新屬性，不重長
var _built_structure: String = ""
## 身體的圖現在讀的是哪幾個檔（檔名沒變就不重讀）
var _body_image_key: String = ""


func _ready() -> void:
	apply_design()
	if Engine.is_editor_hint():
		return
	add_to_group("creature")  # 生態缸、水草用這個找所有生物
	_wander_angle = heading
	_update_player_group()
	_create_head_area()
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_brain_wait -= delta
	var target: Dictionary = _get_move_target()
	_update_boost(target.get("boost", false), delta)
	_steer(target.angle, target.speed * (get_balance().boost_speed if boosting else 1.0), delta)
	_update_invincible(delta)


## 回傳這一幀想往哪個角度走、想走多快、要不要加速：{"angle": 弧度, "speed": 像素／秒, "boost": 要不要加速}
func _get_move_target() -> Dictionary:
	if brain.is_valid():
		if _brain_wait <= 0.0:
			_brain_wait = BRAIN_INTERVAL
			_brain_decision = brain.call()
		if not _brain_decision.is_empty():
			return _brain_decision
	match control_mode:
		Mode.MOUSE:
			var to_mouse: Vector2 = get_global_mouse_position() - global_position
			if tank_controls:  # 一直全速往前，滑鼠只管方向
				return {"angle": to_mouse.angle() if to_mouse.length() > head_radius else heading, "speed": speed, "boost": _read_boost()}
			# 滑鼠就在頭上：停下來、不轉頭，不然會原地打轉、身體捲成一團
			if to_mouse.length() < head_radius:
				return {"angle": heading, "speed": 0.0}
			# 離滑鼠越近走越慢，不然會在滑鼠旁邊一直繞圈
			return {"angle": to_mouse.angle(), "speed": speed * clampf((to_mouse.length() - head_radius) / 80.0, 0.0, 1.0), "boost": _read_boost()}
		Mode.WASD:
			var input: Vector2 = _read_wasd()
			if tank_controls:  # 放開方向鍵也照樣往前衝
				return {"angle": input.angle() if input != Vector2.ZERO else heading, "speed": speed, "boost": _read_boost()}
			return {"angle": input.angle() if input != Vector2.ZERO else heading, "speed": speed if input != Vector2.ZERO else 0.0, "boost": _read_boost()}
	return {"angle": _wander(), "speed": speed * 0.6}


## 轉向目標角度（每秒最多轉 turn_speed）、往前走，最後留在範圍裡
func _steer(target_angle: float, target_speed: float, delta: float) -> void:
	var max_turn: float = turn_speed * delta
	heading += clampf(angle_difference(heading, target_angle), -max_turn, max_turn)
	_current_speed = lerpf(_current_speed, target_speed, 1.0 - exp(-8.0 * delta))
	velocity = Vector2.from_angle(heading) * _current_speed + knockback
	knockback *= exp(-6.0 * delta)  # 彈開的速度慢慢變小
	global_position += velocity * delta
	global_position += WaterFlow.at(global_position) * FLOW_DRIFT * delta  # 被水流推一點點
	var area: Rect2 = get_bounds()
	global_position = global_position.clamp(area.position, area.end)


## 漫遊：每隔 1～3 秒隨機換個方向；靠近邊緣就轉回中間
func _wander() -> float:
	_wander_timer -= get_process_delta_time()
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.0, 3.0)
		_wander_angle = heading + randf_range(-PI / 2.0, PI / 2.0)
	var area: Rect2 = get_bounds().grow(-80.0)
	if not area.has_point(global_position):
		_wander_angle = (area.get_center() - global_position).angle()
	return _wander_angle


## 加速（像 Slither）：每秒消耗 boost_cost 個飼料，消耗的從尾巴掉出去。
## 這一級吃到一半的用完了，就掉一級（身體變小）、從上一級的滿格繼續扣，一直噴到 0 級、一個都不剩才停
func _update_boost(want: bool, delta: float) -> void:
	boosting = want and can_boost()
	if not boosting:
		return
	_boost_spent += get_balance().boost_cost * delta
	while _boost_spent >= 1.0 and can_boost():
		_boost_spent -= 1.0
		if food_progress <= 0:
			_shrink_one_level()
		food_progress -= 1
		var body: ChainBody = get_body()
		boost_spent.emit(body.get_joint(body.joint_count() - 1) if body != null else global_position)


## 還能不能加速：還有吃到一半的飼料，或還沒到 0 級
func can_boost() -> bool:
	return shape != null and (food_progress > 0 or level > 0)


## 加速把這一級用完了：掉一級，進度變成上一級的滿格
func _shrink_one_level() -> void:
	level -= 1
	apply_design()
	_notify_parts()
	food_progress = get_stats().level_cost


## 玩家按住任何鍵、滑鼠左鍵或右鍵就是要加速（只有生態缸的玩家可以加速）
func _read_boost() -> bool:
	if not tank_controls:
		return false
	return not _held_keys.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


## 記下按住了哪些鍵。Esc（暫停）、F1～F12 不算；用方向鍵操作時，方向鍵、WASD 也不算
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not tank_controls or key == null or key.echo:
		return
	var code: Key = key.physical_keycode
	if code == KEY_ESCAPE or (code >= KEY_F1 and code <= KEY_F12):
		return
	if control_mode == Mode.WASD and code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return
	if key.pressed:
		_held_keys[code] = true
	else:
		_held_keys.erase(code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_held_keys.clear()  # 切到別的視窗時放開的鍵收不到，先全部當作放開


## 無敵時間倒數，無敵時一閃一閃
func _update_invincible(delta: float) -> void:
	if invincible_time <= 0.0:
		return
	invincible_time = maxf(invincible_time - delta, 0.0)
	modulate.a = 1.0 if invincible_time <= 0.0 or fmod(invincible_time, 0.25) > 0.125 else 0.35


func is_invincible() -> bool:
	return invincible_time > 0.0


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


## 可以游的範圍（全局座標）：有設定 bounds 就用它，不然是畫面範圍（有攝影機時跟著攝影機）
func get_bounds() -> Rect2:
	if bounds.has_area():
		return bounds
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
	var collision := CollisionShape2D.new()
	collision.shape = _head_shape
	head_area.add_child(collision)
	add_child(head_area)


# ---------------------------------------------------------------- 對外的功能


## 長大：等級 +amount。有設計檔的照長大方式變形狀；沒有的通知所有零件（身體會變長）。發出 grew 訊號
func grow(amount: int = 1) -> void:
	level += amount
	apply_design()
	_notify_parts()
	grew.emit(level)


## 吃掉一個食物：通知食物「被吃了」（食物有 on_eaten() 的話），發出 ate。
## 有設計檔的生物：吃滿「升一級要吃幾個」才長大一級（大顆飼料算好幾個，多的留到下一級）；
## 沒有設計檔的：吃一個就長大 1
func eat(food: Node) -> void:
	if food.has_method("on_eaten"):
		food.call("on_eaten", self)
	ate.emit(food)
	if shape == null:
		grow(1)
		return
	if max_level >= 0 and level >= max_level:
		return  # 已經最高級了：吃了也不會再長大
	food_progress += int(food.get("value")) if "value" in food else 1
	while food_progress >= get_stats().level_cost:
		food_progress -= get_stats().level_cost
		grow(1)
		if max_level >= 0 and level >= max_level:
			food_progress = 0
			return


## 掉級：最多掉到 0 級，回傳真的掉了幾級。這一級吃到一半的飼料也不見了
func lose_levels(amount: int) -> int:
	var lost: int = mini(amount, level)
	food_progress = 0
	if lost > 0:
		level -= lost
		apply_design()
		_notify_parts()
	hurt.emit()
	return lost


## 直接設定等級（重生時回到 0 級用），吃到一半的飼料歸零
func set_level(new_level: int) -> void:
	level = maxi(new_level, 0)
	food_progress = 0
	apply_design()
	_notify_parts()


## 換腳協調：另一組有腳在空中時回傳 false（group 這組的腳先等一下）。
## 腳分 A、B 兩組輪流走，看起來才像真的在走路
func can_step(group: int) -> bool:
	for leg: IKLeg in _get_legs():
		if leg.is_group_stepping(1 - group):
			return false
	return true


## 生物在不在畫面裡：不在的話藏起來、裝飾的動作（腳、觸手、眼睛、掛件）先停，省下畫圖和計算。
## 身體還是照常跟著頭走（吃東西、碰撞要用）；會抓食物的觸手也照常動。回到畫面時零件重擺姿勢
func set_on_screen(on_screen: bool) -> void:
	if visible == on_screen:
		return
	visible = on_screen
	for node: Node in find_children("*", "", true, false):
		var part: CreaturePart = node as CreaturePart
		if part == null or (part is Tentacle and (part as Tentacle).behavior == Tentacle.Behavior.GRAB_FOOD):
			continue
		part.process_mode = Node.PROCESS_MODE_INHERIT if on_screen else Node.PROCESS_MODE_DISABLED
		if on_screen:
			part.reset_pose()


## 這隻生物所有的腳（記起來，零件變了才重找；每一幀每隻腳都要問，一直重找很慢）
func _get_legs() -> Array[IKLeg]:
	if _legs_dirty:
		_legs.clear()
		for node: Node in find_children("*", "", true, false):
			if node is IKLeg:
				_legs.append(node as IKLeg)
		_legs_dirty = false
	return _legs


## 變短：等級 -amount，通知所有零件，發出 hurt 訊號；長度短到剩 2 時再發出 died
func shrink(amount: int = 1) -> void:
	level -= amount
	apply_design()
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


## 設定所有碰撞區（頭、身體）的碰撞層和遮罩
func set_collision(layer: int, mask: int) -> void:
	for node: Node in find_children("*", "Area2D", true, false):
		var area: Area2D = node as Area2D
		area.collision_layer = layer
		area.collision_mask = mask


# ---------------------------------------------------------------- 設計檔


## 依設計檔和現在的等級長出（或更新）身體和零件。改了設計檔的內容之後呼叫這個，生物就會變樣子。
## 零件數量、左右、圖沒變時只更新屬性；變了就整個重長，但身體維持原本的姿勢
func apply_design() -> void:
	if design == null:
		_clear_built()
		shape = null
		_stats = null
		return
	_legs_dirty = true
	shape = CreatureGrowth.shape_at(design, level, get_balance())
	_stats = CreatureStats.at_level(design, level, get_balance(), shape)
	_apply_abilities()
	var structure: String = _design_structure()
	if structure != _built_structure or not is_instance_valid(_built_body):
		var pose: PackedVector2Array = _built_body.get_joints() if is_instance_valid(_built_body) else PackedVector2Array()
		_clear_built()
		_build(pose)
		_built_structure = structure
	else:
		shape.body.apply_to(_built_body)
		var parts: Array[PartDesign] = shape.all_parts()
		for i: int in parts.size():
			parts[i].apply_to(_built_parts[i])
			if parts[i] is OrnamentDesign:
				_apply_image(_built_parts[i], parts[i])
	_apply_body_images()
	_sort_parts()


## 身體自己的圖（頭、每一節、尾巴）：檔名變了才重新讀
func _apply_body_images() -> void:
	var body_design: BodyDesign = shape.body
	var key: String = "|".join([body_design.head_image, body_design.segment_image, body_design.tail_image, shape.image_folder])
	if key == _body_image_key:
		return
	_body_image_key = key
	_built_body.head_texture = shape.load_image(body_design.head_image)
	_built_body.segment_texture = shape.load_image(body_design.segment_image)
	_built_body.tail_texture = shape.load_image(body_design.tail_image)
	_built_body.queue_redraw()


## 零件的上下順序：掛得越靠尾巴越先畫（在下面），越靠頭越後畫（在上面）；眼睛永遠在最上面。
## 掛在同一節的零件維持設計檔裡的順序
func _sort_parts() -> void:
	var order: Array[int] = []
	for i: int in _built_parts.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var layer_a: int = _part_layer(_built_parts[a])
		var layer_b: int = _part_layer(_built_parts[b])
		return layer_a > layer_b if layer_a != layer_b else a < b)
	for i: int in order:
		_built_body.move_child(_built_parts[i], -1)


## 排順序用：掛在第幾節（-1 換成真正的最後一節）。眼睛是 -1，排在最後面（最上面）
func _part_layer(part: Node) -> int:
	if part is Eyes:
		return -1
	return _built_body.resolve_index(part.get("attach_segment"))


## 長出身體，再把零件一個一個加在身體上。節點不設 owner，所以不會存進場景檔。
## pose 是重長前身體的關節，有的話身體維持原本的姿勢（長大時才不會突然拉直）
func _build(pose: PackedVector2Array) -> void:
	_built_body = ChainBody.new()
	_built_body.name = "Body"
	_built_body.segments_per_growth = 0  # 長大由長大方式決定，身體自己不加節
	add_child(_built_body)
	shape.body.apply_to(_built_body)
	if not pose.is_empty() and not Engine.is_editor_hint():
		_built_body.set_joints(pose)
	for part: PartDesign in shape.all_parts():
		var node: Node2D = _new_part_node(part)
		if part is OrnamentDesign:
			# 掛件「兩邊」要在加進場景前就有圖，右邊才會複製一份
			part.apply_to(node)
			_add_image(node, part)
			_built_body.add_child(node)
		else:
			_built_body.add_child(node)
			part.apply_to(node)
		_built_parts.append(node)


func _new_part_node(part: PartDesign) -> Node2D:
	if part is LegDesign:
		return IKLeg.new()
	if part is TentacleDesign:
		return Tentacle.new()
	if part is EyesDesign:
		return Eyes.new()
	return Ornament.new()


## 掛件放自己的圖：在掛件底下加一個 Sprite2D
func _add_image(ornament: Node2D, part: OrnamentDesign) -> void:
	if part.image_file == "":
		return
	var sprite := Sprite2D.new()
	sprite.name = "Image"
	sprite.texture = shape.load_image(part.image_file)
	ornament.add_child(sprite)
	_apply_image(ornament, part)


func _apply_image(ornament: Node, part: OrnamentDesign) -> void:
	var sprite: Sprite2D = ornament.get_node_or_null("Image") as Sprite2D
	if sprite != null:
		sprite.scale = Vector2.ONE * part.image_scale
		sprite.rotation = part.image_rotation


func _clear_built() -> void:
	for node: Node in [_built_body] + _built_parts:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_built_body = null
	_built_parts.clear()
	_built_structure = ""
	_body_image_key = ""


## 設計檔的「結構」寫成一串字：零件的種類和數量、掛件的左右和圖。這串字變了就要重長
func _design_structure() -> String:
	var text: String = ""
	for part: PartDesign in shape.all_parts():
		text += part.get_script().get_global_name() + ","
		if part is OrnamentDesign:
			text += "%d:%s," % [part.side, part.image_file]
	return text


## 有設計檔的生物：速度、轉向用能力計算的值，頭的大小跟身體第一節一樣粗
func _apply_abilities() -> void:
	var stats: CreatureStats = get_stats()
	speed = stats.speed
	turn_speed = stats.turn
	var body: BodyDesign = shape.body
	head_radius = maxf(body.thickness * (body.width_curve.sample(0.0) if body.width_curve != null else 1.0), 4.0)


## 平衡資料（沒有指定就用預設的）
func get_balance() -> CreatureBalance:
	if balance == null:
		balance = CreatureBalance.get_default()
	return balance


## 現在的能力（速度、轉向、抓取、視野、升一級要吃幾個、體型）。沒有設計檔是 null。
## 形狀變了（apply_design()）才重算
func get_stats() -> CreatureStats:
	return _stats


func _notify_parts() -> void:
	for node: Node in find_children("*", "", true, false):
		if node.has_method("on_grow"):
			node.call("on_grow", level)
