extends Node
## 生態缸規則（像 Slither）的自動測試：
## 1. 撞身體：頭撞到別人的身體，撞人的死掉（玩家回 0 級、換地方重生、無敵一下；整隻散成大顆飼料，一下子不能吃），被撞的沒事
## 2. 擋路：別人撞到你的身體，牠死掉、你沒事，「撞倒幾隻」+1；不管誰大，大的撞到小的也是大的死
## 3. 頭碰頭：從側面撞過來的死、被撞的沒事；正面對撞兩隻都死
## 4. 無敵：重生無敵的時候，撞到別人、被別人撞都沒事
## 5. 加速：比較快、消耗飼料、從尾巴掉出小顆飼料；這一級的用完就掉一級繼續噴，噴到 0 級、一個都不剩才停
## 5-1. 操作（像 Slither）：滑鼠在頭上也一直往前衝；按任何鍵、滑鼠左鍵都加速；Esc、F1 不算；用方向鍵時方向鍵不算；工坊的生物不能加速
## 6. 飼料：大顆算好幾個（多的留到下一級）、自己長的照機率出大顆、浮著不會往下沉
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/eat_test.tscn

const TANK_SCENE: PackedScene = preload("res://game/tank/tank.tscn")
const SNAKE: String = "res://example/creatures/snake/design.tres"

var _failures: int = 0


func _ready() -> void:
	await _test_crash()
	await _test_block()
	await _test_head_on()
	await _test_invincible()
	await _test_boost()
	await _test_controls()
	await _test_food()

	if _failures == 0:
		print("[碰撞測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[碰撞測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_crash() -> void:
	print("--- 撞到別人的身體 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	player.set_level(5)
	var other: Creature = await _add(tank, 2, Vector2(2000, 400))
	_place(player, _tail(other), -PI / 2.0)  # 頭在對方的尾巴上，身體往下（不會被對方的頭碰到）
	await _frames(2)
	_expect(player.level == 0 and is_instance_valid(player), "5 級的玩家撞到 2 級的身體：死掉，回到 0 級")
	_expect(not _dead(other) and other.level == 2, "被撞的沒事")
	_expect(player.global_position.distance_to(other.global_position) > 200.0, "換到離得遠的地方重生（%.0f 像素）" % player.global_position.distance_to(other.global_position))
	_expect(player.is_invincible(), "重生後無敵一下")
	_expect("撞到別人" in tank.get_node("%HUD").call("get_message"), "顯示「撞到別人了」")
	_expect(tank.kills == 0, "自己撞死的：撞倒幾隻不會 +1")
	var foods: Array[Node] = tank.get_node("%Foods").get_children()
	var balance: CreatureBalance = player.get_balance()
	_expect(foods.size() == TankRules.dropped_food(5, balance), "5 級死掉：散成 %d 個飼料（%d 個）" % [TankRules.dropped_food(5, balance), foods.size()])
	_expect(foods.all(func(food: Node) -> bool: return (food as Food).value == balance.big_food_value), "都是大顆")
	_expect(foods.all(func(food: Node) -> bool: return not food.is_in_group("food")), "剛掉的飼料一下子不能吃")
	await _seconds(1.0)
	_expect(foods.all(func(food: Variant) -> bool: return not is_instance_valid(food) or (food as Node).is_in_group("food")), "過一下就能吃了")
	await _free(tank)


func _test_block() -> void:
	print("--- 擋路：別人撞到你 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	_place(player, Vector2(1200, 700), 0.0)
	var small: Creature = await _add(tank, 0, Vector2(400, 400))
	_place(small, _tail(player), -PI / 2.0)
	await _frames(2)
	_expect(_dead(small), "0 級的撞到玩家的身體：死掉")
	_expect(player.level == 0 and not player.is_invincible() and tank.kills == 1, "玩家沒事，撞倒幾隻 +1")
	_expect("撞倒一隻" in tank.get_node("%HUD").call("get_message"), "顯示「撞倒一隻」")
	var big: Creature = await _add(tank, 10, Vector2(400, 400))
	_place(big, _middle(player), -PI / 2.0)
	await _frames(2)
	_expect(_dead(big) and player.level == 0, "10 級的大隻撞到 0 級玩家的身體：也是大隻死")
	await _free(tank)


func _test_head_on() -> void:
	print("--- 頭碰頭 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	_place(player, Vector2(1200, 700), 0.0)
	player.velocity = Vector2(player.speed, 0)  # 往右游
	# 大隻從側面（上面）往下衝，撞到玩家的頭
	var big: Creature = await _add(tank, 10, Vector2(400, 400))
	_place(big, player.global_position + Vector2(0, -player.head_radius), PI / 2.0)
	big.velocity = Vector2(0, big.speed)
	await _frames(2)
	_expect(_dead(big), "大隻從側面撞到玩家的頭：大隻死")
	_expect(player.level == 0 and not player.is_invincible() and tank.kills == 1, "被撞的玩家沒事")

	# 正面對撞
	var twin: Creature = await _add(tank, 0, Vector2(400, 400))
	_place(twin, player.global_position + Vector2(player.head_radius, 0), PI)
	twin.velocity = Vector2(-twin.speed, 0)
	await _frames(2)
	_expect(_dead(twin) and player.is_invincible(), "正面對撞：兩隻都死")

	var balance: CreatureBalance = player.get_balance()
	var a: Creature = _creature(0)  # 只測規則，不放進缸裡（放進去馬上就撞了）
	var b: Creature = _creature(0)
	a.position = Vector2(400, 400)
	b.position = Vector2(420, 400)
	add_child(a)
	add_child(b)
	a.velocity = Vector2(balance.head_on_speed + 10.0, 0)
	b.velocity = Vector2(-(balance.head_on_speed - 10.0), 0)
	_expect(TankRules.head_on_rammers(a, b, balance) == [a], "對方衝得不夠快（%.0f）：只有衝過去的算撞人" % (balance.head_on_speed - 10.0))
	b.velocity = Vector2(-(balance.head_on_speed + 10.0), 0)
	_expect(TankRules.head_on_rammers(a, b, balance).size() == 2, "兩隻都衝超過 %.0f：兩隻都算" % balance.head_on_speed)
	a.queue_free()
	b.queue_free()
	await _free(tank)


func _test_invincible() -> void:
	print("--- 無敵 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	player.set_level(3)
	player.invincible_time = 5.0
	var other: Creature = await _add(tank, 2, Vector2(2000, 400))
	_place(player, _tail(other), -PI / 2.0)
	await _frames(2)
	_expect(player.level == 3 and not _dead(other), "無敵時撞到別人：都沒事")
	_place(other, _tail(player), -PI / 2.0)
	await _frames(2)
	_expect(not _dead(other), "無敵時被別人撞：撞的也沒事")
	await _free(tank)


func _test_boost() -> void:
	print("--- 加速 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	player.control_mode = Creature.Mode.WASD  # 用方向鍵往右游（模擬按鍵）
	player.set_process(true)
	_press(KEY_RIGHT, true)
	var normal: float = await _top_speed(player, false)
	player.food_progress = 2
	var foods_before: int = tank.get_node("%Foods").get_child_count()
	var boosted: float = await _top_speed(player, true)
	_expect(boosted > normal * 1.3, "加速比較快：%.0f → %.0f" % [normal, boosted])
	_expect(player.food_progress < 2, "加速消耗吃到一半的飼料（剩 %d 個）" % player.food_progress)
	_expect(tank.get_node("%Foods").get_child_count() > foods_before, "消耗的飼料從尾巴掉出來")
	_press(KEY_SPACE, false)
	_press(KEY_RIGHT, false)
	player.set_process(false)

	# 這一級的用完了：掉一級，從上一級的滿格繼續扣
	var cost: float = player.get_balance().boost_cost
	player.set_level(2)
	player.food_progress = 0
	var size_before: float = player.get_stats().size
	player.call("_update_boost", true, 1.01 / cost)  # 剛好消耗 1 個
	_expect(player.level == 1 and player.food_progress == player.get_stats().level_cost - 1, "2 級、進度 0 還能噴：掉到 1 級，進度 %d／%d" % [player.food_progress, player.get_stats().level_cost])
	_expect(player.get_stats().size < size_before, "掉級之後身體變小")
	var foods: Node = tank.get_node("%Foods")
	var count_before: int = foods.get_child_count()
	var remaining: int = player.food_progress + _cost_at(player, 0)  # 1 級剩的＋0 級的滿格
	for i: int in 500:
		player.call("_update_boost", true, 1.0)
		if not player.boosting:
			break
	_expect(player.level == 0 and player.food_progress == 0 and not player.can_boost(), "一直噴：噴到 0 級、一個都不剩才停（%d 級、%d 個）" % [player.level, player.food_progress])
	player.call("_update_boost", true, 1.0)
	_expect(not player.boosting, "0 級、一個都不剩：不能再噴")
	var dropped: Array[Node] = foods.get_children().slice(count_before)
	_expect(dropped.size() == remaining, "噴掉幾個就掉幾個飼料（%d 個）" % dropped.size())
	_expect(dropped.all(func(food: Node) -> bool: return (food as Food).value == 1), "噴出來的都是小顆")
	await _free(tank)


func _test_controls() -> void:
	print("--- 操作 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	_expect(player.tank_controls, "生態缸的玩家：Slither 操作")
	player.set_process(true)
	player.food_progress = 3
	# 滑鼠就在頭上：照樣往前衝
	var target: Dictionary = player.call("_get_move_target")
	_expect(is_equal_approx(float(target.speed), player.speed), "滑鼠不管在哪：都全速往前（%.0f）" % float(target.speed))
	for key: Key in [KEY_Q, KEY_SPACE, KEY_1]:
		_press(key, true)
		await _frames(1)
		_expect(player.call("_read_boost"), "按住 %s：加速" % OS.get_keycode_string(key))
		_press(key, false)
		await _frames(1)
		_expect(not player.call("_read_boost"), "放開 %s：不加速" % OS.get_keycode_string(key))
	for key: Key in [KEY_ESCAPE, KEY_F1]:
		_press(key, true)
		await _frames(1)
		_expect(not player.call("_read_boost"), "按 %s 不算加速" % OS.get_keycode_string(key))
		_press(key, false)
		await _frames(1)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	_expect(player.call("_read_boost"), "按住滑鼠左鍵：加速")
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(1)
	player.control_mode = Creature.Mode.WASD
	_press(KEY_W, true)
	await _frames(1)
	_expect(not player.call("_read_boost"), "用方向鍵操作：按 W 是轉方向、不算加速")
	_press(KEY_W, false)
	await _frames(1)
	target = player.call("_get_move_target")
	_expect(is_equal_approx(float(target.speed), player.speed), "用方向鍵操作：放開也照樣往前衝")
	player.tank_controls = false
	player.control_mode = Creature.Mode.MOUSE
	_press(KEY_Q, true)
	await _frames(1)
	_expect(not player.call("_read_boost"), "不是生態缸的玩家（工坊、沙盒）：按鍵不會加速")
	_press(KEY_Q, false)
	await _frames(1)
	player.set_process(false)
	await _free(tank)


## 模擬按下（放開）滑鼠的一個鍵
func _mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(event)


## creature 在 level 級時，升一級要吃幾個
func _cost_at(creature: Creature, at_level: int) -> int:
	var old: int = creature.level
	var progress: int = creature.food_progress
	creature.set_level(at_level)
	var cost: int = creature.get_stats().level_cost
	creature.set_level(old)
	creature.food_progress = progress
	return cost


func _test_food() -> void:
	print("--- 飼料 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	var balance: CreatureBalance = player.get_balance()
	var cost: int = player.get_stats().level_cost
	player.food_progress = cost - 1
	var big := Food.new()
	big.value = balance.big_food_value
	player.eat(big)
	_expect(player.level == 1 and player.food_progress == balance.big_food_value - 1, "差 1 個升級時吃大顆（%d 個）：升 1 級，多的 %d 個留到下一級" % [balance.big_food_value, player.food_progress])

	var foods: Node = tank.get_node("%Foods")
	tank.drop_food(Vector2(600, 300), true, true)
	tank.drop_food(Vector2(700, 300), true)
	var dropped_big: Food = foods.get_child(foods.get_child_count() - 2)
	var dropped_small: Food = foods.get_child(foods.get_child_count() - 1)
	_expect(dropped_big.value == balance.big_food_value and dropped_big.radius > dropped_small.radius and dropped_small.value == 1, "大顆比較大、算 %d 個；小顆算 1 個" % balance.big_food_value)
	await _frames(30)
	_expect(is_equal_approx(dropped_small.global_position.y, 300.0), "沒有水流時，飼料停在原地、不往下沉（y = %.1f）" % dropped_small.global_position.y)

	tank.balance.food_interval = 0.01
	tank.balance.big_food_chance = 1.0
	var before: int = foods.get_child_count()
	await _frames(5)
	var grown: Array[Node] = foods.get_children().slice(before)
	_expect(not grown.is_empty() and grown.all(func(food: Node) -> bool: return (food as Food).value == balance.big_food_value), "大顆機率 1：自己長的都是大顆（%d 個）" % grown.size())
	tank.balance.big_food_chance = 0.0
	before = foods.get_child_count()
	await _frames(5)
	grown = foods.get_children().slice(before)
	_expect(not grown.is_empty() and grown.all(func(food: Node) -> bool: return (food as Food).value == 1), "大顆機率 0：自己長的都是小顆（%d 個）" % grown.size())
	await _free(tank)


## 按住（或放開）空白鍵游 0.8 秒，回傳最後的速度
func _top_speed(creature: Creature, boost: bool) -> float:
	_press(KEY_SPACE, boost)
	await _seconds(0.8)  # headless 的一幀很短，用時間算
	var top: float = creature.velocity.length()
	_press(KEY_SPACE, false)
	await get_tree().process_frame
	return top


## 模擬按下（放開）一個鍵
func _press(keycode: Key, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.keycode = keycode
	key.pressed = pressed
	Input.parse_input_event(key)


# ---------------------------------------------------------------- 工具


## 死掉了沒（死掉的過一下就被刪掉）
func _dead(creature: Variant) -> bool:
	return not is_instance_valid(creature) or (creature as Node).is_queued_for_deletion()


## 尾巴最後一節的位置
func _tail(creature: Creature) -> Vector2:
	var body: ChainBody = creature.get_body()
	return body.get_joint(body.joint_count() - 1)


## 身體中間那一節的位置
func _middle(creature: Creature) -> Vector2:
	var body: ChainBody = creature.get_body()
	return body.get_joint(body.joint_count() / 2)


## 一隻停住不動的蛇（level 級）
func _creature(level: int) -> Creature:
	var creature := Creature.new()
	creature.design = load(SNAKE)
	creature.control_mode = Creature.Mode.WANDER
	creature.level = level
	return creature


func _add(tank: Tank, level: int, at: Vector2) -> Creature:
	var creature: Creature = _creature(level)
	creature.position = at
	tank.add_creature(creature)
	creature.set_process(false)
	creature.reset_pose()
	await _frames(1)
	return creature


## 把生物停住、移到 at、頭朝 heading，身體拉直
func _place(creature: Creature, at: Vector2, heading: float) -> void:
	creature.set_process(false)
	creature.global_position = at
	creature.heading = heading
	creature.reset_pose()


func _spawn() -> Tank:
	var tank: Tank = TANK_SCENE.instantiate()
	tank.balance = CreatureBalance.get_default().duplicate()  # 自己一份，改了不影響別的測試
	tank.balance.food_interval = 0.0
	tank.flow_strength = 0.0
	tank.population = 1  # 沒有 NPC（NPC 在 npc_test 測）
	add_child(tank)
	await _frames(2)
	tank.player.set_process(false)
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
