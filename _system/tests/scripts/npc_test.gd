extends Node
## NPC 的自動測試：
## 1. 開始：NPC 的數量＝缸裡總數－玩家人數；不同設計檔、等級在範圍內、不會生在玩家旁邊
## 2. 再生：NPC 死掉，過一下再生一隻（不是馬上）
## 3. 大腦：附近有別的生物就衝到牠的頭前面擋路（快到了就加速）、看得到飼料就吃、都沒有就漫遊；太遠、無敵的不理；會避開別人的頭和身體
## 4. 等級上限：到了最高級，吃再多也不會長大
## 5. 在生態缸裡：NPC 真的會衝到玩家的頭前面
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/npc_test.tscn

const TANK_SCENE: PackedScene = preload("res://game/tank/tank.tscn")
const SNAKE: String = "res://example/creatures/snake/design.tres"
## 大腦測試用的範圍（很大，不會碰到邊緣）
const AREA: Rect2 = Rect2(0, 0, 4000, 4000)

var _failures: int = 0


func _ready() -> void:
	await _test_start()
	await _test_respawn()
	await _test_brain()
	await _test_max_level()
	await _test_in_tank()

	if _failures == 0:
		print("[NPC 測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[NPC 測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_start() -> void:
	print("--- 開始 ---")
	var tank: Tank = await _spawn({})
	var npcs: Array[Creature] = _npcs(tank)
	_expect(npcs.size() == tank.population - 1, "缸裡總數 %d、玩家 1 隻：NPC %d 隻" % [tank.population, npcs.size()])
	var designs: Dictionary = {}
	var ok: bool = true
	for npc: Creature in npcs:
		designs[npc.design] = true
		ok = ok and npc.brain.is_valid() and npc.bounds == tank.world_rect() and npc.level >= 0 and npc.level <= tank.npc_max_level
	_expect(ok, "每隻 NPC 都有大腦、範圍是整張地圖、等級在 0～%d" % tank.npc_max_level)
	_expect(designs.size() >= 2, "NPC 用了 %d 種設計檔" % designs.size())
	var nearest: float = INF
	for npc: Creature in npcs:
		nearest = minf(nearest, npc.global_position.distance_to(tank.player.global_position))
	_expect(nearest > 200.0, "不會生在玩家旁邊（最近 %.0f 像素）" % nearest)
	await _free(tank)

	tank = await _spawn({"population": 4})
	_expect(_npcs(tank).size() == 3, "缸裡總數 4：NPC 3 隻")
	await _free(tank)


func _test_respawn() -> void:
	print("--- 再生 ---")
	var tank: Tank = await _spawn({"population": 4, "npc_respawn_time": 0.4})
	_npcs(tank)[0].queue_free()
	await _frames(2)
	_expect(tank.npc_count() == 2, "死掉一隻：剩 2 隻（不是馬上再生）")
	await _seconds(0.6)
	_expect(tank.npc_count() == 3, "過一下再生一隻：回到 3 隻")
	await _free(tank)


func _test_brain() -> void:
	print("--- 大腦 ---")
	var me: Creature = _creature(5, Vector2(1000, 1000), 0.0)
	var sight: float = me.get_stats().sight
	var no_food: Array[Node] = []
	var other: Creature = _creature(0, Vector2(1000 + sight * 0.3, 1000), -PI / 2.0)  # 頭朝上，身體往下
	var ahead: Vector2 = other.global_position + Vector2(0, -other.head_radius * NpcBrain.BLOCK_AHEAD)
	var decision: Dictionary = NpcBrain.choose_target(me, [me, other], no_food)
	var want: float = (ahead - me.global_position).angle()
	_expect(not decision.is_empty() and absf(angle_difference(decision.angle, want)) < 0.3, "附近有別的生物：衝到牠的頭前面（%.0f 度，前面在 %.0f 度）" % [rad_to_deg(decision.get("angle", 0.0)), rad_to_deg(want)])
	_expect(not decision.get("boost", true), "離擋路的位置還遠：不加速")
	_place(other, me.global_position + Vector2(40, other.head_radius * NpcBrain.BLOCK_AHEAD), -PI / 2.0)  # 牠頭前面的位置就在 me 旁邊
	decision = NpcBrain.choose_target(me, [me, other], no_food)
	_expect(decision.get("boost", false), "快到擋路的位置：加速")
	other.invincible_time = 5.0
	_expect(NpcBrain.choose_target(me, [me, other], no_food).is_empty(), "無敵的（剛重生）：不理")
	other.invincible_time = 0.0
	_place(other, Vector2(1000 + sight * 0.6, 1000), -PI / 2.0)
	_expect(NpcBrain.choose_target(me, [me, other], no_food).is_empty(), "太遠（視野的 6 成）：不理（漫遊）")

	var food := Food.new()
	food.position = Vector2(1000, 1000 + sight * 0.5)
	add_child(food)
	var foods: Array[Node] = [food]
	decision = NpcBrain.choose_target(me, [me], foods)
	_expect(not decision.is_empty() and absf(angle_difference(decision.angle, PI / 2.0)) < 0.3, "看得到飼料：往飼料游（%.0f 度）" % rad_to_deg(decision.get("angle", 0.0)))
	food.queue_free()

	var wall: Creature = _creature(0, Vector2(1040, 850), -PI / 2.0)  # 頭朝上，身體往下擋在 me 右邊
	var push: Vector2 = NpcBrain.avoid_bodies(me, [me, wall])
	_expect(push.x < 0.0, "旁邊有別人的身體：往外避開（%.2f, %.2f）" % [push.x, push.y])
	_place(wall, Vector2(1030, 1000), -PI / 2.0)  # 別人的頭就在 me 右邊
	push = NpcBrain.avoid_bodies(me, [me, wall])
	_expect(push.x < 0.0, "旁邊有別人的頭：也要避開（撞到頭也會死）（%.2f, %.2f）" % [push.x, push.y])
	for node: Creature in [me, other, wall]:
		node.queue_free()
	await _frames(2)


func _test_max_level() -> void:
	print("--- 等級上限 ---")
	var npc: Creature = _creature(2, Vector2(500, 500), 0.0)
	npc.max_level = 2
	for i: int in 30:
		var food := Food.new()
		add_child(food)
		npc.eat(food)
	_expect(npc.level == 2, "最高 2 級：吃了 30 個還是 2 級")
	npc.queue_free()
	await _frames(2)


func _test_in_tank() -> void:
	print("--- 在生態缸裡 ---")
	var snake_only: Array[CreatureDesign] = [load(SNAKE)]
	var tank: Tank = await _spawn({"population": 1, "npc_designs": snake_only, "npc_level_spread": 0})
	var player: Creature = tank.player
	player.set_process(false)
	player.global_position = Vector2(1000, 700)
	player.heading = 0.0
	player.reset_pose()
	var ahead: Vector2 = player.global_position + Vector2(player.head_radius * NpcBrain.BLOCK_AHEAD, 0)
	var blocker: Creature = tank.spawn_npc()
	var sight: float = blocker.get_stats().sight
	_place(blocker, Vector2(1000 + sight * 0.25, 700 + sight * 0.25), -PI / 2.0)  # 在玩家右下方（擋路範圍裡），頭朝上
	var start: float = blocker.global_position.distance_to(ahead)
	var closest: float = start  # 這 1 秒內最接近的距離（衝到之後會繞過頭再轉回來，只看最後一刻不準）
	var end_time: int = Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < end_time and is_instance_valid(blocker) and not blocker.is_queued_for_deletion():
		closest = minf(closest, blocker.global_position.distance_to(ahead))
		await get_tree().process_frame
	var dead: bool = not is_instance_valid(blocker) or blocker.is_queued_for_deletion()
	_expect(not dead and closest < start - 50.0, "NPC 衝到玩家的頭前面：離擋路的位置 %.0f → 最近 %.0f" % [start, closest])
	await _free(tank)


# ---------------------------------------------------------------- 工具


## 一隻停住的蛇（不在生態缸裡，大腦測試用）
func _creature(level: int, at: Vector2, heading: float) -> Creature:
	var creature := Creature.new()
	creature.design = load(SNAKE)
	creature.control_mode = Creature.Mode.WANDER
	creature.level = level
	creature.bounds = AREA
	add_child(creature)
	creature.set_process(false)
	_place(creature, at, heading)
	return creature


func _place(creature: Creature, at: Vector2, heading: float) -> void:
	creature.global_position = at
	creature.heading = heading
	creature.reset_pose()


func _npcs(tank: Tank) -> Array[Creature]:
	return tank.get_creatures().filter(func(creature: Creature) -> bool: return creature.is_in_group("npc"))


func _spawn(settings: Dictionary) -> Tank:
	var tank: Tank = TANK_SCENE.instantiate()
	tank.balance = CreatureBalance.get_default().duplicate()  # 自己一份，改了不影響別的測試
	tank.balance.food_interval = 0.0
	tank.flow_strength = 0.0
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
