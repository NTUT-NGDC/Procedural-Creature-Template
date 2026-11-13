extends Node
## 大吃小的自動測試：
## 1. 吃得掉的倍數：體型剛好是對方的 eat_ratio 倍吃得掉，差一點就吃不掉
## 2. 咬頭：大的吃掉小的（小的消失、沿著身體掉飼料、吃掉幾隻 +1）；差不多大就兩隻都彈開
## 3. 被吃掉：玩家回到 0 級、換地方重生、無敵一下
## 4. 撞身體：自己掉「對方的等級」級（對方 0 級也掉 1 級；最多掉到 0 級），掉的變成飼料、一下子不能吃；彈開、無敵
## 5. 加速：比較快、消耗吃到一半的飼料、從尾巴掉出來；沒有吃到一半的飼料就不能加速
## 6. 標記：視野裡比你大的眼睛變紅、比你小的外框變綠，視野外沒有標記
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/eat_test.tscn

const TANK_SCENE: PackedScene = preload("res://game/tank/tank.tscn")
const SNAKE: String = "res://example/creatures/snake/design.tres"

var _failures: int = 0


func _ready() -> void:
	await _test_ratio()
	await _test_bite()
	await _test_eaten()
	await _test_hit()
	await _test_boost()
	await _test_marks()

	if _failures == 0:
		print("[大吃小測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[大吃小測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_ratio() -> void:
	print("--- 吃得掉的倍數 ---")
	var big: Creature = _creature(4)
	var small: Creature = _creature(0)
	add_child(big)
	add_child(small)
	var balance := CreatureBalance.new()
	var ratio: float = big.get_stats().size / small.get_stats().size
	balance.eat_ratio = ratio
	_expect(TankRules.can_eat(big, small, balance), "體型剛好是 %.2f 倍：吃得掉" % ratio)
	balance.eat_ratio = ratio + 0.01
	_expect(not TankRules.can_eat(big, small, balance), "差一點（要 %.2f 倍）：吃不掉" % balance.eat_ratio)
	_expect(not TankRules.can_eat(small, big, CreatureBalance.new()), "小的吃不掉大的")
	_expect(TankRules.hit_damage(3) == 3 and TankRules.hit_damage(0) == 1, "撞到 3 級的身體掉 3 級，撞到 0 級的掉 1 級")
	big.queue_free()
	small.queue_free()
	await _frames(2)


func _test_bite() -> void:
	print("--- 咬頭 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	player.set_level(6)
	var prey: Creature = await _add(tank, 0, Vector2(2000, 400))
	_place(player, prey.global_position + Vector2(prey.head_radius * 0.5, 0), PI)  # 面對面，頭碰頭
	await _frames(2)
	_expect(not is_instance_valid(prey) or prey.is_queued_for_deletion(), "6 級的蛇咬到 0 級的頭：吃掉")
	_expect(tank.kills == 1, "吃掉幾隻 +1")
	var expected: int = TankRules.dropped_food(1, player.get_balance())
	_expect(tank.get_node("%Foods").get_child_count() == expected, "被吃掉的掉了 %d 個飼料（%d 個）" % [expected, tank.get_node("%Foods").get_child_count()])

	var twin: Creature = await _add(tank, 6, Vector2(2000, 400))
	_place(player, twin.global_position + Vector2(twin.head_radius * 0.5, 0), PI)
	await _frames(2)
	_expect(is_instance_valid(twin) and not twin.is_queued_for_deletion() and player.level == 6, "一樣大：誰也吃不掉")
	_expect(player.knockback.x > 0.0 and twin.knockback.x < 0.0, "一樣大：兩隻往反方向彈開")
	await _free(tank)


func _test_eaten() -> void:
	print("--- 被吃掉 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	player.set_level(2)
	var hunter: Creature = await _add(tank, 10, Vector2(2000, 400))
	_place(player, hunter.global_position + Vector2(hunter.head_radius * 0.5, 0), PI)
	await _frames(2)
	_expect(player.level == 0 and is_instance_valid(player), "玩家被吃掉：回到 0 級")
	_expect(player.global_position.distance_to(hunter.global_position) > 200.0, "換到離得遠的地方重生（%.0f 像素）" % player.global_position.distance_to(hunter.global_position))
	_expect(player.is_invincible(), "重生後無敵一下")
	_expect("被吃掉" in tank.get_node("%HUD").call("get_message"), "顯示「被吃掉了」")
	await _free(tank)


func _test_hit() -> void:
	print("--- 撞身體 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	player.set_level(5)
	var other: Creature = await _add(tank, 2, Vector2(2000, 400))
	var tail: Vector2 = other.get_body().get_joint(other.get_body().joint_count() - 1)
	_place(player, tail, -PI / 2.0)  # 頭在對方的尾巴上，身體往下（不會被對方的頭碰到）
	await _frames(2)
	_expect(player.level == 3, "5 級撞到 2 級的身體：掉 2 級（剩 %d 級）" % player.level)
	_expect(is_instance_valid(other) and other.level == 2, "被撞的不會怎樣")
	_expect(player.is_invincible() and player.knockback != Vector2.ZERO, "撞到的彈開、無敵一下")
	var foods: Array[Node] = tank.get_node("%Foods").get_children()
	_expect(foods.size() == TankRules.dropped_food(2, player.get_balance()), "掉的 2 級變成 %d 個飼料" % foods.size())
	_expect(foods.all(func(food: Node) -> bool: return not food.is_in_group("food")), "剛掉的飼料一下子不能吃")
	await _seconds(1.0)
	_expect(foods.all(func(food: Variant) -> bool: return not is_instance_valid(food) or (food as Node).is_in_group("food")), "過一下就能吃了")

	player.set_level(1)
	player.invincible_time = 0.0
	other.set_level(0)
	await _frames(1)
	tail = other.get_body().get_joint(other.get_body().joint_count() - 1)
	_place(player, tail, -PI / 2.0)
	await _frames(2)
	_expect(player.level == 0, "撞到 0 級的身體：也掉 1 級")
	player.invincible_time = 0.0
	_place(player, tail, -PI / 2.0)
	await _frames(2)
	_expect(player.level == 0, "0 級再撞：最多掉到 0 級")
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
	player.food_progress = 0
	var empty: float = await _top_speed(player, true)
	_expect(empty < normal * 1.2 and not player.boosting, "沒有吃到一半的飼料：不能加速")
	_press(KEY_RIGHT, false)
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


func _test_marks() -> void:
	print("--- 標記 ---")
	var tank: Tank = await _spawn()
	var player: Creature = tank.player
	player.set_level(3)
	var sight: float = player.get_stats().sight
	var big: Creature = await _add(tank, 12, player.global_position + Vector2(sight * 0.6, -150))
	var small: Creature = await _add(tank, 0, player.global_position + Vector2(-sight * 0.6, -150))
	var far: Creature = await _add(tank, 0, player.global_position + Vector2(sight + 300, 300))
	await _frames(2)
	_expect(big.mark == Creature.Mark.DANGER, "視野裡比你大的：眼睛變紅")
	_expect(small.mark == Creature.Mark.PREY, "視野裡你吃得掉的：外框變綠")
	_expect(far.mark == Creature.Mark.NONE, "視野外：沒有標記")
	_expect(player.mark == Creature.Mark.NONE, "自己沒有標記")
	await _free(tank)


# ---------------------------------------------------------------- 工具


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
