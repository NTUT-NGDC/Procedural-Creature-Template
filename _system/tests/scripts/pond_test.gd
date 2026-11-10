extends Node
## 池塘小遊戲的自動測試：
## 1. 三種勝利條件都能贏：長到目標長度、撐過時間、吃滿幾個
## 2. 會輸：被咬到長度剩 2、時間限制到了
## 3. 天敵 0 隻（和平模式）＋撐過時間：時間到正常結束
## 4. 玩家生物沒有身體（只有觸手）也能玩：會長大、會贏
## 5. 再來一場：長度、吃了幾個、時間、天敵、食物都重設，遊戲恢復進行
## 6. 規則屬性：被咬少一半、天敵會變多、食物會逃跑、天敵偵測距離、玩家控制方式
## 7. 設定有問題（沒有玩家生物、根節點不是 Creature）：顯示提示、不會當掉
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/pond_test.tscn

const POND_SCENE: PackedScene = preload("res://example/pond/pond.tscn")
const CREATURE_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/creature.gd")
const TENTACLE_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/tentacle.gd")

var _failures: int = 0


func _ready() -> void:
	await _test_win_by_length()
	await _test_win_by_survive_peaceful()
	await _test_win_by_eating()
	await _test_lose_by_bites()
	await _test_lose_by_time_limit()
	await _test_no_body_player()
	await _test_restart()
	await _test_rules()
	await _test_bad_settings()

	get_tree().paused = false
	if _failures == 0:
		print("[池塘測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[池塘測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_win_by_length() -> void:
	print("--- 勝利條件：長到目標長度 ---")
	var pond: Pond = await _spawn({"target_value": 13, "predator_count": 0})
	var results: Array[bool] = _watch(pond)
	var player: Creature = _player(pond)
	_expect(player.get_length() == 10, "一開始長度 10（跟身體幾節無關）")
	_expect(_status(pond).begins_with("長度 10 / 13"), "HUD 顯示「長度 10 / 13」")
	for i: int in 3:
		player.eat(_any_food(pond))
	await get_tree().process_frame
	_expect(results == [true], "吃 3 個長到 13：贏了")
	_expect(get_tree().paused and _result_visible(pond), "結算時遊戲暫停、顯示結算畫面")
	_expect(not pond.get_node("%PauseMenu").visible, "結算時藏起暫停選單")
	await _free(pond)


func _test_win_by_survive_peaceful() -> void:
	print("--- 勝利條件：撐過時間（和平模式） ---")
	var pond: Pond = await _spawn({"win_condition": Pond.WinCondition.SURVIVE, "target_value": 1, "predator_count": 0})
	var results: Array[bool] = _watch(pond)
	_expect(pond.get_node("%Creatures").get_child_count() == 1, "天敵 0 隻：池塘裡只有玩家")
	_expect("還要撐" in _status(pond), "HUD 顯示「還要撐幾秒」")
	await get_tree().create_timer(1.3).timeout
	_expect(results == [true], "撐過 1 秒：贏了")
	await _free(pond)


func _test_win_by_eating() -> void:
	print("--- 勝利條件：吃滿幾個 ---")
	var pond: Pond = await _spawn({"win_condition": Pond.WinCondition.EAT, "target_value": 2, "predator_count": 0})
	var results: Array[bool] = _watch(pond)
	var player: Creature = _player(pond)
	player.eat(_any_food(pond))
	await get_tree().process_frame
	_expect(results.is_empty() and _status(pond).begins_with("吃了 1 / 2"), "吃 1 個：還沒贏，HUD「吃了 1 / 2」")
	player.eat(_any_food(pond))
	await get_tree().process_frame
	_expect(results == [true], "吃 2 個：贏了")
	await _free(pond)


func _test_lose_by_bites() -> void:
	print("--- 輸：被咬到剩 2 ---")
	var pond: Pond = await _spawn({"predator_count": 1, "bite_damage": 3})
	var results: Array[bool] = _watch(pond)
	var player: Creature = _player(pond)
	var predator: Creature = pond.get("_predators")[0]
	for bite: int in 3:
		pond.set("_invincible_until", 0.0)
		pond.get("_retreating").clear()
		predator.global_position = player.global_position
		for i: int in 4:
			await get_tree().physics_frame
	_expect(player.get_length() == 2, "被咬 3 次、每次少 3：10 → 2（實際 %d）" % player.get_length())
	_expect(results == [false], "長度剩 2：輸了")
	await _free(pond)


func _test_lose_by_time_limit() -> void:
	print("--- 輸：時間限制到了 ---")
	var pond: Pond = await _spawn({"time_limit": 1, "predator_count": 0})
	var results: Array[bool] = _watch(pond)
	_expect("剩 1 秒" in _status(pond), "HUD 顯示剩幾秒")
	await get_tree().create_timer(1.3).timeout
	_expect(results == [false], "時間到還沒長到目標：輸了")
	_expect("時間到" in (pond.get_node("%ResultTitle") as Label).text, "結算標題是「時間到了！」")
	await _free(pond)


func _test_no_body_player() -> void:
	print("--- 玩家沒有身體（只有觸手） ---")
	var creature: Creature = CREATURE_SCRIPT.new()
	creature.name = "TentacleOnly"
	var tentacle: Node = TENTACLE_SCRIPT.new()
	tentacle.name = "Tentacle"
	creature.add_child(tentacle)
	tentacle.owner = creature
	var scene := PackedScene.new()
	scene.pack(creature)
	creature.free()

	var pond: Pond = await _spawn({"player_creature": scene, "target_value": 12, "predator_count": 0})
	var results: Array[bool] = _watch(pond)
	var player: Creature = _player(pond)
	_expect(player != null and player.get_body() == null, "玩家沒有 ChainBody")
	var start: Vector2 = player.global_position
	player.control_mode = Creature.Mode.WANDER
	for i: int in 20:
		await get_tree().process_frame
	_expect(player.global_position != start, "會移動")
	player.eat(_any_food(pond))
	player.eat(_any_food(pond))
	await get_tree().process_frame
	_expect(results == [true], "吃 2 個長到 12：贏了")
	await _free(pond)


func _test_restart() -> void:
	print("--- 再來一場 ---")
	var pond: Pond = await _spawn({"target_value": 11, "predator_count": 2})
	var results: Array[bool] = _watch(pond)
	var old_player: Creature = _player(pond)
	old_player.eat(_any_food(pond))
	await get_tree().process_frame
	_expect(results == [true], "第一場贏了")
	(pond.get_node("%RestartButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Creature = _player(pond)
	_expect(player != old_player and not is_instance_valid(old_player), "換了一隻新的玩家，舊的清掉了")
	_expect(player.get_length() == 10 and pond.get("_eaten") == 0 and pond.get("_elapsed") < 0.5, "長度、吃了幾個、時間都重設")
	_expect(pond.get("_predators").size() == 2 and pond.get_node("%Creatures").get_child_count() == 3, "天敵重新放 2 隻，沒有留下舊的")
	_expect(pond.get_node("%Foods").get_child_count() == 6, "食物重新放 6 個")
	_expect(not get_tree().paused and not _result_visible(pond) and pond.get_node("%PauseMenu").visible, "解除暫停、藏起結算、暫停選單回來")
	player.eat(_any_food(pond))
	await get_tree().process_frame
	_expect(results == [true, true], "第二場也能正常結束")
	await _free(pond)


func _test_rules() -> void:
	print("--- 規則屬性 ---")
	# 被咬少一半
	var pond: Pond = await _spawn({"bite_halves": true, "predator_count": 1})
	var player: Creature = _player(pond)
	player.grow(4)
	var predator: Creature = pond.get("_predators")[0]
	predator.global_position = player.global_position
	for i: int in 4:
		await get_tree().physics_frame
	_expect(player.get_length() == 7, "被咬少一半：14 → 7（實際 %d）" % player.get_length())
	_expect(predator.control_mode == Creature.Mode.FLEE, "咬完天敵退開")
	await get_tree().create_timer(Pond.RETREAT_TIME + 0.2).timeout
	_expect(predator.control_mode == Creature.Mode.CHASE, "1 秒後天敵回去追玩家")
	await _free(pond)

	# 天敵會變多
	pond = await _spawn({"predator_count": 1, "predator_every": 2, "target_value": 99})
	_player(pond).grow(5)
	await get_tree().process_frame
	_expect(pond.get("_predators").size() == 3, "每長 2 節多一隻：長 5 節後 1 + 2 = 3 隻（實際 %d）" % pond.get("_predators").size())
	await _free(pond)

	# 天敵速度、偵測距離、群組
	pond = await _spawn({"predator_count": 1, "predator_speed_scale": 2.0, "predator_detect_range": 77.0})
	predator = pond.get("_predators")[0]
	_expect(is_equal_approx(predator.speed, 360.0) and is_equal_approx(predator.detect_range, 77.0), "天敵速度 ×2、偵測距離 77")
	_expect(predator.control_mode == Creature.Mode.CHASE and predator.is_in_group("predator"), "天敵改成追玩家、在 predator 群組")
	await _free(pond)

	# 玩家控制方式
	pond = await _spawn({"player_control": Pond.PlayerControl.WASD, "predator_count": 0})
	_expect(_player(pond).control_mode == Creature.Mode.WASD and _player(pond).is_in_group("player"), "玩家控制方式 WASD")
	await _free(pond)

	# 食物會逃跑
	pond = await _spawn({"food_flees": true, "food_count": 1, "predator_count": 0})
	player = _player(pond)
	player.set_process(false)
	var food: Node2D = _any_food(pond)
	food.global_position = player.global_position + Vector2(100, 0)
	await get_tree().create_timer(0.3).timeout
	_expect(food.global_position.distance_to(player.global_position) > 120.0, "食物會逃跑：玩家靠近時躲開")
	await _free(pond)


func _test_bad_settings() -> void:
	print("--- 設定有問題 ---")
	var pond: Pond = await _spawn({"player_creature": null})
	var message: Label = pond.get_node("%MessageLabel")
	_expect(message.visible and "還沒有設定玩家生物" in message.text, "沒有玩家生物：顯示提示")
	await _free(pond)

	var not_creature := PackedScene.new()
	var plain := Node2D.new()
	not_creature.pack(plain)
	plain.free()
	pond = await _spawn({"player_creature": not_creature, "predator_creature": not_creature})
	message = pond.get_node("%MessageLabel")
	_expect(message.visible and "不是 Creature" in message.text, "玩家生物的根節點不是 Creature：顯示提示")
	await get_tree().create_timer(0.2).timeout
	_expect(true, "不會當掉")
	await _free(pond)


# ---------------------------------------------------------------- 工具


## 建立池塘，props 是要改的規則屬性（在加進場景樹之前設定，跟在檢查器改一樣）
func _spawn(props: Dictionary) -> Pond:
	get_tree().paused = false
	var pond: Pond = POND_SCENE.instantiate()
	for key: String in props:
		pond.set(key, props[key])
	add_child(pond)
	await get_tree().process_frame
	return pond


## 記錄 game_over 的結果（true 贏、false 輸）
func _watch(pond: Pond) -> Array[bool]:
	var results: Array[bool] = []
	pond.game_over.connect(func(won: bool) -> void: results.append(won))
	return results


func _player(pond: Pond) -> Creature:
	return pond.get("_player")


func _any_food(pond: Pond) -> Node:
	return pond.get_node("%Foods").get_child(0)


func _status(pond: Pond) -> String:
	return (pond.get_node("%StatusLabel") as Label).text


func _result_visible(pond: Pond) -> bool:
	return (pond.get_node("%Result") as CanvasLayer).visible


func _free(pond: Pond) -> void:
	pond.queue_free()
	get_tree().paused = false
	await get_tree().process_frame


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
