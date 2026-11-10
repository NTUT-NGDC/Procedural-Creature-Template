@tool
class_name CreaturePart
extends Node2D
## 掛載零件（觸手、腳、眼睛、掛件）共用的基底：找到自己掛在哪隻生物、哪一節上。
##
## 往上找最近的 ChainBody，掛在它的某一節上；沒有身體的話就掛在 Creature 的中心（頭）。
## 「左右」是從生物的角度看：面向前方時的左手邊、右手邊。
##
## 每種零件自己宣告「掛在第幾節」「左右」兩個屬性（預設值各不相同），
## 再用這裡的 anchor_position()、anchor_angle()、side_signs() 算位置。

## 左右的編號，跟各零件「左右」選單的順序一樣
enum Side { LEFT, RIGHT, BOTH, CENTER }

## 上次擺預覽姿勢時，掛載點在哪裡（編輯器裡用來發現生物被拖動了）
var _last_anchor: Vector2 = Vector2.INF


## 這個零件屬於哪隻生物（往上找最近的 Creature），找不到就是 null
func get_creature() -> Creature:
	var node: Node = get_parent()
	while node != null:
		if node is Creature:
			return node
		node = node.get_parent()
	return null


## 掛在哪個身體上（往上找最近的 ChainBody），沒有就是 null
func get_body() -> ChainBody:
	var node: Node = get_parent()
	while node != null and not node is Creature:
		if node is ChainBody:
			return node
		node = node.get_parent()
	return null


## 「左右」選項要畫在哪幾邊：-1 是左、1 是右、0 是中間。「兩邊」就是左右各一個
static func side_signs(side: int) -> PackedFloat32Array:
	match side:
		Side.LEFT:
			return PackedFloat32Array([-1.0])
		Side.RIGHT:
			return PackedFloat32Array([1.0])
		Side.BOTH:
			return PackedFloat32Array([-1.0, 1.0])
	return PackedFloat32Array([0.0])


## 第 segment 節面向的角度（全局，弧度）。沒有身體就是頭的方向
func anchor_angle(segment: int) -> float:
	var body: ChainBody = get_body()
	if body != null:
		return body.get_angle(segment)
	var creature: Creature = get_creature()
	return creature.heading if creature != null else global_rotation


## 掛載點（全局座標）：第 segment 節往 side_sign 那邊（-1 左、1 右、0 中間）偏「粗細 × outward」
func anchor_position(segment: int, side_sign: float, outward: float = 1.0) -> Vector2:
	var body: ChainBody = get_body()
	var center: Vector2 = global_position
	var half_width: float = 0.0
	if body != null:
		center = body.get_joint(segment)
		half_width = body.get_width(segment)
	elif get_creature() != null:
		center = get_creature().global_position
		half_width = get_creature().head_radius
	# 面向角度 +90 度是右手邊（Godot 的 y 往下）
	return center + Vector2.from_angle(anchor_angle(segment) + PI / 2.0) * half_width * outward * side_sign


## 外框的顏色和粗細跟身體一樣，畫風才統一。沒有身體就用預設值
func outline_style() -> Dictionary:
	var body: ChainBody = get_body()
	if body != null:
		return {"color": body.outline_color, "width": body.outline_width}
	return {"color": Color("#cdeccf"), "width": 2.5}


## 編輯器裡：生物被拖動、身體形狀改了，就重擺預覽姿勢。子類別在 _process() 開頭呼叫
func editor_follow_anchor(anchor: Vector2) -> void:
	if not anchor.is_equal_approx(_last_anchor):
		_last_anchor = anchor
		reset_pose()


## Creature 長大或變短時呼叫。預設不做事，子類別可以覆寫
func on_grow(_level: int) -> void:
	pass


## 擺回預覽姿勢。子類別要覆寫
func reset_pose() -> void:
	queue_redraw()
