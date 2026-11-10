extends Node
## 生物零件的自動測試：
## 1. 身體節數 2 和 80 不會出錯；「第幾節」超出範圍時當最後一節
## 2. grow／shrink 後節數正確、最少 2 節；短到剩 2 節時發出 died；新加的節接在尾巴後面
## 3. 頭快速繞圈：間距不變、相鄰兩節的彎曲不超過上限
## 4. reset_pose()：瞬間移動後身體重新拉直在頭後面
## 5. 沒有身體的生物：長度用等級換算，也能移動
## 6. 全身碰撞：每節都有碰撞區，長大後跟著增加
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/creature_parts_test.tscn

const CREATURE_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/creature.gd")
const BODY_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/chain_body.gd")
const FRAME: float = 1.0 / 60.0

var _failures: int = 0


func _ready() -> void:
	await _test_segment_range()
	await _test_grow_shrink()
	await _test_fast_turn()
	await _test_reset_pose()
	await _test_no_body()
	await _test_full_body_collision()

	if _failures == 0:
		print("[生物零件測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[生物零件測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_segment_range() -> void:
	print("--- 節數範圍 ---")
	for count: int in [2, 80]:
		var creature: Creature = await _spawn({"segment_count": count})
		var body: ChainBody = creature.get_body()
		_expect(body.joint_count() == count, "%d 節：joint_count() = %d" % [count, body.joint_count()])
		await _simulate(creature, 30, 0.0)
		_expect(body.get_joint(999) == body.get_joint(count - 1), "%d 節：第 999 節當最後一節" % count)
		_expect(body.get_joint(-1) == body.get_joint(count - 1), "%d 節：第 -1 節是最後一節" % count)
		await _free(creature)
	var body_low: ChainBody = BODY_SCRIPT.new()
	body_low.segment_count = 0
	_expect(body_low.segment_count == 2, "節數設成 0 會變成 2")
	body_low.free()


func _test_grow_shrink() -> void:
	print("--- 長大、變短 ---")
	var creature: Creature = await _spawn({"segment_count": 10, "segments_per_growth": 2})
	var body: ChainBody = creature.get_body()
	await _simulate(creature, 30, 0.0)
	var grew_levels: Array[int] = []
	creature.grew.connect(func(level: int) -> void: grew_levels.append(level))
	creature.grow(1)
	creature.grow(2)
	_expect(body.joint_count() == 16, "每次長 2 節，長大 3 次：10 → 16（實際 %d）" % body.joint_count())
	_expect(grew_levels == [1, 3], "grew 訊號帶著等級 1、3")
	var tail_gap: float = body.get_joint(-1).distance_to(body.get_joint(-2))
	_expect(is_equal_approx(tail_gap, body.spacing), "新的節接在尾巴後面，間距正確（%.2f）" % tail_gap)
	_expect(body.get_joint(-1).distance_to(Vector2.ZERO) > 100.0, "新的節不是從原點飛過來")

	var hurt_count: Array[int] = [0]
	var died_count: Array[int] = [0]
	creature.hurt.connect(func() -> void: hurt_count[0] += 1)
	creature.died.connect(func() -> void: died_count[0] += 1)
	creature.shrink(2)
	_expect(body.joint_count() == 12 and hurt_count[0] == 1 and died_count[0] == 0, "被咬 2：16 → 12，發出 hurt，沒有 died")
	creature.shrink(100)
	_expect(body.joint_count() == 2, "被咬很多下：最少留 2 節（實際 %d）" % body.joint_count())
	_expect(died_count[0] == 1, "剩 2 節時發出 died")
	await _simulate(creature, 10, 0.0)
	_expect(true, "剩 2 節繼續動不會出錯")
	await _free(creature)


func _test_fast_turn() -> void:
	print("--- 快速繞圈 ---")
	var max_bend: float = deg_to_rad(30.0)
	var creature: Creature = await _spawn({"segment_count": 30, "max_bend": max_bend})
	var body: ChainBody = creature.get_body()
	var worst_bend: float = 0.0
	var worst_gap: float = 0.0
	for frame: int in 240:
		await _simulate(creature, 1, deg_to_rad(720.0) if frame > 30 else 0.0)
		for i: int in range(1, body.joint_count()):
			worst_gap = maxf(worst_gap, absf(body._joints[i].distance_to(body._joints[i - 1]) - body.spacing))
			if i >= 2:
				var bend: float = absf(angle_difference((body._joints[i - 1] - body._joints[i - 2]).angle(), (body._joints[i] - body._joints[i - 1]).angle()))
				worst_bend = maxf(worst_bend, bend)
	_expect(worst_gap < 0.01, "間距一直保持（最大誤差 %.4f）" % worst_gap)
	_expect(worst_bend <= max_bend + 0.001, "相鄰兩節最多彎 %.1f 度（上限 30）" % rad_to_deg(worst_bend))
	await _free(creature)


func _test_reset_pose() -> void:
	print("--- reset_pose ---")
	var creature: Creature = await _spawn({})
	var body: ChainBody = creature.get_body()
	await _simulate(creature, 60, deg_to_rad(180.0))
	creature.global_position = Vector2(900, 500)
	creature.heading = PI / 2.0
	creature.reset_pose()
	var expected_tail: Vector2 = Vector2(900, 500) + Vector2.UP * body.spacing * (body.joint_count() - 1)
	_expect(body.get_joint(0).is_equal_approx(Vector2(900, 500)), "頭在新位置")
	_expect(body.get_joint(-1).distance_to(expected_tail) < 0.01, "身體拉直在頭的反方向（頭朝下，身體往上）")
	await _free(creature)


func _test_no_body() -> void:
	print("--- 沒有身體的生物 ---")
	var creature: Creature = CREATURE_SCRIPT.new()
	creature.position = Vector2(300, 300)
	add_child(creature)
	await get_tree().process_frame
	_expect(creature.get_length() == Creature.LENGTH_WITHOUT_BODY, "長度 = %d" % Creature.LENGTH_WITHOUT_BODY)
	creature.grow(3)
	_expect(creature.get_length() == Creature.LENGTH_WITHOUT_BODY + 3, "長大 3 次，長度 +3")
	creature.control_mode = Creature.Mode.WANDER
	var start: Vector2 = creature.global_position
	for i: int in 30:
		await get_tree().process_frame
	_expect(creature.global_position != start, "漫遊模式會移動")
	await _free(creature)


func _test_full_body_collision() -> void:
	print("--- 全身碰撞 ---")
	var creature: Creature = await _spawn({"segment_count": 8, "full_body_collision": true})
	creature.set_collision(2, 1)
	await _simulate(creature, 2, 0.0)
	var body: ChainBody = creature.get_body()
	_expect(body._hit_areas.size() == 7, "8 節：身體有 7 個碰撞區（頭另外算）")
	creature.grow(3)
	await _simulate(creature, 2, 0.0)
	_expect(body._hit_areas.size() == 10, "長大 3 節後有 10 個碰撞區")
	_expect(body._hit_areas[-1].collision_layer == 2, "新的碰撞區沿用頭的碰撞層")
	_expect(body._hit_areas[0].global_position.is_equal_approx(body.get_joint(1)), "碰撞區跟著關節走")
	await _free(creature)


## 建立一隻有身體的生物，body_props 是要設定給 ChainBody 的屬性
func _spawn(body_props: Dictionary) -> Creature:
	var creature: Creature = CREATURE_SCRIPT.new()
	creature.position = Vector2(640, 360)
	var body: ChainBody = BODY_SCRIPT.new()
	for key: String in body_props:
		body.set(key, body_props[key])
	creature.add_child(body)
	add_child(creature)
	await get_tree().process_frame
	# 改由測試自己移動，才能精準控制轉彎
	creature.set_process(false)
	body.set_process(false)
	return creature


## 手動跑 frames 幀：頭以 turn_rate（弧度／秒）轉彎、用 speed 往前走，再讓身體跟上
func _simulate(creature: Creature, frames: int, turn_rate: float) -> void:
	var body: ChainBody = creature.get_body()
	for i: int in frames:
		creature.heading += turn_rate * FRAME
		creature.velocity = Vector2.from_angle(creature.heading) * creature.speed
		creature.global_position += creature.velocity * FRAME
		if body != null:
			body._process(FRAME)
	await get_tree().process_frame


func _free(node: Node) -> void:
	node.queue_free()
	await get_tree().process_frame


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
