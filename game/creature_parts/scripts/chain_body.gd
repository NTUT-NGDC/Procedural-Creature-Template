@tool
class_name ChainBody
extends Node2D
## 身體：一串跟著頭走的關節（鏈條跟隨），沿著關節兩側畫出身體的輪廓。
##
## 用法：加在 Creature 底下。頭就是 Creature 的位置，第 1 節以後都跟著前一節走。
## 腳、觸手、眼睛、掛件可以加在身體底下，用「掛在第幾節」決定位置。
##
## 演算法在 follow_chain()，其他都是畫圖和屬性處理。

## 程式最多允許幾節（檢查器最多拉到 80，吃東西長大可以超過）
const MAX_SEGMENTS: int = 200
## 備用畫法：每兩節之間排幾個圓
const FALLBACK_STEPS: int = 3

## 花紋的編號，跟「花紋」選單的順序一樣
enum Pattern { NONE, SPOTS, STRIPES, FIN }

@export_group("形狀")
## 節數：身體有幾節（含頭）
@export_range(2, 80, 1, "or_greater") var segment_count: int = 16:
	set(value):
		segment_count = clampi(value, 2, MAX_SEGMENTS)
		_resize_joints()
## 間距：每節之間的距離（像素）
@export_range(4, 60, 1) var spacing: float = 14.0:
	set(value):
		spacing = value
		_refresh_preview()
## 最大彎曲角：每節跟前一節最多能彎幾度。越小身體越直，180 等於不限制
@export_range(5, 180, 1, "radians_as_degrees") var max_bend: float = deg_to_rad(30.0)
## 粗細：身體最粗的地方，中心到邊緣的距離（像素）
@export_range(2, 80, 1) var thickness: float = 16.0:
	set(value):
		thickness = value
		queue_redraw()
## 粗細曲線：從頭（左）到尾（右）的粗細比例，1 是最粗
@export var width_curve: Curve = _make_default_curve():
	set(value):
		_watch_resource(width_curve, value)
		width_curve = value
		queue_redraw()
## 每次成長加幾節：吃到一次食物，身體變長幾節
@export_range(0, 10, 1) var segments_per_growth: int = 1
## 全身都有碰撞：勾了每一節都能被咬到，沒勾只有頭
@export var full_body_collision: bool = false

@export_group("動作")
## 游動擺幅（像素）：往前走時身體左右擺動的幅度，0 是不擺。蛇、魚、蝌蚪可以開
@export_range(0, 40, 0.5) var swim_amplitude: float = 0.0
## 游動頻率：每秒擺幾次
@export_range(0, 6, 0.1) var swim_frequency: float = 2.0

@export_group("外觀")
## 身體顏色：從頭（左）到尾（右）的漸層。只放一個顏色就是單色
@export var body_gradient: Gradient = _make_default_gradient():
	set(value):
		_watch_resource(body_gradient, value)
		body_gradient = value
		queue_redraw()
## 外框顏色
@export var outline_color: Color = Color("#cdeccf"):
	set(value):
		outline_color = value
		queue_redraw()
## 外框粗細（像素），0 是沒有外框
@export_range(0, 10, 0.5) var outline_width: float = 2.5:
	set(value):
		outline_width = value
		queue_redraw()
## 花紋
@export_enum("無", "斑點", "條紋", "背鰭") var pattern: int = Pattern.SPOTS:
	set(value):
		pattern = value
		queue_redraw()
## 花紋顏色
@export var pattern_color: Color = Color("#2f6e45"):
	set(value):
		pattern_color = value
		queue_redraw()

## 關節位置（全局座標），[0] 是頭。這是演算法算出來的位置
var _joints: PackedVector2Array = []
## 畫出來的位置（全局座標）＝關節＋游動的左右擺動
var _display: PackedVector2Array = []
## 每一節面向的角度（全局，弧度），朝頭的方向
var _angles: PackedFloat32Array = []
## 游動的相位、強度（停下來時慢慢不擺）
var _swim_phase: float = 0.0
var _swim_strength: float = 0.0
## 上次收到的成長等級，用來算這次要加減幾節
var _last_level: int = 0
## 全身碰撞用的碰撞區（執行時才建立），[0] 對應第 1 節
var _hit_areas: Array[Area2D] = []


func _ready() -> void:
	_watch_resource(null, width_curve)
	_watch_resource(null, body_gradient)
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# 編輯器裡不動，只在生物被拖到別的地方時重擺預覽姿勢
		if _joints.is_empty() or not _joints[0].is_equal_approx(_get_head_position()):
			reset_pose()
		return
	_joints[0] = _get_head_position()
	follow_chain(_get_heading())
	_update_display(delta)
	_update_hit_areas()
	queue_redraw()


# ---------------------------------------------------------------- 演算法


## 鏈條跟隨：每一節拉到「離前一節剛好 spacing 遠」，而且跟前一段的夾角不超過 max_bend。
## _joints[0]（頭）已經由 Creature 移動好了，heading 是頭朝向的角度
func follow_chain(heading: float) -> void:
	var prev_angle: float = heading + PI  # 第 1 節的參考方向：頭的反方向
	for i: int in range(1, _joints.size()):
		var angle: float = (_joints[i] - _joints[i - 1]).angle()  # 這一節現在在前一節的哪個方向
		var diff: float = clampf(angle_difference(prev_angle, angle), -max_bend, max_bend)  # 不能彎太多
		angle = prev_angle + diff
		_joints[i] = _joints[i - 1] + Vector2.from_angle(angle) * spacing  # 拉到剛好 spacing 遠
		prev_angle = angle


# ---------------------------------------------------------------- 對外的功能


## 現在有幾節
func joint_count() -> int:
	return _joints.size()


## 第 index 節畫出來的位置（全局座標）。-1 是最後一節，超出範圍也當最後一節
func get_joint(index: int) -> Vector2:
	if _display.is_empty():
		return _get_head_position()
	return _display[resolve_index(index)]


## 第 index 節面向的角度（全局，弧度），朝頭的方向
func get_angle(index: int) -> float:
	if _angles.is_empty():
		return _get_heading()
	return _angles[resolve_index(index)]


## 第 index 節的粗細（中心到邊緣，像素）
func get_width(index: int) -> float:
	var t: float = float(resolve_index(index)) / float(maxi(joint_count() - 1, 1))
	var ratio: float = width_curve.sample(t) if width_curve != null else 1.0
	return maxf(thickness * ratio, 0.5)


## 把「第幾節」換成實際的索引：負數從尾巴往回數（-1 是最後一節），超出範圍就是最後一節
func resolve_index(index: int) -> int:
	var count: int = maxi(joint_count(), 1)
	if index < 0:
		index += count
	if index < 0 or index >= count:
		return count - 1
	return index


## 加 amount 節（加在尾巴後面）
func add_segments(amount: int) -> void:
	segment_count += amount


## 減 amount 節（從尾巴拿掉），最少留 2 節
func remove_segments(amount: int) -> void:
	segment_count -= amount


## Creature 長大或變短時呼叫：等級每差 1，就加減 segments_per_growth 節
func on_grow(level: int) -> void:
	var change: int = (level - _last_level) * segments_per_growth
	_last_level = level
	segment_count += change


## 預覽姿勢：從頭往頭的反方向拉成一直線
func reset_pose() -> void:
	var head: Vector2 = _get_head_position()
	var back: Vector2 = Vector2.from_angle(_get_heading() + PI)
	_joints.resize(segment_count)
	for i: int in segment_count:
		_joints[i] = head + back * spacing * i
	_update_display(0.0)
	queue_redraw()


# ---------------------------------------------------------------- 內部處理


## 節數改變時：加的節接在尾巴後面、沿著尾巴的方向（不會從原點飛過來）；減的從尾巴拿掉
func _resize_joints() -> void:
	if not is_inside_tree() or _joints.is_empty():
		return
	if Engine.is_editor_hint():
		reset_pose()
		return
	while _joints.size() > segment_count:
		_joints.remove_at(_joints.size() - 1)
	while _joints.size() < segment_count:
		var last: Vector2 = _joints[-1]
		var tail_dir: Vector2 = _joints[-2].direction_to(last) if _joints.size() >= 2 else Vector2.from_angle(_get_heading() + PI)
		if tail_dir == Vector2.ZERO:
			tail_dir = Vector2.from_angle(_get_heading() + PI)
		_joints.append(last + tail_dir * spacing)
	_update_display(0.0)
	_sync_hit_areas()


## 算出畫圖用的位置和角度：關節＋往前走時的左右擺動
func _update_display(delta: float) -> void:
	var creature: Creature = _get_creature()
	var moving: float = 0.0
	if creature != null and not Engine.is_editor_hint():
		moving = clampf(creature.velocity.length() / maxf(creature.speed, 1.0), 0.0, 1.0)
	_swim_strength = lerpf(_swim_strength, moving, 1.0 - exp(-5.0 * delta))
	_swim_phase = fmod(_swim_phase + TAU * swim_frequency * _swim_strength * delta, TAU)

	var count: int = _joints.size()
	_display.resize(count)
	_angles.resize(count)
	for i: int in count:
		_angles[i] = _get_heading() if i == 0 else (_joints[i - 1] - _joints[i]).angle()
		# 波從頭往尾巴傳；頭附近擺得小，才不會整顆頭在晃
		var wave: float = sin(_swim_phase - i * 0.6) * swim_amplitude * _swim_strength * minf(i / 3.0, 1.0)
		_display[i] = _joints[i] + Vector2.from_angle(_angles[i] + PI / 2.0) * wave
	for i: int in range(1, count):
		_angles[i] = (_display[i - 1] - _display[i]).angle()


func _refresh_preview() -> void:
	if is_inside_tree() and Engine.is_editor_hint():
		reset_pose()
	queue_redraw()


## Curve、Gradient 在檢查器裡被修改時也要重畫
func _watch_resource(old_resource: Resource, new_resource: Resource) -> void:
	if old_resource != null and old_resource.changed.is_connected(queue_redraw):
		old_resource.changed.disconnect(queue_redraw)
	if new_resource != null and not new_resource.changed.is_connected(queue_redraw):
		new_resource.changed.connect(queue_redraw)


func _get_creature() -> Creature:
	return get_parent() as Creature


## 頭的位置：有 Creature 就是 Creature 的位置，單獨使用時是自己的位置
func _get_head_position() -> Vector2:
	var creature: Creature = _get_creature()
	return creature.global_position if creature != null else global_position


func _get_heading() -> float:
	var creature: Creature = _get_creature()
	return creature.heading if creature != null else global_rotation


## 全身碰撞：每一節（頭以外）一個圓形碰撞區，執行時才建立
func _sync_hit_areas() -> void:
	if Engine.is_editor_hint() or not full_body_collision or not is_inside_tree():
		return
	var creature: Creature = _get_creature()
	while _hit_areas.size() > joint_count() - 1:
		_hit_areas.pop_back().queue_free()
	while _hit_areas.size() < joint_count() - 1:
		var area := Area2D.new()
		area.set_meta("creature", creature)
		if creature != null and creature.head_area != null:
			area.collision_layer = creature.head_area.collision_layer
			area.collision_mask = creature.head_area.collision_mask
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		area.add_child(shape)
		add_child(area)
		_hit_areas.append(area)
	for i: int in _hit_areas.size():
		((_hit_areas[i].get_child(0) as CollisionShape2D).shape as CircleShape2D).radius = get_width(i + 1)


func _update_hit_areas() -> void:
	if _hit_areas.is_empty() and full_body_collision:
		_sync_hit_areas()
	for i: int in _hit_areas.size():
		_hit_areas[i].global_position = _display[i + 1]


static func _make_default_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.75))  # 頭稍細
	curve.add_point(Vector2(0.2, 1.0))  # 脖子後面最粗
	curve.add_point(Vector2(1.0, 0.1))  # 尾巴尖
	return curve


static func _make_default_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0])
	gradient.colors = PackedColorArray([Color("#4f9d69")])
	return gradient


# ---------------------------------------------------------------- 畫圖


func _draw() -> void:
	if _display.size() < 2:
		return
	var outline: Array = _build_outline()
	var points: PackedVector2Array = outline[0]
	var colors: PackedColorArray = []
	for t: float in outline[1]:
		colors.append(_body_color(t))

	# 身體彎太急時，兩側輪廓會交叉，整個多邊形畫不出來。這一幀改成一節一節畫圓
	if Geometry2D.triangulate_polygon(points).is_empty():
		_draw_fallback()
	else:
		draw_polygon(points, colors)
		_draw_pattern()
		if outline_width > 0.0:
			points.append(points[0])
			draw_polyline(points, outline_color, outline_width, true)

	if CreatureDebug.bones_visible(self):
		_draw_bones()


## 沿著骨架兩側算出輪廓點（本地座標），再讓它變圓滑。
## 回傳 [輪廓點, 每個點在身體上的位置 0～1（頭 0、尾 1，用來取顏色）]
func _build_outline() -> Array:
	var count: int = _display.size()
	var right: PackedVector2Array = []
	var left: PackedVector2Array = []
	var side_ts: PackedFloat32Array = []
	for i: int in count:
		right.append(_side_point(i, PI / 2.0))
		left.append(_side_point(i, -PI / 2.0))
		side_ts.append(float(i) / (count - 1))
	right = _smooth(right)
	left = _smooth(left)
	var smooth_ts: PackedFloat32Array = _smooth_ts(side_ts)

	var points: PackedVector2Array = []
	var ts: PackedFloat32Array = []
	# 右側：頭 → 尾
	points.append_array(right)
	ts.append_array(smooth_ts)
	# 尾巴的圓弧：從右側繞到左側
	_add_cap(points, ts, count - 1, _local_angle(count - 1) + PI / 2.0, 1.0)
	# 左側：尾 → 頭
	for i: int in range(left.size() - 1, -1, -1):
		points.append(left[i])
		ts.append(smooth_ts[i])
	# 頭的圓弧：從左側繞過前面回到右側
	_add_cap(points, ts, 0, _local_angle(0) - PI / 2.0, 0.0)
	return [points, ts]


## 第 i 節往 side 方向（右 +90°、左 -90°）偏一個粗細的點
func _side_point(i: int, side: float) -> Vector2:
	return to_local(_display[i]) + Vector2.from_angle(_local_angle(i) + side) * get_width(i)


## 在第 i 節畫半圓（從 start_angle 轉半圈），頭和尾巴才會是圓的
func _add_cap(points: PackedVector2Array, ts: PackedFloat32Array, i: int, start_angle: float, t: float) -> void:
	for k: int in range(1, 7):
		var angle: float = start_angle + PI * k / 7.0
		points.append(to_local(_display[i]) + Vector2.from_angle(angle) * get_width(i))
		ts.append(t)


## 四點細分：身體一側的每兩個點中間插一個點，讓輪廓變圓滑（頭尾的圓弧不用）
func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = []
	var last: int = points.size() - 1
	for i: int in last:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, last)]
		result.append(p1)
		result.append((-p0 + p1 * 9.0 + p2 * 9.0 - p3) / 16.0)
	result.append(points[last])
	return result


## 跟 _smooth() 一樣插點，用在「在身體上的位置」（取顏色用）
func _smooth_ts(ts: PackedFloat32Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = []
	for i: int in ts.size() - 1:
		result.append(ts[i])
		result.append((ts[i] + ts[i + 1]) / 2.0)
	result.append(ts[-1])
	return result


## 第 i 節的角度（本地座標）
func _local_angle(i: int) -> float:
	return _angles[i] - global_rotation


func _body_color(t: float) -> Color:
	return body_gradient.sample(t) if body_gradient != null else Color("#4f9d69")


## 備用畫法（身體捲成一圈、尾巴碰到頭時用）：沿著骨架排一串圓連成管子。
## 先畫一串比較大的外框色圓，再疊上身體色的圓，看起來跟正常畫法差不多
func _draw_fallback() -> void:
	var circles: Array[Vector3] = []  # x、y 是位置，z 是半徑
	var colors: PackedColorArray = []
	var last: int = _display.size() - 1
	for i: int in last:
		for step: int in FALLBACK_STEPS:
			var t: float = float(step) / FALLBACK_STEPS
			var center: Vector2 = to_local(_display[i].lerp(_display[i + 1], t))
			circles.append(Vector3(center.x, center.y, lerpf(get_width(i), get_width(i + 1), t)))
			colors.append(_body_color((i + t) / last))
	var tail: Vector2 = to_local(_display[last])
	circles.append(Vector3(tail.x, tail.y, get_width(last)))
	colors.append(_body_color(1.0))
	if outline_width > 0.0:
		for circle: Vector3 in circles:
			draw_circle(Vector2(circle.x, circle.y), circle.z + outline_width, outline_color, true, -1.0, true)
	for k: int in range(circles.size() - 1, -1, -1):
		draw_circle(Vector2(circles[k].x, circles[k].y), circles[k].z, colors[k], true, -1.0, true)
	_draw_pattern()


func _draw_pattern() -> void:
	match pattern:
		Pattern.SPOTS:
			_draw_spots()
		Pattern.STRIPES:
			_draw_stripes()
		Pattern.FIN:
			_draw_fin()


## 斑點：每隔一節畫一個圓點，左右交錯
func _draw_spots() -> void:
	for i: int in range(1, _display.size() - 1, 2):
		var side: float = 0.4 if i % 4 == 1 else -0.4
		var center: Vector2 = to_local(_display[i]) + Vector2.from_angle(_local_angle(i) + PI / 2.0) * get_width(i) * side
		draw_circle(center, get_width(i) * 0.22, pattern_color, true, -1.0, true)


## 條紋：每隔一節畫一條橫線
func _draw_stripes() -> void:
	for i: int in range(2, _display.size() - 1, 2):
		var across: Vector2 = Vector2.from_angle(_local_angle(i) + PI / 2.0) * get_width(i) * 0.85
		var center: Vector2 = to_local(_display[i])
		draw_line(center + across, center - across, pattern_color, maxf(2.0, get_width(i) * 0.3), true)


## 背鰭：沿著背上中線，每節一個往後的小三角形
func _draw_fin() -> void:
	for i: int in range(1, _display.size() - 1):
		var center: Vector2 = to_local(_display[i])
		var back: Vector2 = Vector2.from_angle(_local_angle(i) + PI) * spacing * 0.8
		var side: Vector2 = Vector2.from_angle(_local_angle(i) + PI / 2.0) * get_width(i) * 0.2
		draw_colored_polygon(PackedVector2Array([center + side, center + back, center - side]), pattern_color)


## 骨架（F1）：每節的距離圓、骨架線、關節點，畫的是演算法算出來的關節（沒有游動擺動）
func _draw_bones() -> void:
	var bone_points: PackedVector2Array = []
	for joint: Vector2 in _joints:
		bone_points.append(to_local(joint))
	var faint: Color = CreatureDebug.BONE_COLOR
	faint.a = 0.25
	for point: Vector2 in bone_points:
		draw_arc(point, spacing, 0.0, TAU, 24, faint, 1.0, true)
	draw_polyline(bone_points, CreatureDebug.BONE_COLOR, 1.0, true)
	for point: Vector2 in bone_points:
		draw_circle(point, 2.5, CreatureDebug.BONE_COLOR)
