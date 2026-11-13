@tool
class_name Weed
extends Node2D
## 水草：根部固定在地上的一串關節。每個關節像彈簧一樣想站直，被水流推、被經過的生物撥開就會彎。
## 跟真的植物一樣，根部彎一點，上面整株就跟著轉過去（越下面越影響整株）；根部硬、尖端軟。
##
## 用法：放在生態缸的 Plants 節點底下，節點的位置就是根部。編輯器裡看得到站直的樣子。
## 演算法在 bend_chain()（海葵也用這個），其他是畫圖和屬性處理。

## 生物撥開水草時，多留幾像素的空隙
const PUSH_MARGIN: float = 4.0
## 生物推水草的力道：重疊 1 像素推多大力
const PUSH_FORCE: float = 30.0
## 力變成轉動的比例：越大越容易被推彎
const TURN_FACTOR: float = 0.18
## 根部比尖端硬幾倍
const ROOT_STIFFNESS: float = 2.0
## 阻力：越大晃越少、越快停
const DAMPING: float = 0.35
## 每個關節最多彎幾度（弧度），避免被推到折成一團
const MAX_BEND: float = 1.2

@export_group("形狀")
## 高度（像素）
@export_range(20, 400, 1) var height: float = 120.0:
	set(value):
		height = value
		reset_pose()
## 節數：越多越柔軟
@export_range(2, 20, 1) var segment_count: int = 8:
	set(value):
		segment_count = value
		reset_pose()
## 根部粗細、末端粗細（像素）
@export_range(1, 30, 0.5) var base_width: float = 6.0:
	set(value):
		base_width = value
		queue_redraw()
@export_range(0.5, 30, 0.5) var tip_width: float = 2.0:
	set(value):
		tip_width = value
		queue_redraw()
## 傾斜：沒有水流時往哪邊歪，0 是直直往上
@export_range(-60, 60, 1, "radians_as_degrees") var lean: float = 0.0:
	set(value):
		lean = value
		reset_pose()

@export_group("外觀")
## 根部顏色、末端顏色
@export var base_color: Color = Color("#2f6e45"):
	set(value):
		base_color = value
		queue_redraw()
@export var tip_color: Color = Color("#7fc77a"):
	set(value):
		tip_color = value
		queue_redraw()

@export_group("動作")
## 硬度：被推歪之後站回來多快。越小越軟、晃得越大
@export_range(0.5, 20, 0.5) var stiffness: float = 3.0
## 水流推多少：0 是不受水流影響
@export_range(0, 5, 0.1) var flow_bend: float = 1.0

## 每一節的位置（全局座標），[0] 是根部
var _points: PackedVector2Array = []
## 每個關節「比下面那節多彎幾度」（弧度）、彎的速度
var _angles: PackedFloat32Array = []
var _speeds: PackedFloat32Array = []


func _ready() -> void:
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if _points.is_empty() or not _points[0].is_equal_approx(global_position):
			reset_pose()  # 編輯器裡被拖動了：重擺
		return
	var obstacles: Array[Vector3] = gather_obstacles(self, global_position, height)
	_points = bend_chain(_angles, _speeds, global_position, Vector2.UP.rotated(lean), height / segment_count, stiffness, flow_bend, obstacles, delta)
	queue_redraw()


## 角度彈簧鏈（水草、海葵的觸手都用這個）。angles 是每個關節「比下面那節多彎幾度」：
## 1. 從根部一節一節接上去，算出每一節的位置（根部彎，上面整株跟著轉）
## 2. 每一節受到的力（水流、生物推）變成它下面每個關節的轉動力：力臂 × 力
## 3. 每個關節像彈簧一樣想彎回 0 度（根部硬、尖端軟），再加上阻力
static func bend_chain(angles: PackedFloat32Array, speeds: PackedFloat32Array, root: Vector2, direction: Vector2, seg_len: float, stiff: float, bend: float, obstacles: Array[Vector3], delta: float) -> PackedVector2Array:
	var points: PackedVector2Array = chain_points(root, direction, seg_len, angles)  # 1. 從根部接上去
	var count: int = angles.size()
	var torques := PackedFloat32Array()
	torques.resize(count)
	for i: int in range(1, points.size()):  # 2. 每一節受的力，傳給它下面的每個關節
		var force: Vector2 = WaterFlow.at(points[i]) * bend + push_force(points[i], obstacles)
		for j: int in i:
			torques[j] += (points[i] - points[j]).cross(force) / (seg_len * count * count)  # 力臂 × 力（除掉長度，讓高矮不同的水草一樣好推）
	for j: int in count:  # 3. 角度彈簧：根部硬、尖端軟
		var spring: float = stiff * stiff * lerpf(ROOT_STIFFNESS, 1.0, float(j) / maxi(count - 1, 1))
		speeds[j] += (torques[j] * TURN_FACTOR - spring * angles[j] - 2.0 * DAMPING * sqrt(spring) * speeds[j]) * delta
		angles[j] = clampf(angles[j] + speeds[j] * delta, -MAX_BEND, MAX_BEND)
	return chain_points(root, direction, seg_len, angles)


## 從根部照每個關節的角度，一節一節接出每一節的位置
static func chain_points(root: Vector2, direction: Vector2, seg_len: float, angles: PackedFloat32Array) -> PackedVector2Array:
	var points := PackedVector2Array([root])
	var angle: float = direction.angle()
	for bend_angle: float in angles:
		angle += bend_angle  # 每個關節在下面那節的方向上再多彎一點
		points.append(points[-1] + Vector2.from_angle(angle) * seg_len)
	return points


## 生物把這一點往外推的力：點在生物身體裡面時，重疊越多推越大力（obstacles 每一項是 x、y、半徑）
static func push_force(point: Vector2, obstacles: Array[Vector3]) -> Vector2:
	var force := Vector2.ZERO
	for obstacle: Vector3 in obstacles:
		var center := Vector2(obstacle.x, obstacle.y)
		var reach: float = obstacle.z + PUSH_MARGIN
		var offset: Vector2 = point - center
		if offset.length_squared() < reach * reach and offset != Vector2.ZERO:
			force += offset.normalized() * (reach - offset.length()) * PUSH_FORCE
	return force


## 附近（near 周圍 reach 像素）的生物身體：每一節一個圓，回傳 (x, y, 半徑) 的清單
static func gather_obstacles(node: Node, near: Vector2, reach: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for item: Node in node.get_tree().get_nodes_in_group("creature"):
		var creature: Creature = item as Creature
		var body: ChainBody = creature.get_body() if creature != null else null
		if body == null:
			if creature != null and creature.global_position.distance_to(near) < reach + creature.head_radius:
				result.append(Vector3(creature.global_position.x, creature.global_position.y, creature.head_radius))
			continue
		# 整隻都離很遠就跳過（頭到這裡的距離 > 水草高度＋身體長度）
		if creature.global_position.distance_to(near) > reach + body.joint_count() * body.spacing + body.thickness:
			continue
		for i: int in body.joint_count():
			var joint: Vector2 = body.get_joint(i)
			result.append(Vector3(joint.x, joint.y, body.get_width(i)))
	return result


## 預覽姿勢：關節都不彎，從根部往上（照傾斜）拉直
func reset_pose() -> void:
	_angles.resize(segment_count)
	_angles.fill(0.0)
	_speeds.resize(segment_count)
	_speeds.fill(0.0)
	var root: Vector2 = global_position if is_inside_tree() else position
	_points = chain_points(root, Vector2.UP.rotated(lean), height / segment_count, _angles)
	queue_redraw()


## 尖端的位置（全局座標，測試用）
func get_tip() -> Vector2:
	return _points[-1]


func _draw() -> void:
	if _points.size() < 2:
		return
	var count: int = _points.size()
	for i: int in count - 1:
		var t: float = float(i) / (count - 1)
		var a: Vector2 = to_local(_points[i])
		var b: Vector2 = to_local(_points[i + 1])
		var width: float = lerpf(base_width, tip_width, t)
		var color: Color = base_color.lerp(tip_color, t)
		draw_line(a, b, color, width * 2.0, true)
		draw_circle(b, lerpf(base_width, tip_width, float(i + 1) / (count - 1)), base_color.lerp(tip_color, float(i + 1) / (count - 1)), true, -1.0, true)
		# 葉子：每隔一節，左右交錯長一片
		if i % 2 == 1:
			var side: float = 1.0 if i % 4 == 1 else -1.0
			var along: Vector2 = (b - a).normalized()
			var leaf_dir: Vector2 = along.rotated(side * 0.9)
			_draw_leaf(b, leaf_dir, width * 3.0, color.lightened(0.15))
	draw_circle(to_local(_points[0]), base_width, base_color, true, -1.0, true)


## 一片葉子：細長的菱形
func _draw_leaf(at: Vector2, direction: Vector2, length: float, color: Color) -> void:
	var side: Vector2 = direction.orthogonal() * length * 0.25
	draw_colored_polygon(PackedVector2Array([at, at + direction * length * 0.5 + side, at + direction * length, at + direction * length * 0.5 - side]), color)
