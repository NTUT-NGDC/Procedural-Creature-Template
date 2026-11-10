@tool
class_name Tentacle
extends CreaturePart
## 觸手（也可以當尾巴、鬍鬚、天線）：根部黏在身體上，末端伸去抓東西。
##
## 用法：加在 ChainBody（或 Creature）底下，設定掛在第幾節、伸出角度。
## 「兩邊」時一個節點會畫左右一對，不用加兩個節點。
##
## 演算法在 fabrik()（伸向目標）和 drag()（往後拖），其他都是畫圖和屬性處理。

## 行為的編號，跟「行為」選單的順序一樣
enum Behavior { DRAG, WAVE, POINT_MOUSE, GRAB_FOOD }

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭，-1 是最後一節（尾巴）
@export_range(-1, 80, 1, "or_greater") var attach_segment: int = 0:
	set(value):
		attach_segment = value
		reset_pose()
## 掛在哪一邊：兩邊會畫左右一對
@export_enum("左", "右", "兩邊", "中間") var side: int = Side.BOTH:
	set(value):
		side = value
		reset_pose()

@export_group("形狀")
## 伸出角度：相對身體往前的方向，0 是往前、90 是往旁邊、180 是往後
@export_range(0, 180, 1, "radians_as_degrees") var reach_angle: float = deg_to_rad(150.0):
	set(value):
		reach_angle = value
		reset_pose()
## 節數：越多越柔軟
@export_range(2, 40, 1) var segment_count: int = 10:
	set(value):
		segment_count = value
		reset_pose()
## 長度（像素）
@export_range(10, 400, 1) var length: float = 80.0:
	set(value):
		length = value
		reset_pose()
## 根部粗細：中心到邊緣的距離（像素）
@export_range(0.5, 40, 0.5) var base_width: float = 6.0:
	set(value):
		base_width = value
		queue_redraw()
## 末端粗細：中心到邊緣的距離（像素）
@export_range(0, 40, 0.5) var tip_width: float = 1.5:
	set(value):
		tip_width = value
		queue_redraw()

@export_group("動作")
## 行為：往後拖（被身體拖著走、轉彎時會甩）、波浪擺動、指向滑鼠、抓最近的食物（伸得到就抓來吃）
@export_enum("往後拖", "波浪擺動", "指向滑鼠", "抓最近的食物") var behavior: int = Behavior.DRAG
## 擺動幅度（像素）：觸手左右晃動的大小，0 是不晃
@export_range(0, 100, 1) var wave_amplitude: float = 15.0
## 擺動速度
@export_range(0, 10, 0.1) var wave_speed: float = 3.0
## FABRIK 迭代次數：越多越準；1 次會有「黏黏的」感覺
@export_range(1, 10, 1) var iterations: int = 4

@export_group("外觀")
## 顏色：從根部（左）到末端（右）的漸層。只放一個顏色就是單色
@export var color_gradient: Gradient = _make_default_gradient():
	set(value):
		if color_gradient != null and color_gradient.changed.is_connected(queue_redraw):
			color_gradient.changed.disconnect(queue_redraw)
		color_gradient = value
		if color_gradient != null and not color_gradient.changed.is_connected(queue_redraw):
			color_gradient.changed.connect(queue_redraw)
		queue_redraw()
## 吸盤：沿著觸手一側畫一排小圓點
@export var suckers: bool = true:
	set(value):
		suckers = value
		queue_redraw()
## 吸盤顏色
@export var sucker_color: Color = Color("#f9d3e0"):
	set(value):
		sucker_color = value
		queue_redraw()

## 每一條觸手的關節（全局座標），[0] 是根部。「兩邊」時有兩條
var _chains: Array[PackedVector2Array] = []
## 每一條觸手現在伸向哪裡（會慢慢移過去，不會瞬間跳）
var _targets: PackedVector2Array = []
## 每一條觸手要不要畫目標十字（骨架顯示用）
var _has_target: Array[bool] = []
## 擺動用的時間
var _time: float = 0.0


func _ready() -> void:
	show_behind_parent = true  # 觸手長在身體下面
	if color_gradient != null and not color_gradient.changed.is_connected(queue_redraw):
		color_gradient.changed.connect(queue_redraw)
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		editor_follow_anchor(anchor_position(attach_segment, 1.0) + Vector2.from_angle(anchor_angle(attach_segment)))
		return
	_time += delta
	var signs: PackedFloat32Array = side_signs(side)
	if _chains.size() != signs.size():
		reset_pose()
	for k: int in signs.size():
		_update_chain(k, signs[k], delta)
	queue_redraw()


# ---------------------------------------------------------------- 演算法


## FABRIK：根部固定在 base，末端盡量碰到 target。來回拉 iterations 趟
func fabrik(chain: PackedVector2Array, base: Vector2, target: Vector2) -> PackedVector2Array:
	var seg_len: float = length / segment_count
	for _i: int in iterations:
		chain[-1] = target  # 往回：末端放到目標
		for i: int in range(chain.size() - 2, -1, -1):
			chain[i] = chain[i + 1] + chain[i + 1].direction_to(chain[i]) * seg_len  # 往根部一節一節拉
		chain[0] = base  # 往前：根部放回原位
		for i: int in range(1, chain.size()):
			chain[i] = chain[i - 1] + chain[i - 1].direction_to(chain[i]) * seg_len  # 往末端一節一節拉
	return chain


## 往後拖：每節留在上一幀的位置（慣性），慢慢被拉回伸出角度，再拉到剛好一節的距離
func drag(chain: PackedVector2Array, base: Vector2, side_sign: float, delta: float) -> PackedVector2Array:
	var seg_len: float = length / segment_count
	var pull: float = 1.0 - exp(-3.0 * delta)  # 每秒被拉回多少
	chain[0] = base
	for i: int in range(1, chain.size()):
		chain[i] = chain[i].lerp(_rest_point(side_sign, i), pull)  # 慢慢回到伸出角度（加上晃動）
		chain[i] = chain[i - 1] + chain[i - 1].direction_to(chain[i]) * seg_len  # 拉到剛好一節的距離
	return chain


# ---------------------------------------------------------------- 行為


func _update_chain(k: int, side_sign: float, delta: float) -> void:
	var base: Vector2 = _root(side_sign)
	var target: Variant = _find_target(side_sign)
	_has_target[k] = target != null
	if target == null:
		_chains[k] = drag(_chains[k], base, side_sign, delta)
		_targets[k] = _chains[k][-1]
		return
	_targets[k] = _targets[k].lerp(target, 1.0 - exp(-10.0 * delta))  # 目標慢慢移過去
	_chains[k] = fabrik(_chains[k], base, _targets[k])
	if behavior == Behavior.GRAB_FOOD:
		_try_eat(_chains[k][-1])


## 依行為決定要伸向哪裡（全局座標）；回傳 null 代表「往後拖」
func _find_target(side_sign: float) -> Variant:
	var base: Vector2 = _root(side_sign)
	var rest_angle: float = _rest_angle(side_sign)
	var sway: Vector2 = Vector2.from_angle(rest_angle + PI / 2.0) * sin(_time * wave_speed) * wave_amplitude
	match behavior:
		Behavior.WAVE:
			return base + Vector2.from_angle(rest_angle) * length * 0.8 + sway * 2.0
		Behavior.POINT_MOUSE:
			return get_global_mouse_position() + sway * 0.3
		Behavior.GRAB_FOOD:
			var food: Node2D = _nearest_food(base)
			if food != null:
				return food.global_position
	return null


## 找觸手伸得到的最近食物（食物要在 "food" 群組裡）
func _nearest_food(base: Vector2) -> Node2D:
	var nearest: Node2D = null
	for node: Node in get_tree().get_nodes_in_group("food"):
		var food: Node2D = node as Node2D
		if food == null or base.distance_to(food.global_position) > length:
			continue
		if nearest == null or base.distance_to(food.global_position) < base.distance_to(nearest.global_position):
			nearest = food
	return nearest


## 末端碰到食物就吃掉
func _try_eat(tip: Vector2) -> void:
	var creature: Creature = get_creature()
	var food: Node2D = _nearest_food(_chains[0][0] if not _chains.is_empty() else tip)
	if creature != null and food != null and tip.distance_to(food.global_position) < tip_width + 8.0:
		food.remove_from_group("food")  # 避免同一幀被另一條觸手再吃一次
		creature.eat(food)


# ---------------------------------------------------------------- 位置


## 根部：掛載的那一節往旁邊偏一半粗細
func _root(side_sign: float) -> Vector2:
	return anchor_position(attach_segment, side_sign, 0.5)


## 伸出的方向（全局角度）：右邊往順時針轉、左邊往逆時針轉
func _rest_angle(side_sign: float) -> float:
	return anchor_angle(attach_segment) + reach_angle * (side_sign if side_sign != 0.0 else 1.0)


## 不受力時第 i 節的位置：沿著伸出方向排成一直線，執行時再加一點晃動
func _rest_point(side_sign: float, i: int) -> Vector2:
	var angle: float = _rest_angle(side_sign)
	var point: Vector2 = _root(side_sign) + Vector2.from_angle(angle) * length / segment_count * i
	if Engine.is_editor_hint():
		return point
	var wave: float = sin(_time * wave_speed - i * 0.5) * wave_amplitude * float(i) / segment_count
	return point + Vector2.from_angle(angle + PI / 2.0) * wave


## 預覽姿勢：每條觸手沿著伸出角度拉直
func reset_pose() -> void:
	if not is_inside_tree():
		return
	var signs: PackedFloat32Array = side_signs(side)
	_chains.clear()
	_targets.clear()
	_has_target.clear()
	for side_sign: float in signs:
		var chain: PackedVector2Array = []
		for i: int in segment_count + 1:
			chain.append(_rest_point(side_sign, i))
		_chains.append(chain)
		_targets.append(chain[-1])
		_has_target.append(false)
	queue_redraw()


static func _make_default_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0])
	gradient.colors = PackedColorArray([Color("#e58fb0")])
	return gradient


# ---------------------------------------------------------------- 畫圖


func _draw() -> void:
	var style: Dictionary = outline_style()
	var signs: PackedFloat32Array = side_signs(side)
	for k: int in _chains.size():
		var points: PackedVector2Array = []
		for joint: Vector2 in _chains[k]:
			points.append(to_local(joint))
		if style.width > 0.0:
			_draw_strand(points, style.width, style.color)
		_draw_strand(points, 0.0, null)
		if suckers:
			_draw_suckers(points, signs[k] if k < signs.size() else 1.0)
	if CreatureDebug.bones_visible(self):
		_draw_bones()


## 第 i 節的粗細：根部到末端慢慢變細
func _width_at(i: int) -> float:
	return lerpf(base_width, tip_width, float(i) / segment_count)


## 畫一條觸手：每節一段粗線＋關節的圓。color 是 null 就用漸層色，extra 是外框多出來的寬度
func _draw_strand(points: PackedVector2Array, extra: float, color: Variant) -> void:
	for i: int in points.size():
		var fill: Color = color if color != null else _gradient_color(float(i) / segment_count)
		var width: float = _width_at(i) + extra
		draw_circle(points[i], width, fill, true, -1.0, true)
		if i < points.size() - 1:
			draw_line(points[i], points[i + 1], fill, width + _width_at(i + 1) + extra, true)  # 兩端的粗細加起來＝線寬


## 吸盤：沿著觸手內側，每隔一節一個小圓點
func _draw_suckers(points: PackedVector2Array, side_sign: float) -> void:
	var inner: float = -side_sign if side_sign != 0.0 else 1.0
	for i: int in range(1, points.size() - 1, 2):
		var width: float = _width_at(i)
		if width < 2.0:
			continue
		var across: Vector2 = (points[i + 1] - points[i]).normalized().rotated(PI / 2.0 * inner)
		draw_circle(points[i] + across * width * 0.45, width * 0.35, sucker_color, true, -1.0, true)


func _gradient_color(t: float) -> Color:
	return color_gradient.sample(t) if color_gradient != null else Color("#e58fb0")


## 骨架（F1）：關節線、關節點；伸向目標時畫目標十字
func _draw_bones() -> void:
	for k: int in _chains.size():
		var points: PackedVector2Array = []
		for joint: Vector2 in _chains[k]:
			points.append(to_local(joint))
		draw_polyline(points, CreatureDebug.BONE_COLOR, 1.0, true)
		for point: Vector2 in points:
			draw_circle(point, 2.5, CreatureDebug.BONE_COLOR)
		if _has_target[k]:
			var target: Vector2 = to_local(_targets[k])
			var faint: Color = CreatureDebug.BONE_COLOR
			faint.a = 0.7
			draw_line(target + Vector2(-6, 0), target + Vector2(6, 0), faint, 1.0)
			draw_line(target + Vector2(0, -6), target + Vector2(0, 6), faint, 1.0)
