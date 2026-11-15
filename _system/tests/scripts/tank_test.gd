extends Node
## 生態缸的自動測試：
## 1. 開始：玩家生物照設計檔長出來、滑鼠控制，速度和頭的大小來自能力；水流照設定
##    大地圖：玩家在地圖中央、鏡頭跟著玩家，到邊緣鏡頭停住、眼睛越多鏡頭拉得越遠、生物游不出地圖
## 2. 飼料：點一下放一個；最多 max_food 個（平衡資料）；被水流帶著飄、不會跑出地圖或進沙地；缸裡會自己長（間隔 0 就不長）
## 3. 吃東西：頭碰到就吃掉；吃滿「升一級要吃幾個」才升級，升級後照長大方式變大
## 4. 水草：有水流時會歪；生物經過被撥開（點在身體外面），生物走了會站回來
## 5. 海葵：觸手被生物推開，再彈回來
## 6. 水草、海葵超過上限：多的藏起來、顯示提示
## 7. 沒有玩家生物：顯示提示、不會當掉；玩家生物超過複雜度上限：不放進來、顯示提示
## 8. 離開生態缸：水流歸零
## 9. 對戰地圖（battle_tank.tscn）：3 × 3、沒有 NPC、水草海葵都在沙地上；
##    復活位置：離每隻生物的頭、身體越遠越好；點滑鼠不會放飼料
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
	await _test_battle_tank()

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
	var tank: Tank = await _spawn({"world_size": Vector2(2560, 1440), "food_interval": 0.0})
	var player: Creature = tank.player
	_expect(player.global_position.distance_to(Vector2(1280, 720)) < 50.0 and player.bounds == Rect2(0, 0, 2560, 1440), "玩家在地圖中央，範圍是整張地圖")
	_expect(tank.camera != null and tank.camera.is_current(), "有跟著玩家的鏡頭")
	player.set_process(false)  # 先停住，才不會跟著滑鼠跑掉
	player.global_position = Vector2(1600, 900)
	await _seconds(1.0)
	_expect(tank.camera.get_screen_center_position().distance_to(player.global_position) < 20.0, "鏡頭跟著玩家走（差 %.0f 像素）" % tank.camera.get_screen_center_position().distance_to(player.global_position))
	player.global_position = Vector2(2550, 1430)
	await _seconds(1.0)
	var view: Rect2 = tank.view_rect()
	_expect(absf(view.end.x - 2560.0) < 1.0 and absf(view.end.y - 1440.0) < 1.0, "玩家在角落：鏡頭停在地圖邊緣，看不到外面（畫面右下角 %v）" % view.end)

	# 視野越大，鏡頭拉得越遠
	var balance: CreatureBalance = tank.get_balance()
	_expect(is_equal_approx(TankRules.camera_zoom(balance.base_sight, balance), 1.0) and is_equal_approx(TankRules.camera_zoom(balance.max_sight * 2.0, balance), balance.max_zoom_out), "鏡頭：沒有眼睛不拉遠，視野到上限拉到 %.2f 倍" % balance.max_zoom_out)
	var sight_now: float = player.get_stats().sight
	var size_before: Vector2 = tank.view_rect().size
	player.design = CreatureDesign.from_data(player.design.to_dict())  # 複製一份來改，不動到範例
	player.design.eyes[0].count = 6
	player.design.eyes[0].size = 1.0
	player.apply_design()
	await _seconds(2.0)
	_expect(player.get_stats().sight > sight_now and tank.view_rect().size.x > size_before.x + 100.0, "眼睛變多（視野 %.0f → %.0f）：看到的地圖變大（寬 %.0f → %.0f）" % [sight_now, player.get_stats().sight, size_before.x, tank.view_rect().size.x])
	player.global_position = Vector2(3000, -100)
	player.set_process(true)
	await _frames(2)
	_expect(Rect2(0, 0, 2560, 1440).grow(0.5).has_point(player.global_position), "生物游不出地圖")
	tank.drop_food(Vector2(2500, 100))
	_expect(tank.get_node("%Foods").get_child(0).max_x == 2560.0, "飼料的範圍是整張地圖")
	await _free(tank)


func _test_food() -> void:
	print("--- 飼料 ---")
	var tank: Tank = await _spawn({"food_interval": 0.0, "max_food": 5})
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
	var start: Vector2 = food.global_position
	await _seconds(0.5)
	_expect(food.global_position != start, "飼料被水流帶著飄（沒有水流時停在原地、不往下沉，在 eat_test 測）")
	food.global_position.y = tank.floor_y() + 50.0
	await _frames(2)
	_expect(food.global_position.y <= tank.floor_y(), "飄到底就擋住，不會跑進沙地")
	food.global_position.y = -50.0
	await _frames(2)
	_expect(food.global_position.y >= 0.0, "飄到最上面也擋住，不會跑出地圖")
	await _free(tank)

	tank = await _spawn({"food_interval": 0.1, "max_food": 50})
	tank.player.set_process(false)
	tank.player.global_position = Vector2(-500, -500)
	await _seconds(0.55)
	var count: int = tank.get_node("%Foods").get_child_count()
	_expect(count >= 3, "缸裡會自己長食物：0.55 秒長了 %d 個" % count)
	await _free(tank)


func _test_eat_and_grow() -> void:
	print("--- 吃東西、升級 ---")
	var tank: Tank = await _spawn({"food_interval": 0.0})
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
	var tank: Tank = await _spawn({"flow_strength": 60.0, "food_interval": 0.0})
	tank.player.set_process(false)
	var weed: Weed = tank.get_node("%Plants").get_child(3) as Weed
	tank.player.global_position = _away(weed)
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
	tank.player.global_position = _away(weed)
	tank.player.reset_pose()
	await _seconds(3.0)
	_expect(weed.get_tip().distance_to(straight_tip) < 5.0, "生物走了、沒有水流：站回原本的樣子（差 %.1f 像素）" % weed.get_tip().distance_to(straight_tip))
	await _free(tank)


func _test_anemone() -> void:
	print("--- 海葵 ---")
	var tank: Tank = await _spawn({"flow_strength": 0.0, "food_interval": 0.0})
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
	tank.player.global_position = _away(anemone)
	tank.player.reset_pose()
	await _seconds(2.0)
	_expect(anemone.get_arm_tip(anemone.arm_count / 2).distance_to(rest_tip) < 2.0, "生物走了：彈回原本的位置")
	await _free(tank)


func _test_plant_limit() -> void:
	print("--- 水草上限 ---")
	var tank: Tank = await _spawn({"max_plants": 5})
	var plants: Array[Node] = tank.get_node("%Plants").get_children()
	var active: Array = tank.get("_active_plants")
	var hidden_rest: bool = plants.slice(5).all(func(plant: Node) -> bool: return not (plant as Node2D).visible and plant.process_mode == Node.PROCESS_MODE_DISABLED)
	_expect(active.size() == 5 and hidden_rest, "上限 5：只有 5 個會動、會顯示（共 %d 個）" % plants.size())
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
	tank = await _spawn({"player_design": load(SNAKE), "max_complexity": 20})
	await _frames(2)
	_expect(tank.player == null and "太複雜" in tank.get_node("%HUD").call("get_message"), "蛇（26 點）超過上限 20：不放進來、顯示提示")
	await _free(tank)


func _test_battle_tank() -> void:
	print("--- 對戰地圖、復活位置 ---")
	var tank: Tank = (load("res://game/tank/battle_tank.tscn") as PackedScene).instantiate()
	add_child(tank)
	await _seconds(0.5)
	_expect(tank.world_size == Vector2(3840, 2160) and tank.npc_count() == 0, "3 × 3 地圖（%v），沒有 NPC（%d 隻）" % [tank.world_size, tank.npc_count()])
	var plants: Array[Node] = tank.get_node("Plants").get_children()
	var on_floor: bool = true
	for plant: Node in plants:
		var position: Vector2 = (plant as Node2D).position
		on_floor = on_floor and position.x >= 0.0 and position.x <= tank.world_size.x and position.y > tank.world_size.y - 100.0
	_expect(plants.size() > 34 and on_floor, "水草、海葵 %d 個，都在地圖裡的沙地上" % plants.size())
	_expect(plants.size() <= tank.max_plants, "沒有超過水草上限（%d）" % tank.max_plants)
	var foods_before: int = tank.get_node("%Foods").get_child_count()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	tank.call("_unhandled_input", click)
	_expect(not tank.click_to_feed and tank.get_node("%Foods").get_child_count() == foods_before, "對戰地圖：點滑鼠不會放飼料")

	var big := Creature.new()
	big.design = load("res://example/creatures/octopus/design.tres")
	big.control_mode = Creature.Mode.WANDER
	big.level = 10
	big.position = Vector2(1000, 1000)
	tank.add_creature(big)
	var small := Creature.new()
	small.design = load("res://example/creatures/doodle/design.tres")
	small.control_mode = Creature.Mode.WANDER
	small.position = Vector2(3000, 1000)
	tank.add_creature(small)
	await _frames(2)
	big.set_process(false)
	small.set_process(false)
	var player: Creature = tank.player
	player.set_level(0)
	var others: Array[Creature] = [big, small]
	var near_big: float = TankRules.spawn_room(_tail_of(big) + Vector2(0, 100), others)
	_expect(near_big > 0.0 and near_big <= 100.0, "離大章魚的尾巴 100：空間是到身體的距離（%.0f），頭和身體都算" % near_big)
	_expect(TankRules.spawn_room(Vector2(2000, 1800), others) > 500.0, "離大家都很遠：空間很大")
	var safe: bool = true
	for i: int in 10:
		tank.call("_respawn_player")
		safe = safe and TankRules.spawn_room(player.global_position, others) > 300.0
	_expect(safe, "復活 10 次：都離每隻生物的頭、身體 300 以上")
	await _free(tank)


# ---------------------------------------------------------------- 工具


func _tail_of(creature: Creature) -> Vector2:
	var body: ChainBody = creature.get_body()
	return body.get_joint(body.joint_count() - 1)


## 離植物遠一點、但鏡頭還看得到它的地方（看不到的植物會暫停）
func _away(plant: Node2D) -> Vector2:
	return plant.global_position + Vector2(450, -450)


func _spawn(settings: Dictionary) -> Tank:
	var tank: Tank = TANK_SCENE.instantiate()
	tank.population = 1  # 沒有 NPC，才不會來搶飼料、撞玩家（NPC 在 npc_test 測）
	tank.balance = CreatureBalance.get_default().duplicate()  # 自己一份，改了不影響別的測試
	for key: String in settings:
		if key in tank.balance:
			tank.balance.set(key, settings[key])  # 飼料的數字在平衡資料裡
		else:
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
