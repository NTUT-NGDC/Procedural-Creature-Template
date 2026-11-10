@tool
class_name IKLeg
extends CreaturePart
## 腳：大腿＋小腿兩節，腳掌釘在地上，身體走遠了才抬腳跨一步。
##
## 用法：加在 ChainBody（或 Creature）底下，設定掛在第幾節。「兩邊」時一個節點會畫左右一對，
## 左邊用「分組」選的那組、右邊自動用另一組，兩組輪流抬腳。
##
## 演算法在 solve_knee()（Two-Bone IK：算膝蓋在哪）和 update_step()（什麼時候換腳），
## 其他都是畫圖和屬性處理。

## 分組、膝蓋方向的編號，跟選單的順序一樣
enum Group { A, B }
enum Knee { OUTWARD, INWARD }

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭，-1 是最後一節
@export_range(-1, 80, 1, "or_greater") var attach_segment: int = 1:
	set(value):
		attach_segment = value
		reset_pose()
## 掛在哪一邊：兩邊會畫左右一對
@export_enum("左", "右", "兩邊") var side: int = Side.BOTH:
	set(value):
		side = value
		reset_pose()

@export_group("形狀")
## 大腿長（像素）
@export_range(4, 200, 1) var thigh_length: float = 30.0:
	set(value):
		thigh_length = value
		reset_pose()
## 小腿長（像素）
@export_range(4, 200, 1) var shin_length: float = 34.0:
	set(value):
		shin_length = value
		reset_pose()
## 膝蓋方向：向外是像蜘蛛一樣張開（往前伸的腳膝蓋朝前、往後伸的朝後），向內相反
@export_enum("向外", "向內") var knee_direction: int = Knee.OUTWARD:
	set(value):
		knee_direction = value
		queue_redraw()

@export_group("動作")
## 落腳角度：理想落腳點相對身體往前的方向，0 是往前、90 是往旁邊、180 是往後
@export_range(0, 180, 1, "radians_as_degrees") var rest_angle: float = deg_to_rad(70.0):
	set(value):
		rest_angle = value
		reset_pose()
## 落腳距離：理想落腳點離髖關節多遠，是「大腿＋小腿」的幾倍
@export_range(0.2, 1.0, 0.05) var rest_distance: float = 0.75:
	set(value):
		rest_distance = value
		reset_pose()
## 跨步距離（像素）：腳掌離理想落腳點多遠就抬腳。越小越像碎步
@export_range(2, 200, 1) var step_distance: float = 24.0
## 跨步時間（秒）：抬一次腳要多久
@export_range(0.02, 1.0, 0.01) var step_time: float = 0.12
## 預判（秒）：抬腳時往移動方向多跨幾秒的距離，太小的話腳會一直拖在後面
@export_range(0, 1, 0.01) var lead: float = 0.15
## 抬腳高度：腳在空中時，腳掌畫大多少、影子多明顯
@export_range(0, 20, 0.5) var lift_height: float = 4.0
## 分組：A、B 兩組輪流抬腳。「兩邊」時右邊自動用另一組
@export_enum("A", "B") var group: int = Group.A

@export_group("外觀")
## 腳的粗細（像素）
@export_range(1, 20, 0.5) var leg_width: float = 4.0:
	set(value):
		leg_width = value
		queue_redraw()
## 腳的顏色
@export var leg_color: Color = Color("#c9b59c"):
	set(value):
		leg_color = value
		queue_redraw()

## 每隻腳的腳掌位置（全局座標）、是否在空中、跨步進度 0～1、這一步從哪裡開始、屬於哪一組
var _feet: PackedVector2Array = []
var _stepping: Array[bool] = []
var _step_t: PackedFloat32Array = []
var _step_start: PackedVector2Array = []
var _groups: PackedInt32Array = []


func _ready() -> void:
	show_behind_parent = true  # 腳長在身體下面
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		editor_follow_anchor(anchor_position(attach_segment, 1.0) + Vector2.from_angle(anchor_angle(attach_segment)))
		return
	var signs: PackedFloat32Array = side_signs(side)
	if _feet.size() != signs.size():
		reset_pose()
	for k: int in signs.size():
		update_step(k, _rest_point(signs[k]), delta)
	queue_redraw()


# ---------------------------------------------------------------- 演算法


## Two-Bone IK：知道髖關節、腳掌和兩節的長度，用餘弦定理算出膝蓋在哪
func solve_knee(hip: Vector2, foot: Vector2, l1: float, l2: float, bend: float) -> Vector2:
	var d: float = clampf(hip.distance_to(foot), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)  # 三角形要存在
	var base_angle: float = (foot - hip).angle()  # 髖 → 腳掌的方向
	var a: float = acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))  # 餘弦定理
	return hip + Vector2.from_angle(base_angle + a * bend) * l1  # bend = 1 或 -1：膝蓋往哪邊彎


## 換腳：腳掌平常釘在地上。離理想落腳點太遠、另一組沒有腳在空中，就抬腳跨過去
func update_step(k: int, rest: Vector2, delta: float) -> void:
	var creature: Creature = get_creature()
	var velocity: Vector2 = creature.velocity if creature != null else Vector2.ZERO
	var limit: float = step_distance if velocity.length() > 5.0 else step_distance * 0.5  # 停下來時，差一半就收回來
	if not _stepping[k]:
		var distance: float = _feet[k].distance_to(rest)
		var allowed: bool = creature == null or creature.can_step(_groups[k])  # 另一組有腳在空中就等
		if (distance > limit and allowed) or distance > step_distance * 2.0:  # 落後太多就不等了
			_stepping[k] = true
			_step_t[k] = 0.0
			_step_start[k] = _feet[k]
	if _stepping[k]:
		_step_t[k] = minf(_step_t[k] + delta / step_time, 1.0)
		var target: Vector2 = rest + (velocity * lead).limit_length(step_distance)  # 往移動方向多跨一點（預判），最多一個跨步
		_feet[k] = _step_start[k].lerp(target, smoothstep(0.0, 1.0, _step_t[k]))
		if _step_t[k] >= 1.0:
			_stepping[k] = false


# ---------------------------------------------------------------- 對外的功能


## group 這組有沒有腳在空中（Creature.can_step() 用）
func is_group_stepping(group_id: int) -> bool:
	for k: int in _stepping.size():
		if _stepping[k] and _groups[k] == group_id:
			return true
	return false


## 預覽姿勢：腳掌放在理想落腳點
func reset_pose() -> void:
	if not is_inside_tree():
		return
	var signs: PackedFloat32Array = side_signs(side)
	_feet.clear()
	_stepping.clear()
	_step_t.clear()
	_step_start.clear()
	_groups.clear()
	for k: int in signs.size():
		_feet.append(_rest_point(signs[k]))
		_stepping.append(false)
		_step_t.append(0.0)
		_step_start.append(_feet[k])
		# 兩邊的時候，右腳用另一組，左右才會輪流
		_groups.append(1 - group if side == Side.BOTH and signs[k] > 0.0 else group)
	queue_redraw()


# ---------------------------------------------------------------- 位置


## 髖關節：掛載的那一節靠近邊緣的地方
func _hip(side_sign: float) -> Vector2:
	return anchor_position(attach_segment, side_sign, 0.8)


## 理想落腳點：從髖關節往「落腳角度」伸出「腳長 × 落腳距離」
func _rest_point(side_sign: float) -> Vector2:
	var angle: float = anchor_angle(attach_segment) + rest_angle * side_sign
	return _hip(side_sign) + Vector2.from_angle(angle) * (thigh_length + shin_length) * rest_distance


## 膝蓋往哪邊彎（1 或 -1）。「向外」像蜘蛛一樣張開：往前伸的腳膝蓋朝前、往後伸的腳膝蓋朝後。
## 左右相反，「向內」再反過來。只看屬性、固定不變，才不會突然翻面
func _bend(side_sign: float) -> float:
	var fan: float = -1.0 if rest_angle < PI / 2.0 else 1.0
	return side_sign * fan * (1.0 if knee_direction == Knee.OUTWARD else -1.0)


# ---------------------------------------------------------------- 畫圖


func _draw() -> void:
	var signs: PackedFloat32Array = side_signs(side)
	var style: Dictionary = outline_style()
	for k: int in mini(_feet.size(), signs.size()):
		var hip: Vector2 = _hip(signs[k])
		# 腳掌太遠時，畫的時候先拉回伸得到的地方，小腿才不會被拉長
		var foot: Vector2 = hip + (_feet[k] - hip).limit_length(thigh_length + shin_length - 0.01)
		var knee: Vector2 = solve_knee(hip, foot, thigh_length, shin_length, _bend(signs[k]))
		var lift: float = sin(_step_t[k] * PI) if _stepping[k] else 0.0
		_draw_leg(to_local(hip), to_local(knee), to_local(foot), lift, style)
	if CreatureDebug.bones_visible(self):
		_draw_bones(signs)


## 畫一隻腳：影子（抬起時）→ 外框 → 大腿、小腿 → 膝蓋、腳掌
func _draw_leg(hip: Vector2, knee: Vector2, foot: Vector2, lift: float, style: Dictionary) -> void:
	var foot_radius: float = leg_width * 0.8 + lift * lift_height
	if lift > 0.0:
		draw_circle(foot + Vector2(2.0, 3.0) * lift_height * lift, foot_radius, Color(0, 0, 0, 0.25), true, -1.0, true)
	if style.width > 0.0:
		var outer: float = leg_width + style.width * 2.0
		draw_line(hip, knee, style.color, outer, true)
		draw_line(knee, foot, style.color, outer, true)
		draw_circle(knee, outer / 2.0, style.color, true, -1.0, true)
		draw_circle(foot, foot_radius + style.width, style.color, true, -1.0, true)
	draw_line(hip, knee, leg_color, leg_width, true)
	draw_line(knee, foot, leg_color, leg_width, true)
	draw_circle(knee, leg_width / 2.0, leg_color, true, -1.0, true)
	draw_circle(foot, foot_radius, leg_color.lightened(0.15 * lift), true, -1.0, true)


## 骨架（F1）：理想落腳點（小圈）、跨步距離（大圈）、腳掌到理想點的線
func _draw_bones(signs: PackedFloat32Array) -> void:
	for k: int in mini(_feet.size(), signs.size()):
		var rest: Vector2 = to_local(_rest_point(signs[k]))
		var foot: Vector2 = to_local(_feet[k])
		draw_arc(rest, step_distance, 0.0, TAU, 32, Color(CreatureDebug.BONE_COLOR, 0.35), 1.0, true)
		draw_arc(rest, 3.0, 0.0, TAU, 12, Color(CreatureDebug.BONE_COLOR, 0.8), 1.0, true)
		draw_line(foot, rest, Color(CreatureDebug.BONE_COLOR, 0.4), 1.0, true)
