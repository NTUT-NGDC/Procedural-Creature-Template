@tool
class_name Anemone
extends Node2D
## 海葵（也可以當珊瑚）：中間一團，周圍一圈短觸手。生物經過時觸手被推開，再像彈簧一樣彈回來。
## 每條觸手跟水草一樣是一條角度彈簧鏈（Weed.bend_chain()），只是往不同方向長。
##
## 用法：放在生態缸的 Plants 節點底下，節點的位置就是中心。

@export_group("形狀")
## 觸手數量
@export_range(3, 24, 1) var arm_count: int = 10:
	set(value):
		arm_count = value
		reset_pose()
## 觸手長度（像素）
@export_range(10, 200, 1) var arm_length: float = 40.0:
	set(value):
		arm_length = value
		reset_pose()
## 每條觸手幾節
@export_range(2, 10, 1) var arm_segments: int = 4:
	set(value):
		arm_segments = value
		reset_pose()
## 觸手粗細（像素）
@export_range(1, 20, 0.5) var arm_width: float = 4.0:
	set(value):
		arm_width = value
		queue_redraw()
## 中間那團的半徑（像素）
@export_range(2, 80, 1) var body_radius: float = 14.0:
	set(value):
		body_radius = value
		reset_pose()
## 觸手張開的角度：360 是一整圈（珊瑚），180 左右是往上的扇形（長在地上的海葵）
@export_range(30, 360, 1, "radians_as_degrees") var fan_angle: float = deg_to_rad(200.0):
	set(value):
		fan_angle = value
		reset_pose()

@export_group("外觀")
@export var body_color: Color = Color("#c2185b"):
	set(value):
		body_color = value
		queue_redraw()
@export var arm_base_color: Color = Color("#ec407a"):
	set(value):
		arm_base_color = value
		queue_redraw()
@export var arm_tip_color: Color = Color("#ffd1e0"):
	set(value):
		arm_tip_color = value
		queue_redraw()

@export_group("動作")
## 硬度：被推開之後彈回來多快
@export_range(0.5, 30, 0.5) var stiffness: float = 6.0
## 水流推多少
@export_range(0, 5, 0.1) var flow_bend: float = 0.5

## 每條觸手的關節（全局座標），[0] 是根部
var _arms: Array[PackedVector2Array] = []
## 每條觸手每個關節彎了幾度、彎的速度
var _angles: Array[PackedFloat32Array] = []
var _speeds: Array[PackedFloat32Array] = []


func _ready() -> void:
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if _arms.is_empty() or not _arms[0][0].is_equal_approx(_arm_root(0)):
			reset_pose()
		return
	var obstacles: Array[Vector3] = Weed.gather_obstacles(self, global_position, arm_length + body_radius)
	for k: int in _arms.size():
		_arms[k] = Weed.bend_chain(_angles[k], _speeds[k], _arm_root(k), _arm_direction(k), arm_length / arm_segments, stiffness, flow_bend, obstacles, delta)
	queue_redraw()


## 第 k 條觸手往哪個方向長：在往上的扇形裡平均分開
func _arm_direction(k: int) -> Vector2:
	var t: float = (k + 0.5) / arm_count if fan_angle >= TAU - 0.01 else float(k) / maxi(arm_count - 1, 1)
	return Vector2.UP.rotated(lerpf(-fan_angle / 2.0, fan_angle / 2.0, t))


## 第 k 條觸手的根部（中間那團的邊上）
func _arm_root(k: int) -> Vector2:
	var center: Vector2 = global_position if is_inside_tree() else position
	return center + _arm_direction(k) * body_radius * 0.8


## 預覽姿勢：觸手都直直伸出去
func reset_pose() -> void:
	_arms.clear()
	_angles.clear()
	_speeds.clear()
	for k: int in arm_count:
		var angles := PackedFloat32Array()
		angles.resize(arm_segments)
		_angles.append(angles)
		_speeds.append(angles.duplicate())
		_arms.append(Weed.chain_points(_arm_root(k), _arm_direction(k), arm_length / arm_segments, angles))
	queue_redraw()


## 第 k 條觸手的尖端（全局座標，測試用）
func get_arm_tip(k: int) -> Vector2:
	return _arms[k][-1]


func _draw() -> void:
	for arm: PackedVector2Array in _arms:
		for i: int in arm.size() - 1:
			var t: float = float(i) / (arm.size() - 1)
			draw_line(to_local(arm[i]), to_local(arm[i + 1]), arm_base_color.lerp(arm_tip_color, t), arm_width * (1.0 - t * 0.5) * 2.0, true)
		draw_circle(to_local(arm[-1]), arm_width * 0.8, arm_tip_color, true, -1.0, true)  # 圓圓的尖端
	draw_circle(Vector2.ZERO, body_radius, body_color, true, -1.0, true)
	draw_circle(Vector2(-body_radius * 0.3, -body_radius * 0.3), body_radius * 0.35, body_color.lightened(0.25), true, -1.0, true)
