@tool
class_name Eyes
extends CreaturePart
## 眼睛：一排眼睛平均排在某一節上，瞳孔會看著前方、滑鼠、食物或天敵，還會眨眼。
##
## 用法：加在 ChainBody（或 Creature）底下。大小和間距是「那一節粗細」的比例，
## 身體變粗變細時眼睛會跟著變。

## 看哪裡的編號，跟「看哪裡」選單的順序一樣
enum LookAt { FORWARD, MOUSE, FOOD, PREDATOR }

## 眨眼：閉多久（秒）、每次眨眼間隔幾秒（隨機）
const BLINK_TIME: float = 0.12
const BLINK_INTERVAL_MIN: float = 2.0
const BLINK_INTERVAL_MAX: float = 5.0

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭
@export_range(-1, 80, 1, "or_greater") var attach_segment: int = 0:
	set(value):
		attach_segment = value
		queue_redraw()

@export_group("形狀")
## 眼睛數量：平均排在那一節上
@export_range(1, 6, 1) var count: int = 2:
	set(value):
		count = value
		queue_redraw()
## 大小：眼白半徑是那一節粗細的幾倍
@export_range(0.05, 1.0, 0.01) var size: float = 0.3:
	set(value):
		size = value
		queue_redraw()
## 間距：最外側的眼睛離中線多遠，是那一節粗細的幾倍
@export_range(0.0, 1.5, 0.01) var spread: float = 0.6:
	set(value):
		spread = value
		queue_redraw()

@export_group("外觀")
## 眼白顏色
@export var white_color: Color = Color.WHITE:
	set(value):
		white_color = value
		queue_redraw()
## 瞳孔顏色
@export var pupil_color: Color = Color("#111111"):
	set(value):
		pupil_color = value
		queue_redraw()

@export_group("動作")
## 看哪裡：前方、滑鼠、最近的食物（"food" 群組）、最近的天敵（"predator" 群組）
@export_enum("前方", "滑鼠", "最近的食物", "最近的天敵") var look_target: int = LookAt.FORWARD
## 眨眼
@export var blink: bool = true

## 瞳孔現在看的方向（單位向量，會慢慢轉過去）
var _look: Vector2 = Vector2.RIGHT
var _blink_timer: float = 0.0
var _blinking: bool = false


func _ready() -> void:
	_blink_timer = randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		var anchor: Vector2 = anchor_position(attach_segment, 0.0)
		if not anchor.is_equal_approx(_last_anchor):
			_last_anchor = anchor
			queue_redraw()
		return
	var target_direction: Vector2 = _find_look_direction()
	_look = _look.lerp(target_direction, 1.0 - exp(-12.0 * delta)).normalized()
	_update_blink(delta)
	queue_redraw()


## 要看的方向（單位向量）。找不到目標就看前方
func _find_look_direction() -> Vector2:
	var center: Vector2 = anchor_position(attach_segment, 0.0)
	var forward: Vector2 = Vector2.from_angle(anchor_angle(attach_segment))
	var target: Node2D = null
	match look_target:
		LookAt.MOUSE:
			return center.direction_to(get_global_mouse_position())
		LookAt.FOOD:
			target = _nearest_in_group("food", center)
		LookAt.PREDATOR:
			target = _nearest_in_group("predator", center)
	if target == null:
		return forward
	return center.direction_to(target.global_position)


func _nearest_in_group(group_name: String, from: Vector2) -> Node2D:
	var nearest: Node2D = null
	var creature: Creature = get_creature()
	for node: Node in get_tree().get_nodes_in_group(group_name):
		var other: Node2D = node as Node2D
		if other == null or other == creature:
			continue
		if nearest == null or from.distance_to(other.global_position) < from.distance_to(nearest.global_position):
			nearest = other
	return nearest


## 每隔 2～5 秒眨一次眼，每次閉 0.12 秒
func _update_blink(delta: float) -> void:
	_blink_timer -= delta
	if _blinking and _blink_timer <= 0.0:
		_blinking = false
		_blink_timer = randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)
	elif not _blinking and _blink_timer <= 0.0 and blink:
		_blinking = true
		_blink_timer = BLINK_TIME


## 每顆眼睛的中心（全局座標）：沿著那一節的左右方向平均排開
func get_eye_positions() -> PackedVector2Array:
	var positions: PackedVector2Array = []
	for i: int in count:
		var offset: float = 0.0 if count == 1 else lerpf(-spread, spread, float(i) / (count - 1))
		positions.append(anchor_position(attach_segment, 1.0, offset))
	return positions


## 眼睛的大小依那一節的粗細算
func _segment_width() -> float:
	var body: ChainBody = get_body()
	if body != null:
		return body.get_width(attach_segment)
	return get_creature().head_radius if get_creature() != null else 10.0


func _draw() -> void:
	var white_radius: float = _segment_width() * size
	var style: Dictionary = outline_style()
	var look: Vector2 = Vector2.from_angle(anchor_angle(attach_segment)) if Engine.is_editor_hint() else _look
	FastDraw.begin(self)  # 這排眼睛一次畫完
	for eye_position: Vector2 in get_eye_positions():
		var center: Vector2 = to_local(eye_position)
		if _blinking:
			# 閉眼：畫一條短線
			var across: Vector2 = Vector2.from_angle(anchor_angle(attach_segment) - global_rotation + PI / 2.0) * white_radius
			draw_line(center - across, center + across, style.color, maxf(1.5, white_radius * 0.3), true)
			continue
		FastDraw.circle(self, center, white_radius, white_color)
		var local_look: Vector2 = look.rotated(-global_rotation)
		FastDraw.circle(self, center + local_look * white_radius * 0.35, white_radius * 0.5, pupil_color)
	FastDraw.end()
