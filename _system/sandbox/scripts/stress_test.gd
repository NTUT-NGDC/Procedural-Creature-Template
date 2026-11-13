extends Node
## 壓力測試：在生態缸裡一次生出很多隻最貴的生物（章魚、蜈蚣），水草、海葵、飼料全開，
## 畫面左下角顯示平均幀時間和 fps。用來確認對戰時跑不跑得動。
##
## 用法：開這個場景按 F6，按下面的按鈕換情境。
##   ・「對戰 20 隻」：對戰的情況：20 隻玩家生物、3 × 3 的地圖、鏡頭跟著其中一隻、沒有 NPC（驗收看這個）
##   ・「10／24／32 隻」：生物在 2 × 2 的地圖上游，鏡頭只看得到一部分
##   ・「（全擠）」：所有生物都在鏡頭裡（最壞的情況）
##   ・「單人缸 10／6 隻」：照生態缸的預設（隨機的範例生物、等級在玩家附近），6 隻是網頁版自動減少後的數量
## 數字的意思：
##   ・平均：最近幾秒每一幀平均花多久
##   ・最低：最慢的那一幀
##   ・最低 1%：最慢的那 1% 幀平均起來。比「最低」穩，看得出會不會忽快忽慢（跟平均差很多＝會頓）
## 拿去教室電腦跑：在命令列加上「-- auto」會自動跑完每種情境、把結果印出來後關掉
##   godot --path . res://_system/sandbox/stress_test.tscn -- auto

const TANK_SCENE: PackedScene = preload("res://game/tank/tank.tscn")
## 最貴的設計：章魚（8 條觸手）、蜈蚣（很多腳，越長大腳越多）
const HEAVY: Array[String] = ["res://example/creatures/octopus/design.tres", "res://example/creatures/centipede/design.tres"]
const COUNTS: Array[int] = [10, 24, 32]
## 生物的等級（越大身體越長、蜈蚣腳越多）
const LEVEL: int = 8
## 平均幀時間、最低 fps 看最近幾秒
const WINDOW: float = 4.0
## 對戰：幾隻玩家、地圖幾個畫面大
const BATTLE_COUNT: int = 20
const BATTLE_MAP: Vector2 = Vector2(3, 3)
## 「混戰」：其中幾隻（含鏡頭跟的那隻）擠在同一個畫面大的範圍裡打（大家追來追去會聚在一起）
const BRAWL_COUNT: int = 8

var _tank: Tank
var _crowd: bool = false
var _battle: bool = false
## 混戰的範圍（沒有混戰是空的）
var _brawl_area: Rect2 = Rect2()
var _count: int = 0
## 最近 WINDOW 秒內每一幀的時間（秒）
var _frame_times: PackedFloat32Array = []
var _label: Label


func _ready() -> void:
	_build_ui()
	if "auto" in OS.get_cmdline_user_args():
		_run_auto.call_deferred()
	else:
		_spawn_battle()


func _process(delta: float) -> void:
	_frame_times.append(delta)
	var total: float = 0.0
	for t: float in _frame_times:
		total += t
	while total > WINDOW and _frame_times.size() > 1:
		total -= _frame_times[0]
		_frame_times.remove_at(0)
	if _crowd and _tank != null:
		_keep_in_view()
	if _battle and _tank != null and _tank.get_creatures().size() < _count:
		_add_battle_creature()  # 被吃掉的補回來，數量才固定
	var result: Vector3 = stats()
	_label.text = "%d 隻（%s）　畫面裡 %d 隻\n平均 %.1f ms（%.0f fps）　最低 %.0f fps　最低 1%% %.0f fps" % [
		_count, _mode_name(), _visible_count(), result.x * 1000.0, 1.0 / result.x, result.y, result.z]


## 最近 WINDOW 秒：(平均幀時間（秒）, 最低 fps, 最低 1% 的 fps)
func stats() -> Vector3:
	if _frame_times.is_empty():
		return Vector3(1.0, 0.0, 0.0)
	var total: float = 0.0
	for t: float in _frame_times:
		total += t
	var sorted: PackedFloat32Array = _frame_times.duplicate()
	sorted.sort()
	var slow_count: int = maxi(ceili(sorted.size() * 0.01), 1)  # 最慢的 1% 有幾幀
	var slow_total: float = 0.0
	for i: int in slow_count:
		slow_total += sorted[sorted.size() - 1 - i]
	return Vector3(total / sorted.size(), 1.0 / sorted[-1], slow_count / slow_total)


func _mode_name() -> String:
	if _battle:
		return "對戰，%d × %d 地圖%s" % [BATTLE_MAP.x, BATTLE_MAP.y, "，%d 隻混戰" % BRAWL_COUNT if _brawl_area.has_area() else ""]
	return "全擠在畫面裡" if _crowd else "分散"


## 重開一個生態缸，生出 count 隻（count＋玩家＝缸裡總數，被吃掉會自己補）
func _spawn(count: int, crowd: bool) -> void:
	await _clear()
	_count = count
	_crowd = crowd
	_tank = TANK_SCENE.instantiate()
	var designs: Array[CreatureDesign] = []
	for path: String in HEAVY:
		designs.append(load(path))
	_tank.npc_designs = designs
	_tank.population = 0  # 先不要生，玩家升到 LEVEL 級再生（NPC 的等級跟著玩家）
	_tank.npc_level_spread = 0
	_tank.npc_max_level = LEVEL
	_tank.npc_respawn_time = 0.0
	add_child(_tank)
	move_child(_tank, 0)  # 按鈕在生態缸上面
	_tank.player.control_mode = Creature.Mode.WANDER
	_tank.player.set_level(LEVEL)
	_tank.population = count + 1
	for i: int in count:
		_tank.spawn_npc()
	_fill_food()


## 照生態缸的預設開一個單人缸（缸裡總共 total 隻），只換掉玩家的控制方式（不用滑鼠也會游）
func _spawn_default(total: int) -> void:
	await _clear()
	_count = total
	_tank = TANK_SCENE.instantiate()
	_tank.population = total
	add_child(_tank)
	move_child(_tank, 0)
	_tank.player.control_mode = Creature.Mode.WANDER


## 對戰：3 × 3 地圖、BATTLE_COUNT 隻最貴的生物（都算玩家，沒有 NPC），鏡頭跟著其中一隻。
## brawl 是「混戰」：鏡頭跟的那隻和另外幾隻關在地圖中間一個畫面大的範圍裡
func _spawn_battle(brawl: bool = false) -> void:
	await _clear()
	_count = BATTLE_COUNT
	_battle = true
	_tank = TANK_SCENE.instantiate()
	_tank.world_size = TankWater.SCREEN * BATTLE_MAP
	_tank.population = 0  # 沒有 NPC
	_tank.player_design = load(HEAVY[0])
	add_child(_tank)
	move_child(_tank, 0)
	_spread_plants()
	if brawl:
		_brawl_area = Rect2((_tank.world_size - TankWater.SCREEN) / 2.0, TankWater.SCREEN)
	_tank.player.control_mode = Creature.Mode.WANDER  # 測試時用漫遊代替真人操作
	_tank.player.set_level(LEVEL)
	_tank.player.global_position = _random_spot()
	if brawl:
		_tank.player.bounds = _brawl_area
	_tank.player.reset_pose()
	while _tank.get_creatures().size() < _count:
		_add_battle_creature()
	_fill_food()


## 對戰裡「別的玩家」：測試時用漫遊代替真人操作
func _add_battle_creature() -> void:
	var creature := Creature.new()
	creature.design = load(HEAVY[_tank.get_creatures().size() % HEAVY.size()])
	creature.control_mode = Creature.Mode.WANDER
	creature.level = LEVEL
	creature.heading = randf() * TAU
	creature.position = _random_spot()
	var in_brawl: bool = _brawl_area.has_area() and _tank.get_creatures().size() < BRAWL_COUNT
	_tank.add_creature(creature)
	if in_brawl:
		creature.bounds = _brawl_area


## 地圖上隨機一個點（離邊緣一點）；混戰時先放滿混戰的範圍
func _random_spot() -> Vector2:
	if _brawl_area.has_area() and _tank.get_creatures().size() < BRAWL_COUNT:
		return _brawl_area.position + Vector2(randf_range(0.1, 0.9), randf_range(0.1, 0.9)) * _brawl_area.size
	return Vector2(randf_range(0.1, 0.9), randf_range(0.1, 0.8)) * _tank.world_size


## 生態缸的水草是照 2 × 2 地圖擺的：照比例攤到整張大地圖、移到沙地上
func _spread_plants() -> void:
	var old_size: Vector2 = TankWater.SCREEN * 2.0
	for plant: Node in _tank.get_node("Plants").get_children():
		var node: Node2D = plant as Node2D
		node.position = Vector2(node.position.x * _tank.world_size.x / old_size.x, node.position.y + _tank.world_size.y - old_size.y)


## 收掉上一個生態缸
func _clear() -> void:
	if _tank != null:
		_tank.queue_free()
		_tank = null
		await get_tree().process_frame
	_crowd = false
	_battle = false
	_brawl_area = Rect2()
	_frame_times.clear()


## 飼料放滿
func _fill_food() -> void:
	for i: int in _tank.get_balance().max_food:
		_tank.drop_food(Vector2(randf() * _tank.world_size.x, randf() * _tank.floor_y()))
	_frame_times.clear()


## 「全擠在畫面裡」：每隻生物的範圍都設成鏡頭看得到的地方
func _keep_in_view() -> void:
	var view := Rect2(_tank.camera.get_screen_center_position() - TankWater.SCREEN / 2.0, TankWater.SCREEN).grow(-60.0)
	for creature: Creature in _tank.get_creatures():
		if creature.bounds != view:
			creature.bounds = view
			creature.global_position = view.position + Vector2(randf(), randf()) * view.size
			creature.reset_pose()


func _visible_count() -> int:
	if _tank == null:
		return 0
	return _tank.get_creatures().filter(func(creature: Creature) -> bool: return creature.visible).size()


## 自動跑完每種情境：每種先暖身 2 秒再量（關掉垂直同步，才量得到真正的幀時間）
func _run_auto() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("[壓力測試] 垂直同步關閉")
	await _spawn_battle()
	await _measure("對戰 %d 隻（%d × %d 地圖，鏡頭跟隨，沒有 NPC）" % [BATTLE_COUNT, BATTLE_MAP.x, BATTLE_MAP.y], 8.0)
	await _spawn_battle(true)
	await _measure("對戰 %d 隻，其中 %d 隻混戰" % [BATTLE_COUNT, BRAWL_COUNT], 8.0)
	for total: int in [10, 6]:
		await _spawn_default(total)
		await _measure("單人缸預設 %2d 隻" % total, 4.0)
	print("[壓力測試] 以下是章魚＋蜈蚣 %d 級、2 × 2 地圖" % LEVEL)
	for crowd: bool in [false, true]:
		for count: int in COUNTS:
			await _spawn(count, crowd)
			await _measure("%2d 隻 %s" % [count, "全擠" if crowd else "分散"], 4.0)
	get_tree().quit()


## 暖身 2 秒、量 seconds 秒，印出結果
func _measure(title: String, seconds: float) -> void:
	await get_tree().create_timer(2.0).timeout
	_frame_times.clear()
	await get_tree().create_timer(seconds).timeout
	var result: Vector3 = stats()
	print("[壓力測試] %s　畫面裡 %2d 隻：平均 %5.1f ms（%3.0f fps）最低 %3.0f fps　最低 1%% %3.0f fps" % [
		title, _visible_count(), result.x * 1000.0, 1.0 / result.x, result.y, result.z])


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(22, 560)
	layer.add_child(box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_label)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_add_button(buttons, "對戰 %d 隻" % BATTLE_COUNT, _spawn_battle.bind(false))
	_add_button(buttons, "對戰（%d 隻混戰）" % BRAWL_COUNT, _spawn_battle.bind(true))
	for crowd: bool in [false, true]:
		for count: int in COUNTS:
			_add_button(buttons, "%d 隻%s" % [count, "（全擠）" if crowd else ""], _spawn.bind(count, crowd))
	for total: int in [10, 6]:
		_add_button(buttons, "單人缸 %d 隻" % total, _spawn_default.bind(total))


func _add_button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	parent.add_child(button)
