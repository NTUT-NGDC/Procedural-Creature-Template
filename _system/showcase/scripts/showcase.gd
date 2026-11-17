extends Node2D
## IG 宣傳影片的展示場景（1080 × 1350 直式）。生物照劇本（data/storyboard.tres）自己游，不用滑鼠。
## 匯出時不會帶進去。
##
## 錄影片（在內層專案資料夾執行，Godot 換成自己的路徑）：
##   1. 暫時在專案資料夾放一個 override.cfg（Movie Maker 開始錄時就用專案設定的視窗大小，不放會錄成 1280 × 720）：
##        [display]
##        window/size/viewport_width=1080
##        window/size/viewport_height=1350
##        window/size/borderless=true
##   2. Godot --path . --write-movie <資料夾>/frame.png --fixed-fps 30 res://_system/showcase/showcase.tscn
##   3. 錄完刪掉 override.cfg（不要 commit）
##   正式的時間軸前面會多錄 WARMUP 秒（讓生物先游起來），轉 MP4 時剪掉；
##   開頭前最後 0.7 秒拿來跟結尾最後 0.7 秒交叉淡化，重播時才會接回開頭（步驟見外層 docs/promo/README.md）
## 拍截圖（正常＋骨架，同一個畫面，存到外層 docs/promo/）：
##   Godot --path . res://_system/showcase/showcase.tscn -- shots

## 畫面大小（IG 直式 4:5）
const SCREEN: Vector2i = Vector2i(1080, 1350)
## 開頭前先游幾秒（錄影會錄進去，轉檔時剪掉；最後 LOOP_FADE 秒拿來讓結尾淡回開頭）
const WARMUP: float = 2.0
## 主角從畫面外多遠的地方出發（像素）
const STAR_OFFSCREEN: float = 200.0
## 沿著橢圓游時，瞄準前面多遠的角度（弧度）：越大越早轉彎
const LANE_LEAD: float = 0.6

## 劇本
@export var storyboard: ShowcaseStoryboard

## 劇本時間（秒）：0 是影片開頭，開頭前是負的
var _time: float = -WARMUP
## 地圖大小（畫面大小 ÷ 鏡頭放大倍率）
var _world: Vector2
var _creatures: Array[Creature] = []
var _shots_mode: bool = false
var _shot_taken: bool = false
var _debug: Node
## 飼料：每個餵食點一串；補飼料用固定的亂數種子，每次錄出來都一樣
var _foods: Array[Array] = []
var _food_layer: Node2D
## 每個餵食點還要等幾秒才能補下一顆
var _refill_wait: PackedFloat32Array = []
var _rng := RandomNumberGenerator.new()

var _dim: ColorRect
var _caption_bones: Control
var _caption_rules: Control
var _ending: Control

@onready var _water: Node2D = %Water
@onready var _plants: Node2D = %Plants
@onready var _creature_layer: Node2D = %Creatures
@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	_shots_mode = OS.get_cmdline_user_args().has("shots")
	# 視窗比螢幕高時系統會把它縮小：拿掉邊框、直接設定大小，錄出來才是 1080 × 1350
	get_window().borderless = true
	get_window().size = SCREEN
	get_window().position = Vector2i.ZERO
	get_window().content_scale_size = SCREEN
	print("視窗大小：", get_window().size)
	_world = Vector2(SCREEN) / storyboard.zoom
	_debug = get_node_or_null("/root/Debug")
	WaterFlow.strength = storyboard.flow_strength
	WaterFlow.fixed_time = 0.0
	_water.set("world_size", _world)
	_camera.zoom = Vector2.ONE * storyboard.zoom
	_camera.position = _world / 2.0
	_add_plants()
	_food_layer = Node2D.new()  # 飼料畫在水草前面、生物後面
	add_child(_food_layer)
	move_child(_food_layer, _creature_layer.get_index())
	_rng.seed = 1119
	for _spot: Vector2 in storyboard.feed_spots:
		_foods.append([])
		_refill_wait.append(0.0)
	_foods.append([])  # 最後一串是整個畫面隨機撒的
	_refill_wait.append(0.0)
	for _i: int in maxi(storyboard.food_per_spot, storyboard.scatter_food):
		_refill_food(0.0)  # 一開始就放滿
	for i: int in storyboard.actors.size():
		_spawn(i)
	_build_ui()
	print("展示場景：30 fps 錄影時，影片開頭是第 %d 幀（從 0 算）" % roundi(WARMUP * 30.0))


func _exit_tree() -> void:
	WaterFlow.reset()
	if _debug != null:
		_debug.set("show_bones", false)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_time += delta
	WaterFlow.fixed_time = _time + 100.0  # 水流用的時間（固定、不跟電腦時間跑）
	if _debug != null:
		_debug.set("show_bones", _time >= storyboard.bones_start and _time < storyboard.bones_end)
	_update_ui()
	_wrap_passers()
	_eat_food()
	_refill_food(delta)
	if _shots_mode and not _shot_taken and _time >= storyboard.shot_time:
		_shot_taken = true
		_take_shots()
	elif not _shots_mode and _time >= storyboard.total:
		print("最後的等級：", _creatures.map(func(c: Creature) -> int: return c.level))
		get_tree().quit()


# ---------- 生物 ----------

## 照劇本放第 i 隻生物：主角放在畫面左邊外面；其他照角色放（繞圈放在橢圓上、游過去放在路線上、吃飼料放在餵食點旁）
func _spawn(i: int) -> void:
	var actor: ShowcaseActor = storyboard.actors[i]
	if actor == null or actor.design == null:
		return
	var creature := Creature.new()
	creature.design = _recolored(actor)
	creature.control_mode = Creature.Mode.WANDER
	creature.bounds = Rect2(-_world.x, -_world.y * 0.3, _world.x * 3.0, _world.y * 1.6)
	_creature_layer.add_child(creature)
	creature.set_level(actor.level)
	creature.brain = _brain.bind(_creatures.size())
	_creatures.append(creature)
	if actor.is_star:  # 主角在開頭前就出發，第 0 秒頭剛好游進畫面
		_place(creature, Vector2(60.0 - creature.speed * actor.speed_scale * WARMUP, _world.y * 0.45), 0.0)
		return
	match actor.role:
		ShowcaseActor.Role.PASS:
			var span: float = _body_span(creature)
			var path: Vector2 = Vector2(-span, _world.x + span)
			if actor.pass_from_right:
				path = Vector2(path.y, path.x)
			_place(creature, Vector2(lerpf(path.x, path.y, actor.pass_offset), _world.y * actor.pass_height), PI if actor.pass_from_right else 0.0)
		ShowcaseActor.Role.FEED:
			var angle: float = TAU * i / storyboard.actors.size()
			_place(creature, _feed_spot(actor) + Vector2.from_angle(angle) * storyboard.feed_range * _world.x * 0.5, angle + PI / 2.0)
		_:
			var angle: float = actor.lane_phase * TAU
			var at: Vector2 = _lane_point(actor, angle)
			_place(creature, at, (_lane_point(actor, angle + _lane_dir(actor) * 0.1) - at).angle())


## 把生物瞬間移到 at、頭朝 heading，身體往後拉直
func _place(creature: Creature, at: Vector2, heading: float) -> void:
	creature.global_position = at
	creature.heading = heading
	creature.reset_pose()


## 身體從頭到尾巴有多長（加上腳、觸手大概伸出去的距離），用來判斷整隻都出了畫面
func _body_span(creature: Creature) -> float:
	var span: float = 0.0
	var body: ChainBody = creature.get_body()
	if body != null:
		for point: Vector2 in body.get_points():
			span = maxf(span, point.distance_to(creature.global_position))
	return span + 120.0


## 游過去的生物：整隻出了畫面，就移到另一邊重新出發（在畫面外換，看不到）
func _wrap_passers() -> void:
	if _time >= storyboard.chase_start and _time < storyboard.bones_start:
		return  # 追目標點的時候不換
	for i: int in _creatures.size():
		var actor: ShowcaseActor = storyboard.actors[i]
		if actor.role != ShowcaseActor.Role.PASS or actor.is_star:
			continue
		var creature: Creature = _creatures[i]
		var span: float = _body_span(creature)
		var x: float = creature.global_position.x
		var y: float = _world.y * actor.pass_height
		if not actor.pass_from_right and x > _world.x + span:
			_place(creature, Vector2(-span, y), 0.0)
		elif actor.pass_from_right and x < -span:
			_place(creature, Vector2(_world.x + span, y), PI)


## 換顏色：複製一份設計檔再改，不會動到範例的檔案
func _recolored(actor: ShowcaseActor) -> CreatureDesign:
	if actor.body_color.a <= 0.0:
		return actor.design
	var design: CreatureDesign = actor.design.duplicate(true)
	var color: Color = actor.body_color
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color.lightened(0.15), color.darkened(0.2)])
	design.body.body_gradient = gradient
	design.body.outline_color = color.lightened(0.55)
	design.body.pattern_color = color.darkened(0.45)
	for leg: LegDesign in design.legs:
		leg.leg_color = color.lightened(0.25)
	for tentacle: TentacleDesign in design.tentacles:
		var arm := Gradient.new()
		arm.colors = PackedColorArray([color, color.lightened(0.5)])
		tentacle.color_gradient = arm
	return design


## 大腦：每 0.1 秒問一次要往哪走。照劇本的時間決定：中間大家追目標點，其他時間照自己的角色
func _brain(index: int) -> Dictionary:
	var creature: Creature = _creatures[index]
	var actor: ShowcaseActor = storyboard.actors[index]
	var here: Vector2 = creature.global_position
	var speed: float = creature.speed * actor.speed_scale
	var target: Vector2
	if _time >= storyboard.chase_start and _time < storyboard.bones_start:
		var spread: Vector2 = Vector2.from_angle(TAU * index / storyboard.actors.size()) * storyboard.chase_spread * _world.x
		target = _chase_point(_time) + spread  # 每隻錯開一點，才不會擠成一團
		speed = creature.speed * storyboard.chase_speed_scale
	elif actor.is_star and _time < storyboard.chase_start:
		target = Vector2(_world.x * 2.0, _world.y * 0.45)
	elif actor.role == ShowcaseActor.Role.PASS:
		var ahead: float = -_world.x if actor.pass_from_right else _world.x
		target = Vector2(here.x + ahead, _world.y * actor.pass_height)
	elif actor.role == ShowcaseActor.Role.FEED:
		var spot: Vector2 = _feed_spot(actor)
		var food: Node2D = _nearest_food(here, spot)
		if food != null:
			target = food.global_position
			speed *= clampf(here.distance_to(target) / 80.0, 0.4, 0.9)  # 靠近飼料慢下來，才不會繞著打轉
		else:  # 沒有飼料：在餵食點旁邊慢慢繞
			target = spot + Vector2.from_angle(_time * 0.8 + index) * storyboard.feed_range * _world.x * 0.5
			speed *= 0.6
	else:
		target = _lane_target(actor, here)
	var direction: Vector2 = (target - here).normalized() + _avoid(index) * storyboard.avoid_strength
	return {"angle": direction.angle(), "speed": speed}


## 閃開：附近每一節別隻的身體都把自己往外推，越近推越大（回傳推的方向，長度大約 0～1 以上）
func _avoid(index: int) -> Vector2:
	var here: Vector2 = _creatures[index].global_position
	var push: Vector2 = Vector2.ZERO
	var space: float = storyboard.personal_space
	if space <= 0.0:
		return push
	for j: int in _creatures.size():
		if j == index:
			continue
		var other: Creature = _creatures[j]
		if other.global_position.distance_to(here) > space + _body_span(other):
			continue  # 整隻都很遠，不用一節一節算
		var body: ChainBody = other.get_body()
		var points: PackedVector2Array = body.get_points() if body != null else PackedVector2Array([other.global_position])
		for point: Vector2 in points:
			var distance: float = here.distance_to(point)
			if distance < space and distance > 0.01:
				push += (here - point) / distance * (1.0 - distance / space)
	return push.limit_length(3.0)


## 看不見的目標點：繞著畫面中間轉
func _chase_point(time: float) -> Vector2:
	var angle: float = TAU * (time - storyboard.chase_start) / storyboard.chase_period - PI / 2.0
	return _world / 2.0 + Vector2(cos(angle), sin(angle)) * storyboard.chase_radius * _world


## 沿著橢圓游：算出自己現在在橢圓的哪個角度，瞄準前面一點的點
func _lane_target(actor: ShowcaseActor, from: Vector2) -> Vector2:
	var offset: Vector2 = (from - actor.lane_center * _world) / (actor.lane_radius * _world)
	return _lane_point(actor, offset.angle() + _lane_dir(actor) * LANE_LEAD)


func _lane_point(actor: ShowcaseActor, angle: float) -> Vector2:
	return actor.lane_center * _world + Vector2(cos(angle), sin(angle)) * actor.lane_radius * _world


func _lane_dir(actor: ShowcaseActor) -> float:
	return -1.0 if actor.lane_reverse else 1.0


# ---------- 飼料 ----------

## 第幾個餵食點的位置（全局座標）
func _feed_spot(actor: ShowcaseActor) -> Vector2:
	if storyboard.feed_spots.is_empty():
		return _world / 2.0
	return storyboard.feed_spots[clampi(actor.feed_spot, 0, storyboard.feed_spots.size() - 1)] * _world


## 離 from 最近、而且在餵食點附近的飼料（沒有就回傳 null）
func _nearest_food(from: Vector2, spot: Vector2) -> Node2D:
	var best: Node2D = null
	var reach: float = storyboard.feed_range * _world.x
	for node: Node in get_tree().get_nodes_in_group("food"):
		var food: Node2D = node as Node2D
		if food.global_position.distance_to(spot) > reach:
			continue
		if best == null or from.distance_squared_to(food.global_position) < from.distance_squared_to(best.global_position):
			best = food
	return best


## 頭碰到飼料就吃掉（跟生態缸一樣會長大）
func _eat_food() -> void:
	for creature: Creature in _creatures:
		for node: Node in get_tree().get_nodes_in_group("food"):
			var food: Food = node as Food
			if food.global_position.distance_to(creature.global_position) < creature.head_radius + food.radius + 4.0:
				creature.eat(food)


## 每個餵食點少於 food_per_spot 顆，就每隔 food_refill_time 秒補一顆；
## 最後一串是整個畫面隨機撒的，少於 scatter_food 顆就每隔 scatter_refill_time 秒補一顆
func _refill_food(delta: float) -> void:
	for k: int in _foods.size():
		var scatter: bool = k == _foods.size() - 1
		var list: Array = _foods[k].filter(func(food: Node) -> bool: return is_instance_valid(food) and food.is_in_group("food"))
		_foods[k] = list
		_refill_wait[k] -= delta
		if list.size() >= (storyboard.scatter_food if scatter else storyboard.food_per_spot) or _refill_wait[k] > 0.0:
			continue
		_refill_wait[k] = storyboard.scatter_refill_time if scatter else storyboard.food_refill_time
		var at: Vector2
		if scatter:
			at = Vector2(_rng.randf_range(40.0, _world.x - 40.0), _rng.randf_range(40.0, _world.y - 60.0))
		else:
			at = storyboard.feed_spots[k] * _world + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * storyboard.food_spread * _world.x
		list.append(_add_food(at, _rng.randf() < storyboard.big_food_chance))


## 放一顆飼料（大顆比較大、吃了算好幾顆，跟生態缸一樣）
func _add_food(at: Vector2, big: bool) -> Food:
	var food := Food.new()
	food.position = at
	food.floor_y = _world.y - 30.0
	food.max_x = _world.x
	if big:
		food.radius = Food.BIG_RADIUS
		food.value = CreatureBalance.get_default().big_food_value
	_food_layer.add_child(food)
	return food


# ---------- 背景 ----------

## 水草、海葵：沿著沙地排一排（位置是畫面寬度的比例）
func _add_plants() -> void:
	var bottom: float = _world.y - 26.0
	var weeds: Array = [[0.04, 170.0, -0.1], [0.13, 100.0, 0.15], [0.3, 230.0, -0.2], [0.38, 120.0, 0.05], [0.62, 150.0, 0.12], [0.8, 250.0, -0.15], [0.9, 110.0, 0.2], [0.97, 180.0, 0.0]]
	for data: Array in weeds:
		var weed := Weed.new()
		weed.position = Vector2(_world.x * data[0], bottom)
		weed.height = data[1]
		weed.segment_count = maxi(4, roundi(data[1] / 20.0))
		weed.lean = data[2]
		_plants.add_child(weed)
	var anemones: Array = [[0.22, Color("#c2185b"), Color("#ec407a"), Color("#ffd1e0")], [0.52, Color("#d9730d"), Color("#fa9a33"), Color("#ffe69a")], [0.72, Color("#7b1fa2"), Color("#ba68c8"), Color("#f3d1ff")]]
	for data: Array in anemones:
		var anemone := Anemone.new()
		anemone.position = Vector2(_world.x * data[0], bottom + 4.0)
		anemone.fan_angle = deg_to_rad(200.0)
		anemone.body_color = data[1]
		anemone.arm_base_color = data[2]
		anemone.arm_tip_color = data[3]
		_plants.add_child(anemone)


# ---------- 字幕 ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_dim = ColorRect.new()
	_dim.color = Color.BLACK
	_dim.size = Vector2(SCREEN)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_dim)
	_caption_bones = _make_caption(storyboard.caption_bones)
	_caption_rules = _make_caption(storyboard.caption_rules)
	layer.add_child(_caption_bones)
	layer.add_child(_caption_rules)
	_ending = _make_ending()
	layer.add_child(_ending)
	_add_banner()
	_update_ui()


## 最上面的橫幅：橘色色帶＋社團名（跟輪播最後一張一樣），下面一行時間和主題。
## 放在更上面一層，不會被結尾變暗、也不會淡入淡出
func _add_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var band := ColorRect.new()
	band.color = Color("#f2b766")
	band.position = Vector2(0, 70)
	band.size = Vector2(SCREEN.x, 76)
	layer.add_child(band)
	var settings := LabelSettings.new()
	settings.font_size = 44
	settings.font_color = Color("#0b1e24")
	layer.add_child(_banner_label(storyboard.banner_text, settings, 80.0))
	if storyboard.banner_subtitle != "":
		var strip := ColorRect.new()  # 深色底條：生物從下面游過去也看得清楚
		strip.color = Color(0.04, 0.12, 0.14, 0.88)
		strip.position = Vector2(0, 146)
		strip.size = Vector2(SCREEN.x, 56)
		layer.add_child(strip)
		var settings_small := LabelSettings.new()
		settings_small.font_size = 33
		settings_small.font_color = Color.WHITE
		layer.add_child(_banner_label(storyboard.banner_subtitle, settings_small, 151.0))


func _banner_label(text: String, settings: LabelSettings, y: float) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, y)
	label.size = Vector2(SCREEN.x, settings.font_size * 1.4)
	return label


## 一句字幕：黑色半透明圓角底＋白字，放在畫面中間偏上
func _make_caption(text: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.06, 0.08, 0.72)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(22.0)
	style.content_margin_left = 36.0
	style.content_margin_right = 36.0
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.label_settings = _label_settings(storyboard.caption_size)
	panel.add_child(label)
	var holder := CenterContainer.new()  # 讓字幕不管多長都置中
	holder.size = Vector2(SCREEN.x, 0)
	holder.position = Vector2(0, SCREEN.y * storyboard.caption_y)
	holder.add_child(panel)
	return holder


## 結尾的字：第一行大、後面小，整塊放在畫面正中間
func _make_ending() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 30)
	for i: int in storyboard.ending_lines.size():
		var label := Label.new()
		label.text = storyboard.ending_lines[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.label_settings = _label_settings(storyboard.ending_title_size if i == 0 else storyboard.ending_size)
		if i == 0:
			label.label_settings.font_color = Color("#ffd166")
		box.add_child(label)
		if i == 0:  # 第一行和後面兩行中間多空一點
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 12)
			box.add_child(gap)
	var holder := CenterContainer.new()
	holder.size = Vector2(SCREEN)
	holder.add_child(box)
	return holder


func _label_settings(font_size: int) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = Color.WHITE
	settings.outline_size = roundi(font_size / 6.0)
	settings.outline_color = Color(0.02, 0.06, 0.08)
	settings.shadow_color = Color(0, 0, 0, 0.6)
	settings.shadow_offset = Vector2(4, 4)
	return settings


## 每一幀照劇本時間算字幕、變暗的透明度
func _update_ui() -> void:
	var fade: float = storyboard.fade_time
	_caption_bones.modulate.a = _window(_time, storyboard.bones_start, storyboard.bones_end, fade)
	_caption_rules.modulate.a = _window(_time, storyboard.bones_end + fade, storyboard.ending_start, fade)
	var ending: float = _window(_time, storyboard.ending_start, INF, fade)
	_dim.color.a = storyboard.ending_dim * ending
	_ending.modulate.a = ending


## 從 start 淡入、到 end 淡出（各花 fade 秒），回傳 0～1
static func _window(time: float, start: float, end: float, fade: float) -> float:
	if fade <= 0.0:
		return 1.0 if time >= start and time < end else 0.0
	return clampf(minf((time - start) / fade, (end - time) / fade), 0.0, 1.0)


# ---------- 截圖 ----------

## 暫停在這一幀，拍正常的和骨架的各一張（不放字幕），存到外層 repo 的 docs/promo/
func _take_shots() -> void:
	get_tree().paused = true
	for child: Node in get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var folder: String = ProjectSettings.globalize_path("res://").path_join("../docs/promo")
	DirAccess.make_dir_recursive_absolute(folder)
	await _save_frame(folder.path_join("cover.png"))
	_debug.set("show_bones", true)
	_redraw_all(self)
	await _save_frame(folder.path_join("cover_bones.png"))
	print("截圖存到 ", folder)
	get_tree().quit()


func _save_frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _redraw_all(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()
	for child: Node in node.get_children():
		_redraw_all(child)
