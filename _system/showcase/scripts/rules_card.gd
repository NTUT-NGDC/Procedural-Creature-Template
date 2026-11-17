extends Control
## IG 輪播第 2 張「怎麼做到的？」（1080 × 1350）：三列，每列左邊一張骨架截圖、右邊兩行字。
## 左邊的三個小畫面各自跑一隻生物（骨架開著），等到「看得出規則」的那一刻就定格，三個都定格後存圖：
##   蛇：一邊左右擺頭一邊往前游，身體彎成 S 形，頭游到右邊就定格
##   觸手：章魚多一條「抓最近的食物」的長觸手，伸向目標十字、快碰到時定格
##   蜘蛛：往右走，走到中間、剛好有一隻腳在半空中時定格
## 存到外層 repo 的 docs/promo/rules.png。
##   Godot --path . res://_system/showcase/rules_card.tscn

## 畫面大小（IG 直式 4:5）
const SCREEN: Vector2i = Vector2i(1080, 1350)
## 每張骨架截圖的大小
const PANEL_SIZE: Vector2i = Vector2i(460, 290)
## 等太久還沒定格就直接存（秒）
const TIMEOUT: float = 20.0
const YELLOW: Color = Color("#ffd166")
const WATER: Color = Color("#123c46")

## 大標題
@export var title: String = "怎麼做到的？"
## 標題下面的小字
@export var subtitle: String = "只有三條規則"
## 三列的字：每列兩行（規則、例子）
@export var rule_lines: PackedStringArray = ["① 跟著前一節走", "蛇、尾巴", "② 尖端伸向目標", "觸手、手臂", "③ 腳跟不上就跨下一步", "蜈蚣、蜘蛛"]
## 最下面的字（一行一句）
@export var footer_lines: PackedStringArray = ["規則都幫大家寫好了，", "只需要調整參數就能做出自己的生物"]
## 背景顏色
@export var background_color: Color = Color("#0b1e24")

## 每個小畫面：{"kind", "root", "creature", "frozen", "food"}
var _panels: Array[Dictionary] = []
var _time: float = 0.0
var _saved: bool = false
var _debug: Node


func _ready() -> void:
	get_window().borderless = true
	get_window().size = SCREEN
	get_window().position = Vector2i.ZERO
	get_window().content_scale_size = SCREEN
	size = Vector2(SCREEN)
	WaterFlow.strength = 0.0
	_debug = get_node_or_null("/root/Debug")
	if _debug != null:
		_debug.set("show_bones", true)

	var background := ColorRect.new()
	background.color = background_color
	background.size = size
	add_child(background)
	_add_text(title, 66, YELLOW, Vector2(0, 45), SCREEN.x, HORIZONTAL_ALIGNMENT_CENTER)
	_add_text(subtitle, 44, Color.WHITE, Vector2(0, 135), SCREEN.x, HORIZONTAL_ALIGNMENT_CENTER)
	var kinds: PackedStringArray = ["snake", "tentacle", "legs"]
	for row: int in 3:
		var top: float = 225.0 + row * (PANEL_SIZE.y + 30.0)
		_add_panel(kinds[row], Vector2(60, top))
		var text_x: float = 60.0 + PANEL_SIZE.x + 30.0
		var text_width: float = SCREEN.x - text_x - 40.0
		_add_text(rule_lines[row * 2], 44, YELLOW, Vector2(text_x, top + PANEL_SIZE.y / 2.0 - 64.0), text_width, HORIZONTAL_ALIGNMENT_LEFT)
		_add_text(rule_lines[row * 2 + 1], 33, Color(1, 1, 1, 0.85), Vector2(text_x, top + PANEL_SIZE.y / 2.0 + 10.0), text_width, HORIZONTAL_ALIGNMENT_LEFT)
	for i: int in footer_lines.size():
		_add_text(footer_lines[i], 44, YELLOW, Vector2(0, 1180 + i * 66), SCREEN.x, HORIZONTAL_ALIGNMENT_CENTER)


func _exit_tree() -> void:
	if _debug != null:
		_debug.set("show_bones", false)


func _process(delta: float) -> void:
	_time += delta
	var all_frozen: bool = true
	for panel: Dictionary in _panels:
		if panel.frozen:
			continue
		_update_panel(panel)
		if _ready_to_freeze(panel):
			(panel.root as Node).process_mode = Node.PROCESS_MODE_DISABLED  # 整個小畫面停住
			panel.frozen = true
			print("定格：", panel.kind, "（第 %.2f 秒）" % _time)
		else:
			all_frozen = false
	if not _saved and (all_frozen or _time > TIMEOUT):
		_saved = true
		_save()


# ---------- 小畫面 ----------

## 一張骨架截圖：SubViewport 裡放一隻生物＋鏡頭，外面包一個有框的面板
func _add_panel(kind: String, at: Vector2) -> void:
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
	var panel: Dictionary = {"kind": kind, "root": root, "frozen": false, "food": null}
	match kind:
		"snake":
			camera.zoom = Vector2.ONE * 1.35
			var snake: Creature = _make_creature(root, "snake", null)
			_pose_s_curve(snake)
			snake.brain = func() -> Dictionary: return {"angle": snake.heading, "speed": 0.0}  # 擺好就不動
			panel.creature = snake
		"tentacle":
			camera.zoom = Vector2.ONE * 1.5
			var octopus: Creature = _make_creature(root, "octopus", _with_reaching_arm)
			_place(octopus, Vector2(-40.0, 10.0), 0.0)
			octopus.brain = func() -> Dictionary: return {"angle": 0.0, "speed": 18.0}
			panel.creature = octopus
		"legs":
			camera.zoom = Vector2.ONE * 1.5
			var spider: Creature = _make_creature(root, "spider", _pink_spider)
			var walk: float = spider.speed * 0.5
			_place(spider, Vector2(-walk * 1.6, 0.0), 0.0)
			spider.brain = func() -> Dictionary: return {"angle": 0.0, "speed": walk}
			panel.creature = spider
	_panels.append(panel)


## 用範例的設計檔放一隻生物（change 可以先改一份複製的設計檔）
func _make_creature(root: Node2D, design_name: String, change: Variant) -> Creature:
	var design: CreatureDesign = load("res://example/creatures/%s/design.tres" % design_name)
	if change is Callable:
		design = design.duplicate(true)
		(change as Callable).call(design)
	var creature := Creature.new()
	creature.design = design
	creature.control_mode = Creature.Mode.WANDER
	creature.bounds = Rect2(-2000, -2000, 4000, 4000)
	root.add_child(creature)
	return creature


## 蜘蛛換成影片裡的粉紅色（原本的深紫色在深色底上看不清楚）
func _pink_spider(design: CreatureDesign) -> void:
	var color: Color = Color(1.0, 0.44, 0.57)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color.lightened(0.15), color.darkened(0.2)])
	design.body.body_gradient = gradient
	design.body.outline_color = color.lightened(0.55)
	for leg: LegDesign in design.legs:
		leg.leg_color = color.lightened(0.25)
		leg.lift_height = 10.0  # 抬高一點，看得出在半空中


## 章魚多一條往右前方伸的長觸手，行為是「抓最近的食物」
func _with_reaching_arm(design: CreatureDesign) -> void:
	var arm: TentacleDesign = design.tentacles[0].duplicate(true)
	arm.side = CreaturePart.Side.RIGHT
	arm.behavior = Tentacle.Behavior.GRAB_FOOD
	arm.length = 130.0
	arm.segment_count = 12
	arm.reach_angle = deg_to_rad(120.0)
	design.tentacles.append(arm)


## 把蛇的身體擺成 S 形：沿著一條正弦曲線，每一節之間的距離都是 spacing（跟遊戲裡一樣）
func _pose_s_curve(snake: Creature) -> void:
	var body: ChainBody = snake.get_body()
	var count: int = body.segment_count
	var joints: PackedVector2Array = []
	var head: Vector2 = Vector2(count * body.spacing * 0.42, 0.0)
	var point: Vector2 = head
	for i: int in count:
		joints.append(point)
		# 往左走一節：方向跟著正弦曲線的斜率轉
		var slope: float = cos(point.x / 34.0) * 0.95
		point += Vector2(-1.0, slope).normalized() * body.spacing
	var center: Vector2 = Vector2.ZERO
	for joint: Vector2 in joints:
		center += joint / joints.size()
	for i: int in joints.size():
		joints[i] -= center
	snake.global_position = joints[0]
	snake.heading = (joints[0] - joints[1]).angle()
	body.set_joints(joints)


func _place(creature: Creature, at: Vector2, heading: float) -> void:
	creature.global_position = at
	creature.heading = heading
	creature.reset_pose()


## 觸手那張：1 秒後在章魚右前方放一個看不見的目標（加上十字），觸手會伸過去
func _update_panel(panel: Dictionary) -> void:
	if panel.kind != "tentacle" or _time < 1.0:
		return
	var food: Node2D = panel.food
	if food != null and is_instance_valid(food) and food.is_in_group("food"):
		return
	var creature: Creature = panel.creature
	var target := TargetCross.new()
	target.global_position = creature.global_position + Vector2(80.0, -40.0)  # 比觸手短、偏一邊，觸手才會彎過去
	target.add_to_group("food")
	(panel.root as Node2D).add_child(target)
	panel.food = target


## 「看得出規則」的那一刻
func _ready_to_freeze(panel: Dictionary) -> bool:
	var creature: Creature = panel.creature
	match panel.kind:
		"snake":  # 擺好 S 形之後等一下，讓畫面跟上
			return _time > 0.5
		"tentacle":  # 觸手快碰到目標、還沒吃到
			var food: Node2D = panel.food
			if food == null or not is_instance_valid(food) or not food.is_in_group("food"):
				return false
			for node: Node in creature.find_children("*", "Tentacle", true, false):
				var tentacle: Tentacle = node as Tentacle
				if tentacle.behavior != Tentacle.Behavior.GRAB_FOOD:
					continue
				var chains: Array = tentacle.get("_chains")
				if chains.is_empty():
					continue
				var distance: float = (chains[0] as PackedVector2Array)[-1].distance_to(food.global_position)
				return distance < 24.0 and distance > 10.0
		"legs":  # 走到中間、有一隻腳正跨到一半
			if _time < 1.2 or creature.global_position.x < -10.0:
				return false
			for node: Node in creature.find_children("*", "IKLeg", true, false):
				var stepping: Array = node.get("_stepping")
				var step_t: PackedFloat32Array = node.get("_step_t")
				for k: int in stepping.size():
					if stepping[k] and step_t[k] > 0.35 and step_t[k] < 0.7:
						_add_step_guides(panel, creature, (node.get("_feet") as PackedVector2Array)[k])
						return true
	return false


## 骨架的跨步圓圈是很淡的 1 像素線，手機上看不到：定格時另外疊一層明顯的
## （每隻腳的理想落腳點、跨步圓圈、腳掌到落腳點的線），再圈出正在半空中的那隻腳
func _add_step_guides(panel: Dictionary, creature: Creature, lifted_foot: Vector2) -> void:
	var guides := StepGuides.new()
	for node: Node in creature.find_children("*", "IKLeg", true, false):
		var leg: IKLeg = node as IKLeg
		var feet: PackedVector2Array = leg.get("_feet")
		var signs: PackedFloat32Array = CreaturePart.side_signs(leg.side)
		for k: int in mini(feet.size(), signs.size()):
			guides.rests.append(leg.call("_rest_point", signs[k]))
			guides.feet.append(feet[k])
			guides.radii.append(leg.step_distance)
	guides.lifted = lifted_foot
	(panel.root as Node2D).add_child(guides)


# ---------- 字、存圖 ----------

func _add_text(text: String, font_size: int, color: Color, at: Vector2, width: float, align: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.position = at
	label.size = Vector2(width, font_size * 1.5)
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = color
	label.label_settings = settings
	add_child(label)


func _save() -> void:
	for panel: Dictionary in _panels:
		if not panel.frozen:
			push_warning("「%s」等太久沒定格，照現在的樣子存" % panel.kind)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var folder: String = ProjectSettings.globalize_path("res://").path_join("../docs/promo")
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join("rules.png"))
	print("截圖存到 ", folder)
	get_tree().quit()


## 觸手的目標：放在 food 群組讓觸手伸過去，畫一個明顯的十字（骨架的顏色）
class TargetCross:
	extends Node2D

	func _draw() -> void:
		var color: Color = CreatureDebug.BONE_COLOR
		draw_line(Vector2(-10, 0), Vector2(10, 0), color, 2.0)
		draw_line(Vector2(0, -10), Vector2(0, 10), color, 2.0)
		draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(color, 0.6), 1.0)


## 跨步的輔助線：理想落腳點（點）、跨步圓圈（腳掌離開這個圈就換一步）、腳掌到落腳點的線，圈出半空中的腳
class StepGuides:
	extends Node2D

	var rests: PackedVector2Array = []
	var feet: PackedVector2Array = []
	var radii: PackedFloat32Array = []
	var lifted: Vector2

	func _draw() -> void:
		var color: Color = CreatureDebug.BONE_COLOR
		for i: int in rests.size():
			draw_arc(rests[i], radii[i], 0.0, TAU, 32, Color(color, 0.75), 2.0, true)
			draw_circle(rests[i], 3.0, color)
			draw_line(feet[i], rests[i], Color(color, 0.75), 1.5, true)
		draw_arc(lifted, 16.0, 0.0, TAU, 32, color, 3.0, true)
