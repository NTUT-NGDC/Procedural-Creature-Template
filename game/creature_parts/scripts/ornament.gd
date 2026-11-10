@tool
class_name Ornament
extends CreaturePart
## 掛件：掛在某一節上、跟著那一節移動和旋轉的裝飾（角、翅膀、魚鰭、天線、帽子……）。
##
## 兩種用法：
##   ・選一個內建「形狀」，不用畫圖
##   ・形狀選「無」，在這個節點底下放自己的東西（Sprite2D 放自己畫的 PNG、Polygon2D 點出形狀）
## 「兩邊」時只要放一張圖，右邊會自動翻過來變成一對。
##
## 自己畫圖時：圖的「根部」放在節點原點，往右（+x）是往外伸的方向。
## 每種內建形狀都是一個短函式（draw_horn()、draw_wing()……），可以照著改，畫自己的形狀。

## 形狀、動法的編號，跟選單的順序一樣
enum Shape { NONE, CIRCLE, ELLIPSE, TRIANGLE, HORN, WING, FIN, LEAF, STAR, HEART }
enum Motion { FIXED, FLAP, SPRING }

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭，-1 是最後一節
@export_range(-1, 80, 1, "or_greater") var attach_segment: int = 0:
	set(value):
		attach_segment = value
		reset_pose()
## 掛在哪一邊：兩邊會畫左右一對（右邊是左邊翻過來的）
@export_enum("左", "右", "兩邊", "中間") var side: int = Side.CENTER:
	set(value):
		side = value
		reset_pose()
## 位置偏移（像素）：x 是往前、y 是往外
@export var offset: Vector2 = Vector2.ZERO:
	set(value):
		offset = value
		reset_pose()
## 角度：0 是朝前、90 是朝外、180 是朝後
@export_range(-180, 180, 1, "radians_as_degrees") var angle: float = 0.0:
	set(value):
		angle = value
		reset_pose()

@export_group("形狀")
## 內建形狀。選「無」就只顯示放在這個節點底下的東西（例如自己畫的圖）
@export_enum("無", "圓", "橢圓", "三角形", "角", "翅膀", "魚鰭", "葉子", "星星", "愛心") var shape: int = Shape.HORN:
	set(value):
		shape = value
		queue_redraw()
## 大小：1 是原本的大小，底下放的圖也會一起縮放
@export_range(0.1, 5, 0.05) var size: float = 1.0:
	set(value):
		size = value
		reset_pose()

@export_group("外觀")
## 顏色：形狀從根部（左）到尖端（右）的漸層。只放一個顏色就是單色
@export var color_gradient: Gradient = _make_default_gradient():
	set(value):
		if color_gradient != null and color_gradient.changed.is_connected(queue_redraw):
			color_gradient.changed.disconnect(queue_redraw)
		color_gradient = value
		if color_gradient != null and not color_gradient.changed.is_connected(queue_redraw):
			color_gradient.changed.connect(queue_redraw)
		queue_redraw()
## 外框：顏色和粗細跟身體一樣，畫風才統一
@export var outline: bool = true:
	set(value):
		outline = value
		queue_redraw()
## 畫在身體上面：開＝畫在身體上面（角、帽子），關＝畫在身體下面（翅膀、腳邊的鰭）
@export var on_top: bool = true:
	set(value):
		on_top = value
		show_behind_parent = not on_top

@export_group("動作")
## 動法：固定、拍動（翅膀、魚鰭、耳朵來回擺）、彈簧（天線、呆毛：轉彎時晚一點跟上、晃一晃）
@export_enum("固定", "拍動", "彈簧") var motion: int = Motion.FIXED
## 拍動幅度：來回擺幾度
@export_range(0, 90, 1, "radians_as_degrees") var flap_amplitude: float = deg_to_rad(30.0)
## 拍動速度
@export_range(0, 20, 0.1) var flap_speed: float = 4.0
## 彈簧硬度：越大跟得越緊，越小越軟、晃得越久
@export_range(1, 30, 0.5) var spring_stiffness: float = 8.0

## 拍動用的時間
var _time: float = 0.0
## 彈簧：現在的角度、角速度（全局，弧度）
var _spring_angle: float = 0.0
var _spring_velocity: float = 0.0
var _spring_started: bool = false
## 「兩邊」時右邊那份子節點（執行時才建立）
var _mirror: Node2D


func _ready() -> void:
	show_behind_parent = not on_top
	if color_gradient != null and not color_gradient.changed.is_connected(queue_redraw):
		color_gradient.changed.connect(queue_redraw)
	if not Engine.is_editor_hint():
		_create_mirror()
	reset_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		editor_follow_anchor(anchor_position(attach_segment, 1.0) + Vector2.from_angle(anchor_angle(attach_segment)))
		return
	_time += delta
	update_spring(delta)
	_apply_transforms()
	queue_redraw()


# ---------------------------------------------------------------- 動作


## 彈簧：角度被拉向那一節的方向（回復力），再加上阻力，所以會晃過頭再慢慢停下來
func update_spring(delta: float) -> void:
	var target: float = anchor_angle(attach_segment)
	if not _spring_started:
		_spring_angle = target
		_spring_started = true
	var error: float = angle_difference(target, _spring_angle)  # 現在偏了多少
	var force: float = -spring_stiffness * spring_stiffness * error  # 回復力：偏越多拉越大力
	var damping: float = -0.6 * spring_stiffness * _spring_velocity  # 阻力：越快擋越多
	_spring_velocity += (force + damping) * delta
	_spring_angle += _spring_velocity * delta


## 拍動：來回擺的角度（左右對稱，在 frame_transform() 裡乘上左右）
func _flap_angle() -> float:
	return sin(_time * flap_speed) * flap_amplitude if motion == Motion.FLAP else 0.0


## 彈簧：比那一節的方向慢了多少（左右一起慢），最多 90 度
func _spring_lag() -> float:
	if motion != Motion.SPRING:
		return 0.0
	return clampf(angle_difference(anchor_angle(attach_segment), _spring_angle), -PI / 2.0, PI / 2.0)


# ---------------------------------------------------------------- 位置


## 第 k 個（左、右或中間）掛件的變換：位置、角度、大小，右邊用 scale.y = -1 翻過去
func frame_transform(k: int) -> Transform2D:
	var signs: PackedFloat32Array = side_signs(side)
	var side_sign: float = signs[k] if signs[k] != 0.0 else 1.0
	var mirror: float = -1.0 if signs[k] > 0.0 else 1.0
	var forward: Vector2 = Vector2.from_angle(anchor_angle(attach_segment))
	var outward: Vector2 = forward.rotated(PI / 2.0) * side_sign
	var origin: Vector2 = anchor_position(attach_segment, signs[k]) + forward * offset.x + outward * offset.y
	# 角度往「外」算：左邊逆時針、右邊順時針，左右才會對稱
	var rotation_angle: float = anchor_angle(attach_segment) + (angle + _flap_angle()) * side_sign + _spring_lag()
	return Transform2D(rotation_angle, Vector2(size, size * mirror), 0.0, origin)


## 把這個節點擺到第一個掛件的位置（底下的圖會跟著），右邊那份擺到第二個位置
func _apply_transforms() -> void:
	if not is_inside_tree():
		return
	global_transform = frame_transform(0)
	if _mirror != null and side_signs(side).size() > 1:
		_mirror.transform = frame_transform(0).affine_inverse() * frame_transform(1)


## 「兩邊」時，把底下的子節點複製一份給右邊（執行時才做，不會存進場景）
func _create_mirror() -> void:
	if side != Side.BOTH or get_child_count() == 0:
		return
	_mirror = Node2D.new()
	_mirror.name = "MirrorSide"
	for child: Node in get_children():
		_mirror.add_child(child.duplicate())
	add_child(_mirror)


## 預覽姿勢：擺到掛載點上
func reset_pose() -> void:
	_spring_started = false
	_apply_transforms()
	queue_redraw()


static func _make_default_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color("#2f6e45"), Color("#a8dcb4")])
	return gradient


# ---------------------------------------------------------------- 畫圖


func _draw() -> void:
	if shape == Shape.NONE or not is_inside_tree():
		return
	for k: int in side_signs(side).size():
		draw_set_transform_matrix(global_transform.affine_inverse() * frame_transform(k))
		match shape:
			Shape.CIRCLE:
				draw_circle_shape()
			Shape.ELLIPSE:
				draw_ellipse_shape()
			Shape.TRIANGLE:
				draw_triangle_shape()
			Shape.HORN:
				draw_horn()
			Shape.WING:
				draw_wing()
			Shape.FIN:
				draw_fin()
			Shape.LEAF:
				draw_leaf()
			Shape.STAR:
				draw_star()
			Shape.HEART:
				draw_heart()
	draw_set_transform_matrix(Transform2D.IDENTITY)


## 以下每種形狀都是一串點（根部在原點，往 +x 伸出去），交給 fill_shape() 填色、畫外框

func draw_circle_shape() -> void:
	fill_shape(_ellipse_points(Vector2(10, 0), 10.0, 10.0))


func draw_ellipse_shape() -> void:
	fill_shape(_ellipse_points(Vector2(14, 0), 14.0, 8.0))


func draw_triangle_shape() -> void:
	fill_shape(PackedVector2Array([Vector2(0, -9), Vector2(22, 0), Vector2(0, 9)]))


## 角：根部粗、尖端往後彎
func draw_horn() -> void:
	fill_shape(PackedVector2Array([
		Vector2(0, -7), Vector2(7, -7), Vector2(14, -9), Vector2(20, -12), Vector2(26, -17),
		Vector2(19, -4), Vector2(11, 3), Vector2(4, 6), Vector2(0, 7)]))


## 翅膀：前緣直、後緣是波浪（像蝙蝠或龍的翅膀）
func draw_wing() -> void:
	fill_shape(PackedVector2Array([
		Vector2(0, 5), Vector2(14, 9), Vector2(30, 7), Vector2(40, 2),
		Vector2(32, -6), Vector2(26, -2), Vector2(19, -13), Vector2(11, -6), Vector2(4, -12), Vector2(0, -6)]))


## 魚鰭：往後掃的三角形
func draw_fin() -> void:
	fill_shape(PackedVector2Array([Vector2(0, 6), Vector2(12, 3), Vector2(22, -10), Vector2(9, -8), Vector2(0, -6)]))


## 葉子：兩端尖、中間胖，加一條葉脈
func draw_leaf() -> void:
	var points: PackedVector2Array = []
	for i: int in 13:
		var t: float = i / 12.0
		points.append(Vector2(26.0 * t, -8.0 * sin(PI * t)))
	for i: int in range(11, 0, -1):
		var t: float = i / 12.0
		points.append(Vector2(26.0 * t, 8.0 * sin(PI * t)))
	fill_shape(points)
	draw_line(Vector2.ZERO, Vector2(24, 0), _outline_color(), 1.0 / size, true)


## 星星：五個尖角
func draw_star() -> void:
	var points: PackedVector2Array = []
	for i: int in 10:
		var radius: float = 12.0 if i % 2 == 0 else 5.0
		points.append(Vector2(12, 0) + Vector2.from_angle(TAU * i / 10.0) * radius)
	fill_shape(points)


## 愛心：用愛心曲線的公式算點，尖端朝外
func draw_heart() -> void:
	var points: PackedVector2Array = []
	for i: int in 32:
		var t: float = TAU * i / 32.0
		var heart: Vector2 = Vector2(16.0 * pow(sin(t), 3), 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		points.append(Vector2(10.0 - heart.y * 0.7, heart.x * 0.7))
	fill_shape(points)


## 填色（根部到尖端的漸層）＋外框
func fill_shape(points: PackedVector2Array) -> void:
	var max_x: float = 1.0
	for point: Vector2 in points:
		max_x = maxf(max_x, point.x)
	var colors: PackedColorArray = []
	for point: Vector2 in points:
		colors.append(_gradient_color(clampf(point.x / max_x, 0.0, 1.0)))
	draw_polygon(points, colors)
	if outline:
		var closed: PackedVector2Array = points.duplicate()
		closed.append(points[0])
		# 整個形狀被放大了 size 倍，外框粗細要除回來，才會跟身體一樣粗
		draw_polyline(closed, _outline_color(), outline_style().width / size, true)


func _ellipse_points(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i: int in 24:
		points.append(center + Vector2(cos(TAU * i / 24.0) * radius_x, sin(TAU * i / 24.0) * radius_y))
	return points


func _gradient_color(t: float) -> Color:
	return color_gradient.sample(t) if color_gradient != null else Color("#a8dcb4")


func _outline_color() -> Color:
	return outline_style().color
