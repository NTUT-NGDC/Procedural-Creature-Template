extends Control
## 主題課投影片的三條規則動圖（1280 × 720）：左右兩個小畫面，左邊「弄壞」、右邊「修好」，骨架開著。
## 匯出時不會帶進去。錄影（在內層專案資料夾執行，Godot 換成自己的路徑，最後的參數選一個）：
##   Godot --path . --write-movie <資料夾>/frame.png --fixed-fps 20 res://_system/showcase/rules_gif.tscn -- chain
##   chain＝鏈條跟隨（最大彎曲角 150° vs 60°）
##   fabrik＝FABRIK（來回 1 趟 vs 10 趟）
##   legs＝換腳（A、B 兩組輪流 vs 全部同一組）
## 前 WARMUP 秒讓生物先動起來，轉 GIF 時剪掉。

const SCREEN: Vector2i = Vector2i(1280, 720)
const PANEL_SIZE: Vector2i = Vector2i(610, 560)
const WARMUP: float = 1.0
const DURATION: float = 8.0
const YELLOW: Color = Color("#ffd166")
const WATER: Color = Color("#123c46")
## 跟投影片一樣的深藍色
const BACKGROUND: Color = Color("#303870")

## 每個 demo：左右兩邊的標題
const LABELS: Dictionary = {
	"chain": ["最大彎曲角 150°：折成一團", "最大彎曲角 30°：順了"],
	"fabrik": ["只拉一趟（像蛇）：根部被拉走", "來回拉（FABRIK）：根部黏住"],
	"legs": ["A、B 兩組輪流跨：在走路", "全部同一組：變成在跳"],
}

var _kind: String = "chain"
var _time: float = -WARMUP
## 每個小畫面：{"root", "camera", "creature", "target", "guides", "variant"}
var _panels: Array[Dictionary] = []
var _debug: Node


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and LABELS.has(args[0]):
		_kind = args[0]
	get_window().size = SCREEN
	get_window().content_scale_size = SCREEN
	size = Vector2(SCREEN)
	WaterFlow.strength = 0.0
	_debug = get_node_or_null("/root/Debug")
	if _debug != null:
		_debug.set("show_bones", true)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.size = size
	add_child(background)
	for side: int in 2:
		var at := Vector2(20.0 + side * (PANEL_SIZE.x + 20.0), 130.0)
		_add_text(LABELS[_kind][side], 33, YELLOW if side == 1 else Color.WHITE, Vector2(at.x, 50.0), PANEL_SIZE.x)
		_add_panel(at, side)


func _exit_tree() -> void:
	WaterFlow.reset()
	if _debug != null:
		_debug.set("show_bones", false)


func _process(delta: float) -> void:
	_time += delta
	for panel: Dictionary in _panels:
		_update_panel(panel, delta)
	if _time >= DURATION:
		get_tree().quit()


# ---------- 小畫面 ----------

func _add_panel(at: Vector2, variant: int) -> void:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = WATER
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = Color(CreatureDebug.BONE_COLOR, 0.6)
	frame.add_theme_stylebox_override("panel", style)
	frame.position = at
	add_child(frame)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(PANEL_SIZE)
	frame.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = PANEL_SIZE
	viewport.transparent_bg = true
	container.add_child(viewport)
	var root := Node2D.new()
	viewport.add_child(root)
	var camera := Camera2D.new()
	root.add_child(camera)
	var panel: Dictionary = {"root": root, "camera": camera, "variant": variant, "target": null, "guides": null}
	match _kind:
		"chain":
			camera.zoom = Vector2.ONE * 1.3
			var snake: Creature = _make_creature(root, "snake", func(design: CreatureDesign) -> void:
				design.body.max_bend = deg_to_rad(150.0 if variant == 0 else 30.0))
			_place(snake, _figure_eight(-WARMUP), 0.0)
			snake.brain = func() -> Dictionary: return {"angle": snake.heading, "speed": 0.0}  # 頭由 _update_panel 直接搬
			panel.creature = snake
		"fabrik":
			camera.zoom = Vector2.ONE * 1.4
			var arm := ArmDemo.new()
			arm.full_fabrik = variant == 1
			root.add_child(arm)
			panel.arm = arm
			panel.target = _add_target(root)
		"legs":
			camera.zoom = Vector2.ONE * 1.5
			root.add_child(GroundDots.new())
			var spider: Creature = _make_creature(root, "spider", func(design: CreatureDesign) -> void:
				_pink_spider(design, variant == 1))
			var walk: float = spider.speed * 0.45
			_place(spider, Vector2(-200.0, 0.0), 0.0)
			spider.brain = func() -> Dictionary: return {"angle": 0.0, "speed": walk}
			panel.creature = spider
			var guides := StepGuides.new()
			root.add_child(guides)
			panel.guides = guides
	_panels.append(panel)


func _update_panel(panel: Dictionary, _delta: float) -> void:
	var creature: Creature = panel.get("creature")
	match _kind:
		"chain":  # 頭沿著 8 字形走，兩端是急轉彎；身體只靠鏈條跟隨拖著走
			var here: Vector2 = _figure_eight(_time)
			creature.heading = (here - creature.global_position).angle()
			creature.global_position = here
		"fabrik":  # 目標在根部右邊繞一個大圈，有時候超出手臂長度
			var angle: float = _time * 1.6
			var target: Node2D = panel.target
			target.position = Vector2(40.0, 0.0) + Vector2(cos(angle) * 110.0, sin(angle * 1.3) * 120.0)
			(panel.arm as ArmDemo).reach(target.position)
		"legs":  # 鏡頭跟著蜘蛛；走出地圖就整隻搬回左邊
			var camera: Camera2D = panel.camera
			camera.position = Vector2(creature.global_position.x, 0.0)
			var guides: StepGuides = panel.guides
			guides.update_from(creature)


## 蛇頭在第 time 秒的位置：橫躺的 8 字形，左右兩端是急轉彎
func _figure_eight(time: float) -> Vector2:
	var t: float = time * TAU / 2.6
	return Vector2(sin(t) * 120.0, sin(t * 2.0) * 45.0)


func _make_creature(root: Node2D, design_name: String, change: Callable) -> Creature:
	var design: CreatureDesign = load("res://example/creatures/%s/design.tres" % design_name)
	design = design.duplicate(true)
	change.call(design)
	var creature := Creature.new()
	creature.design = design
	creature.control_mode = Creature.Mode.WANDER
	creature.bounds = Rect2(-100000, -2000, 200000, 4000)
	root.add_child(creature)
	return creature


func _place(creature: Creature, at: Vector2, heading: float) -> void:
	creature.global_position = at
	creature.heading = heading
	creature.reset_pose()


## 蜘蛛換成粉紅色（深紫色在深色底上看不清楚）；same_group 打勾就把每隻腳都設成 A 組
func _pink_spider(design: CreatureDesign, same_group: bool) -> void:
	var color: Color = Color(1.0, 0.44, 0.57)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color.lightened(0.15), color.darkened(0.2)])
	design.body.body_gradient = gradient
	design.body.outline_color = color.lightened(0.55)
	for leg: LegDesign in design.legs:
		leg.leg_color = color.lightened(0.25)
		leg.lift_height = 10.0
		if same_group:
			leg.group = IKLeg.Group.A


func _add_target(root: Node2D) -> Node2D:
	var target := TargetCross.new()
	root.add_child(target)
	return target


func _add_text(text: String, font_size: int, color: Color, at: Vector2, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = at
	label.size = Vector2(width, font_size * 1.5)
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = color
	label.label_settings = settings
	add_child(label)


## 目標：明顯的十字（骨架的顏色）
class TargetCross:
	extends Node2D

	func _draw() -> void:
		var color: Color = CreatureDebug.BONE_COLOR
		draw_line(Vector2(-10, 0), Vector2(10, 0), color, 2.0)
		draw_line(Vector2(0, -10), Vector2(0, 10), color, 2.0)
		draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(color, 0.6), 1.0)


## 一條觸手的 FABRIK 示範（跟 Tentacle.fabrik() 一樣的寫法）：
## full_fabrik 沒打勾＝只做「① 尖端拉到目標、往根部拉」，根部會被拖走（就是蛇的鏈條跟隨）；
## 打勾＝再做「② 根部放回原位、往尖端推」，根部黏住
class ArmDemo:
	extends Node2D

	const ANCHOR: Vector2 = Vector2(-150.0, 0.0)
	const SEGMENTS: int = 10
	const SEG_LEN: float = 22.0
	const ARM_COLOR: Color = Color("#e48ad8")

	var full_fabrik: bool = false
	var chain: PackedVector2Array = []

	func _init() -> void:
		for i: int in SEGMENTS + 1:
			chain.append(ANCHOR + Vector2(SEG_LEN * i, 0.0))

	func reach(target: Vector2) -> void:
		for _i: int in (3 if full_fabrik else 1):
			chain[-1] = target  # ① 尖端放到目標
			for i: int in range(chain.size() - 2, -1, -1):
				chain[i] = chain[i + 1] + chain[i + 1].direction_to(chain[i]) * SEG_LEN  # 往根部一節一節拉
			if not full_fabrik:
				break
			chain[0] = ANCHOR  # ② 根部放回原位
			for i: int in range(1, chain.size()):
				chain[i] = chain[i - 1] + chain[i - 1].direction_to(chain[i]) * SEG_LEN  # 往尖端一節一節推
		queue_redraw()

	func _draw() -> void:
		var bone: Color = CreatureDebug.BONE_COLOR
		# 身體（觸手黏住的地方）
		draw_circle(ANCHOR + Vector2(-34.0, 0.0), 40.0, Color("#8e4fb5"))
		draw_circle(ANCHOR + Vector2(-48.0, -12.0), 6.0, Color.WHITE)
		draw_circle(ANCHOR + Vector2(-48.0, 12.0), 6.0, Color.WHITE)
		# 根部該黏的位置：紅圈
		draw_arc(ANCHOR, 12.0, 0.0, TAU, 24, Color("#ff5a5a"), 3.0, true)
		# 觸手：越往尖端越細
		for i: int in chain.size() - 1:
			var width: float = lerpf(16.0, 5.0, float(i) / SEGMENTS)
			draw_line(chain[i], chain[i + 1], ARM_COLOR, width, true)
			draw_circle(chain[i + 1], width * 0.5, ARM_COLOR)
		draw_circle(chain[0], 8.0, ARM_COLOR)
		# 骨架
		draw_polyline(chain, bone, 1.5, true)
		for point: Vector2 in chain:
			draw_circle(point, 3.0, bone)


## 地上的點點：鏡頭跟著蜘蛛走，有點點才看得出腳掌釘在地上
class GroundDots:
	extends Node2D

	func _draw() -> void:
		for x: int in range(-600, 4000, 40):
			for y: int in range(-200, 220, 40):
				draw_circle(Vector2(x, y), 2.5, Color(1, 1, 1, 0.3))


## 跨步的輔助線：理想落腳點（點）、跨步圓圈（腳掌離開這個圈就換一步）、腳掌到落腳點的線，每一幀重畫
class StepGuides:
	extends Node2D

	var rests: PackedVector2Array = []
	var feet: PackedVector2Array = []
	var radii: PackedFloat32Array = []

	func update_from(creature: Creature) -> void:
		rests.clear()
		feet.clear()
		radii.clear()
		for node: Node in creature.find_children("*", "IKLeg", true, false):
			var leg: IKLeg = node as IKLeg
			var leg_feet: PackedVector2Array = leg.get("_feet")
			var signs: PackedFloat32Array = CreaturePart.side_signs(leg.side)
			for k: int in mini(leg_feet.size(), signs.size()):
				rests.append(leg.call("_rest_point", signs[k]))
				feet.append(leg_feet[k])
				radii.append(leg.step_distance)
		queue_redraw()

	func _draw() -> void:
		var color: Color = CreatureDebug.BONE_COLOR
		for i: int in rests.size():
			draw_arc(rests[i], radii[i], 0.0, TAU, 32, Color(color, 0.6), 2.0, true)
			draw_circle(rests[i], 3.0, color)
			draw_line(feet[i], rests[i], Color(color, 0.6), 1.5, true)
