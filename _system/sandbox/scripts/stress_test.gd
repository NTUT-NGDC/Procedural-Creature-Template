extends Node
## 壓力測試：在生態缸裡一次生出 10／24／32 隻最貴的生物（章魚、蜈蚣），水草、海葵、飼料全開，
## 畫面左下角顯示平均幀時間和最低 fps。用來確認對戰（最多 24 隻玩家）時跑不跑得動。
##
## 用法：開這個場景按 F6，按下面的按鈕換數量。
##   ・「分散」：生物在整張地圖上游（像真的對戰，鏡頭只看得到一部分）
##   ・「全擠在畫面裡」：所有生物都在鏡頭裡（最壞的情況）
##   ・「單人缸 10／6 隻」：照生態缸的預設（隨機的範例生物、等級在玩家附近），6 隻是網頁版自動減少後的數量
## 拿去教室電腦跑：在命令列加上「-- auto」會自動跑完每種組合、把結果印出來後關掉
##   godot --path . res://_system/sandbox/stress_test.tscn -- auto

const TANK_SCENE: PackedScene = preload("res://game/tank/tank.tscn")
## 最貴的設計：章魚（8 條觸手）、蜈蚣（很多腳，越長大腳越多）
const HEAVY: Array[String] = ["res://example/creatures/octopus/design.tres", "res://example/creatures/centipede/design.tres"]
const COUNTS: Array[int] = [10, 24, 32]
## 生物的等級（越大身體越長、蜈蚣腳越多）
const LEVEL: int = 8
## 平均幀時間、最低 fps 看最近幾秒
const WINDOW: float = 2.0

var _tank: Tank
var _crowd: bool = false
var _count: int = 0
## 最近 WINDOW 秒內每一幀的時間（秒）
var _frame_times: PackedFloat32Array = []
var _label: Label


func _ready() -> void:
	_build_ui()
	if "auto" in OS.get_cmdline_user_args():
		_run_auto.call_deferred()
	else:
		_spawn(COUNTS[0], false)


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
	_label.text = "%d 隻（%s）　畫面裡 %d 隻\n平均幀時間 %.1f ms（%.0f fps）　最低 %.0f fps" % [
		_count, "全擠在畫面裡" if _crowd else "分散", _visible_count(), stats().x * 1000.0, 1.0 / stats().x, stats().y]


## 最近 WINDOW 秒：(平均幀時間（秒）, 最低 fps)
func stats() -> Vector2:
	if _frame_times.is_empty():
		return Vector2(1.0, 0.0)
	var total: float = 0.0
	var worst: float = 0.0
	for t: float in _frame_times:
		total += t
		worst = maxf(worst, t)
	return Vector2(total / _frame_times.size(), 1.0 / worst)


## 重開一個生態缸，生出 count 隻（count＋玩家＝缸裡總數，被吃掉會自己補）
func _spawn(count: int, crowd: bool) -> void:
	if _tank != null:
		_tank.queue_free()
		await get_tree().process_frame
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
	for i: int in _tank.get_balance().max_food:  # 飼料放滿
		_tank.drop_food(Vector2(randf() * _tank.world_size.x, randf() * _tank.floor_y()))
	_frame_times.clear()


## 照生態缸的預設開一個單人缸（缸裡總共 total 隻），只換掉玩家的控制方式（不用滑鼠也會游）
func _spawn_default(total: int) -> void:
	if _tank != null:
		_tank.queue_free()
		await get_tree().process_frame
	_count = total
	_crowd = false
	_tank = TANK_SCENE.instantiate()
	_tank.population = total
	add_child(_tank)
	move_child(_tank, 0)
	_tank.player.control_mode = Creature.Mode.WANDER
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


## 自動跑完每種組合：每種先暖身 2 秒、量 4 秒，印出結果（關掉垂直同步，才量得到真正的幀時間）
func _run_auto() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("[壓力測試] 垂直同步關閉")
	for total: int in [10, 6]:
		await _spawn_default(total)
		await get_tree().create_timer(2.0).timeout
		_frame_times.clear()
		await get_tree().create_timer(4.0).timeout
		var single: Vector2 = stats()
		print("[壓力測試] 單人缸預設 %2d 隻    畫面裡 %2d 隻：平均 %5.1f ms（%3.0f fps）最低 %3.0f fps" % [
			total, _visible_count(), single.x * 1000.0, 1.0 / single.x, single.y])
	print("[壓力測試] 以下是章魚＋蜈蚣 %d 級" % LEVEL)
	for crowd: bool in [false, true]:
		for count: int in COUNTS:
			await _spawn(count, crowd)
			await get_tree().create_timer(2.0).timeout
			_frame_times.clear()
			await get_tree().create_timer(4.0).timeout
			var result: Vector2 = stats()
			print("[壓力測試] %2d 隻 %-6s 畫面裡 %2d 隻：平均 %5.1f ms（%3.0f fps）最低 %3.0f fps" % [
				count, "全擠" if crowd else "分散", _visible_count(), result.x * 1000.0, 1.0 / result.x, result.y])
	get_tree().quit()


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
	for crowd: bool in [false, true]:
		for count: int in COUNTS:
			var button := Button.new()
			button.text = "%d 隻%s" % [count, "（全擠）" if crowd else ""]
			button.add_theme_font_size_override("font_size", 22)
			button.pressed.connect(_spawn.bind(count, crowd))
			buttons.add_child(button)
	for total: int in [10, 6]:
		var single := Button.new()
		single.text = "單人缸 %d 隻" % total
		single.add_theme_font_size_override("font_size", 22)
		single.pressed.connect(_spawn_default.bind(total))
		buttons.add_child(single)
