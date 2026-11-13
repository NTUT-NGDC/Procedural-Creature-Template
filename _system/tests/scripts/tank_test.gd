extends Node
## 生態缸的自動測試：
## 1. 開始：玩家生物照設計檔長出來、滑鼠控制，速度和頭的大小來自能力；水流照設定
##    大地圖：玩家在地圖中央、鏡頭跟著玩家，到邊緣鏡頭停住、生物游不出地圖
## 2. 飼料：點一下放一個；最多 max_food 個；會往下沉、沉到底停住；缸裡會自己長（間隔 0 就不長）
## 3. 吃東西：頭碰到就吃掉；吃滿「升一級要吃幾個」才升級，升級後照長大方式變大
## 4. 水草：有水流時會歪；生物經過被撥開（點在身體外面），生物走了會站回來
## 5. 海葵：觸手被生物推開，再彈回來
## 6. 水草、海葵超過上限：多的藏起來、顯示提示
## 7. 沒有玩家生物：顯示提示、不會當掉
## 8. 離開生態缸：水流歸零
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/tank_test.tscn

const TANK_SCENE: PackedScene = preload("res://game/tank/tank.tscn")
const SNAKE: String = "res://example/creatures/snake/design.tres"

var _failures: int = 0


func _ready() -> void:
	await _test_start()
	await _test_world()
	await _test_food()
	await _test_eat_and_grow()
	await _test_weed()
	await _test_anemone()
	await _test_plant_limit()
	await _test_no_player()

	if _failures == 0:
		print("[生態缸測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[生態缸測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_start() -> void:
	print("--- 開始 ---")
	var tank: Tank = await _spawn({})
	var player: Creature = tank.player
	_expect(player != null and player.design == load(SNAKE) and player.control_mode == Creature.Mode.MOUSE, "玩家生物是蛇（設計檔），用滑鼠控制")
	_expect(is_equal_approx(player.speed, player.get_stats().speed) and player.head_radius > 4.0, "速度來自能力（%.0f），頭的大小來自身體（%.1f）" % [player.speed, player.head_radius])
	_expect(WaterFlow.strength == tank.flow_strength and WaterFlow.at(Vector2(300, 300)) != Vector2.ZERO, "水流強度照生態缸的設定（%.0f）" % WaterFlow.strength)
	await _free(tank)
	_expect(WaterFlow.strength == 0.0 and WaterFlow.at(Vector2(300, 300)) == Vector2.ZERO, "離開生態缸：水流歸零")


func _test_world() -> void:
	print("--- 大地圖 ---")
	var tank: Tank = await _spawn({"world_size": Vector2(2560, 1440), "auto_food_interval": 0.0})
	var player: Creature = tank.player
	_expect(player.global_position.distance_to(Vector2(1280, 720)) < 50.0 and player.bounds == Rect2(0, 0, 2560, 1440), "玩家在地圖中央，範圍是整張地圖")
	_expect(tank.camera != null and tank.camera.is_current(), "有跟著玩家的鏡頭")
	player.set_process(false)  # 先停住，才不會跟著滑鼠跑掉
	player.global_position = Vector2(1600, 900)
	await _seconds(1.0)
	_expect(tank.camera.get_screen_center_position().distance_to(player.global_position) < 20.0, "鏡頭跟著玩家走（差 %.0f 像素）" % tank.camera.get_screen_center_position().distance_to(player.global_position))
	player.global_position = Vector2(2550, 1430)
	await _seconds(1.0)
	_expect(tank.camera.get_screen_center_position().is_equal_approx(Vector2(2560 - 640, 1440 - 360)), "玩家在角落：鏡頭停在地圖邊緣，看不到外面")
	player.global_position = Vector2(3000, -100)
	player.set_process(true)
	await _frames(2)
	_expect(Rect2(0, 0, 2560, 1440).grow(0.5).has_point(player.global_position), "生物游不出地圖")
	tank.drop_food(Vector2(2500, 100))
	_expect(tank.get_node("%Foods").get_child(0).max_x == 2560.0, "飼料的範圍是整張地圖")
	await _free(tank)


func _test_food() -> void:
	print("--- 飼料 ---")
	var tank: Tank = await _spawn({"auto_food_interval": 0.0, "max_food": 5})
	var foods: Node2D = tank.get_node("%Foods")
	tank.player.set_process(false)  # 玩家停住，才不會把飼料吃掉
	tank.player.global_position = Vector2(1200, 100)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(400, 200)
	click.global_position = click.position
	tank.get_viewport().push_input(click)
	await get_tree().process_frame
	_expect(foods.get_child_count() == 1, "點一下放一個飼料")
	for i: int in 10:
		tank.drop_food(Vector2(100 + i * 40, 200))
	_expect(foods.get_child_count() == 5, "最多 5 個（max_food）")
	var food: Food = foods.get_child(0)
	var start_y: float = food.global_position.y
	await _seconds(0.5)
	_expect(food.global_position.y > start_y, "飼料會往下沉")
	food.global_position.y = tank.floor_y() - 1.0
	await _seconds(0.3)
	_expect(is_equal_approx(food.global_position.y, tank.floor_y()), "沉到底就停住")
	await _free(tank)

	tank = await _spawn({"auto_food_interval": 0.1, "max_food": 50})
	tank.player.set_process(false)
	tank.player.global_position = Vector2(-500, -500)
	await _seconds(0.55)
	var count: int = tank.get_node("%Foods").get_child_count()
	_expect(count >= 3, "缸裡會自己長食物：0.55 秒長了 %d 個" % count)
	await _free(tank)


func _test_eat_and_grow() -> void:
	print("--- 吃東西、升級 ---")
	var tank: Tank = await _spawn({"auto_food_interval": 0.0})
	var player: Creature = tank.player
	player.set_process(false)
	var cost: int = player.get_stats().level_cost
	var size_before: float = player.get_stats().size
	for i: int in cost - 1:
		tank.drop_food(player.global_position)
	await _frames(2)
	_expect(player.level == 0 and player.food_progress == cost - 1, "吃了 %d 個：還沒升級（要吃 %d 個）" % [cost - 1, cost])
	tank.drop_food(player.global_position + Vector2(player.head_radius * 0.5, 0))
	await _frames(2)
	_expect(player.level == 1 and player.food_progress == 0, "吃滿 %d 個：升到 1 級" % cost)
	_expect(player.get_stats().size > size_before, "升級後變大：體型 %.0f → %.0f" % [size_before, player.get_stats().size])
	tank.drop_food(player.global_position + Vector2(400, 0))
	await _frames(2)
	_expect(tank.get_node("%Foods").get_child_count() == 1, "離頭很遠的飼料不會被吃")
	await _free(tank)


func _test_weed() -> void:
	print("--- 水草 ---")
	var tank: Tank = await _spawn({"flow_strength": 60.0, "auto_food_interval": 0.0})
	tank.player.set_process(false)
	tank.player.global_position = Vector2(-500, -500)
	var weed: Weed = tank.get_node("%Plants").get_child(3) as Weed
	var straight_tip: Vector2 = weed.global_position + Vector2.UP.rotated(weed.lean) * weed.height
	await _seconds(1.0)
	_expect(weed.get_tip().distance_to(straight_tip) > 3.0, "有水流：水草歪了 %.0f 像素" % weed.get_tip().distance_to(straight_tip))
	_expect(weed.get_tip().distance_to(weed.global_position) <= weed.height + 0.5, "水草的長度不變")

	WaterFlow.strength = 0.0
	tank.flow_strength = 0.0
	await _seconds(3.0)  # 等水草站回來，再讓生物鑽進去
	var middle: Vector2 = weed.global_position + Vector2.UP.rotated(weed.lean) * weed.height * 0.6
	tank.player.global_position = middle
	tank.player.reset_pose()
	await _seconds(0.5)
	var inside: bool = false
	var points: PackedVector2Array = weed.get("_points")
	for point: Vector2 in points:
		inside = inside or point.distance_to(tank.player.global_position) < tank.player.head_radius - 1.0
	_expect(not inside, "生物的頭在水草中間：水草被撥開，沒有點在頭裡面")
	tank.player.global_position = Vector2(-500, -500)
	tank.player.reset_pose()
	await _seconds(3.0)
	_expect(weed.get_tip().distance_to(straight_tip) < 5.0, "生物走了、沒有水流：站回原本的樣子（差 %.1f 像素）" % weed.get_tip().distance_to(straight_tip))
	await _free(tank)


func _test_anemone() -> void:
	print("--- 海葵 ---")
	var tank: Tank = await _spawn({"flow_strength": 0.0, "auto_food_interval": 0.0})
	var anemone: Anemone = null
	for plant: Node in tank.get_node("%Plants").get_children():
		if plant is Anemone and anemone == null:
			anemone = plant
	var rest_tip: Vector2 = anemone.get_arm_tip(anemone.arm_count / 2)
	tank.player.set_process(false)
	tank.player.global_position = rest_tip
	tank.player.reset_pose()
	await _seconds(0.3)
	var pushed: float = anemone.get_arm_tip(anemone.arm_count / 2).distance_to(rest_tip)
	_expect(pushed > 3.0, "生物碰到觸手：被推開 %.0f 像素" % pushed)
	tank.player.global_position = Vector2(-500, -500)
	tank.player.reset_pose()
	await _seconds(2.0)
	_expect(anemone.get_arm_tip(anemone.arm_count / 2).distance_to(rest_tip) < 2.0, "生物走了：彈回原本的位置")
	await _free(tank)


func _test_plant_limit() -> void:
	print("--- 水草上限 ---")
	var tank: Tank = await _spawn({"max_plants": 5})
	var plants: Array[Node] = tank.get_node("%Plants").get_children()
	var visible_count: int = plants.filter(func(plant: Node) -> bool: return (plant as Node2D).visible).size()
	_expect(visible_count == 5, "上限 5：只顯示 5 個（共 %d 個）" % plants.size())
	_expect("太多" in tank.get_node("%HUD").call("get_message"), "顯示提示")
	await _free(tank)


func _test_no_player() -> void:
	print("--- 沒有玩家生物 ---")
	var tank: Tank = await _spawn({"player_design": null})
	await _frames(5)
	_expect(tank.player == null and "還沒有設定玩家生物" in tank.get_node("%HUD").call("get_message"), "顯示提示")
	tank.drop_food(Vector2(300, 300))
	await _frames(5)
	_expect(is_instance_valid(tank), "沒有玩家也不會當掉")
	await _free(tank)


# ---------------------------------------------------------------- 工具


func _spawn(settings: Dictionary) -> Tank:
	var tank: Tank = TANK_SCENE.instantiate()
	for key: String in settings:
		tank.set(key, settings[key])
	add_child(tank)
	await _frames(2)
	return tank


func _free(node: Node) -> void:
	node.queue_free()
	await _frames(2)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
