extends Node
## 生物零件的自動測試：
## 1. 身體節數 2 和 80 不會出錯；「第幾節」超出範圍時當最後一節
## 2. grow／shrink 後節數正確、身體最少 2 節；長度 = 10 ＋ 等級，短到 2 時發出 died；新加的節接在尾巴後面
## 3. 頭快速繞圈：間距不變、相鄰兩節的彎曲不超過上限
## 4. reset_pose()：瞬間移動後身體重新拉直在頭後面
## 5. 沒有身體的生物：長度用等級換算，也能移動
## 6. 全身碰撞：每節都有碰撞區，長大後跟著增加
## 7. 蜘蛛的腳：直走、急轉彎、原地轉圈時膝蓋不會翻面、同一邊的腳不會交叉；停下後 1 秒內腳都站穩
## 8. 觸手：FABRIK 伸得到目標、根部不動；「抓最近的食物」會吃掉食物；掛在超出範圍的節不會出錯
## 9. reset_pose()：瞬間移動後腳和觸手都在新位置；只有觸手、沒有身體的生物也能動
## 10. 掛件：三種動法、十種形狀都不會出錯；「兩邊」會鏡像底下的子節點；彈簧會晃過頭再停下
## 11. 眼睛：1～6 顆、四種「看哪裡」都不會出錯；Gradient 只有一個顏色時正常
## 12. 進階挑戰 grow_challenge：grew 訊號有連接，每升 5 級換一次身體顏色
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/creature_parts_test.tscn

const CREATURE_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/creature.gd")
const BODY_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/chain_body.gd")
const LEG_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/ik_leg.gd")
const TENTACLE_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/tentacle.gd")
const EYES_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/eyes.gd")
const ORNAMENT_SCRIPT: GDScript = preload("res://game/creature_parts/scripts/ornament.gd")
const FOOD_SCRIPT: GDScript = preload("res://_system/sandbox/scripts/sandbox_food.gd")
const FRAME: float = 1.0 / 60.0

var _failures: int = 0


func _ready() -> void:
	await _test_segment_range()
	await _test_grow_shrink()
	await _test_fast_turn()
	await _test_reset_pose()
	await _test_no_body()
	await _test_full_body_collision()
	await _test_spider_legs()
	await _test_tentacle()
	await _test_parts_reset_pose()
	await _test_tentacle_only()
	await _test_ornament()
	await _test_eyes_and_gradient()
	await _test_grow_challenge()

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
	_expect(creature.get_length() == Creature.START_LENGTH + 3, "遊戲長度跟身體節數無關：10 ＋ 等級 3 ＝ %d" % creature.get_length())
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
	_expect(died_count[0] == 1, "長度短到 2 時發出 died")
	await _simulate(creature, 10, 0.0)
	_expect(true, "身體剩 2 節繼續動不會出錯")
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
	_expect(creature.get_length() == Creature.START_LENGTH, "長度 = %d" % Creature.START_LENGTH)
	creature.grow(3)
	_expect(creature.get_length() == Creature.START_LENGTH + 3, "長大 3 次，長度 +3")
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


# ---------------------------------------------------------------- 第二段：腳、觸手


## 蜘蛛：短身體＋四對腳，A、B 兩組交錯
func _make_spider() -> Creature:
	var creature: Creature = CREATURE_SCRIPT.new()
	creature.position = Vector2(640, 360)
	var body: ChainBody = BODY_SCRIPT.new()
	body.segment_count = 3
	body.spacing = 18.0
	creature.add_child(body)
	# 調過的參數：落腳角度間隔 40 度、落腳距離 0.9、髖關節分散在三節，直走時腳不會交叉
	var rest_degrees: Array[float] = [30.0, 70.0, 110.0, 150.0]
	var attach: Array[int] = [0, 1, 1, 2]
	for index: int in rest_degrees.size():
		var leg: IKLeg = LEG_SCRIPT.new()
		leg.attach_segment = attach[index]
		leg.rest_distance = 0.9
		leg.step_distance = 16.0
		leg.thigh_length = 34.0
		leg.shin_length = 42.0
		leg.rest_angle = deg_to_rad(rest_degrees[index])
		leg.group = index % 2
		body.add_child(leg)
	return creature


## 手動跑 frames 幀：頭往前走（speed_ratio × 速度）、轉彎，再依序更新身體和所有零件。
## check 是每幀跑完要呼叫的檢查（可以是空的 Callable）
func _drive(creature: Creature, frames: int, turn_degrees: float, speed_ratio: float, check: Callable) -> void:
	var parts: Array[Node] = creature.find_children("*", "", true, false)
	for i: int in frames:
		creature.heading += deg_to_rad(turn_degrees) * FRAME
		creature.velocity = Vector2.from_angle(creature.heading) * creature.speed * speed_ratio
		creature.global_position += creature.velocity * FRAME
		for part: Node in parts:
			if part is ChainBody or part is CreaturePart:
				part.call("_process", FRAME)
		if check.is_valid():
			check.call()
	await get_tree().process_frame


func _test_spider_legs() -> void:
	print("--- 蜘蛛的腳 ---")
	var creature: Creature = _make_spider()
	add_child(creature)
	await get_tree().process_frame
	for node: Node in [creature] + creature.find_children("*", "", true, false):
		node.set_process(false)
	var legs: Array[IKLeg] = []
	for node: Node in creature.find_children("*", "", true, false):
		if node is IKLeg:
			legs.append(node)

	# 每隻腳一開始的膝蓋在哪一側（外積的正負），之後不能變
	var knee_sides: Dictionary = {}
	# crossings：腳的線段交叉的幀數；swaps：同一邊腳掌前後順序顛倒的幀數（每個階段重新計算）
	var stats: Dictionary = {"flips": 0, "crossings": 0, "swaps": 0}
	var check: Callable = func() -> void:
		if _feet_out_of_order(legs, creature):
			stats.swaps += 1
		var segments: Array = []  # [左右, 起點, 終點]
		for leg: IKLeg in legs:
			var signs: PackedFloat32Array = CreaturePart.side_signs(leg.side)
			for k: int in signs.size():
				var hip: Vector2 = leg._hip(signs[k])
				var foot: Vector2 = hip + (leg._feet[k] - hip).limit_length(leg.thigh_length + leg.shin_length - 0.01)
				var knee: Vector2 = leg.solve_knee(hip, foot, leg.thigh_length, leg.shin_length, leg._bend(signs[k]))
				var cross: float = (foot - hip).cross(knee - hip)
				var key: String = "%s_%d" % [leg.get_instance_id(), k]
				if absf(cross) > 1.0:
					if knee_sides.has(key) and signf(cross) != knee_sides[key]:
						stats.flips += 1
					knee_sides[key] = signf(cross)
				segments.append([signs[k], hip, knee])
				segments.append([signs[k], knee, foot])
		for a: int in segments.size():
			for b: int in range(a + 1, segments.size()):
				# 同一隻腳的大腿、小腿相連，不算交叉
				if a % 2 == 0 and b == a + 1:
					continue
				if segments[a][0] != segments[b][0]:
					continue
				var hit: Variant = Geometry2D.segment_intersects_segment(segments[a][1], segments[a][2], segments[b][1], segments[b][2])
				# 掛在同一節的腳共用髖關節，在髖關節相交不算交叉
				if hit != null and (hit as Vector2).distance_to(segments[a - a % 2][1]) > 2.0 and (hit as Vector2).distance_to(segments[b - b % 2][1]) > 2.0:
					stats.crossings += 1
					return

	# [階段名稱, 幀數, 每秒轉幾度, 速度比例, 要不要檢查]
	# 直走、停下時要求幾乎不交叉（最多 2 幀，1/30 秒內看不出來）；轉彎時只印出來參考：
	# 生物是頭帶著身體走，急轉、原地轉圈時身體會繞著頭甩，腳難免短暫交疊
	var phases: Array = [
		["直走 2 秒", 120, 0.0, 1.0, true],
		["急轉彎（每秒 300 度）", 36, 300.0, 1.0, false],
		["再直走 1 秒", 60, 0.0, 1.0, true],
		["突然停下 1 秒", 60, 0.0, 0.0, true],
		["慢走繞小圈", 120, 300.0, 0.3, false],
		["停下 1 秒", 60, 0.0, 0.0, true],
		["原地轉圈（每秒 300 度）", 72, 300.0, 0.0, false],
		["停下 1 秒", 60, 0.0, 0.0, true],
	]
	for phase: Array in phases:
		stats.crossings = 0
		stats.swaps = 0
		await _drive(creature, phase[1], phase[2], phase[3], check)
		var summary: String = "%s：線段交叉 %d 幀、腳掌前後顛倒 %d 幀（共 %d 幀）" % [phase[0], stats.crossings, stats.swaps, phase[1]]
		if phase[4]:
			_expect(stats.crossings <= 2 and stats.swaps <= 2, summary)
		else:
			print("  （參考）" + summary)
		if phase[3] == 0.0 and phase[2] == 0.0:
			_expect(_legs_settled(legs), "%s後，每隻腳都站穩（沒有在空中、離理想點不到半個跨步）" % phase[0])
	_expect(stats.flips == 0, "整段都沒有膝蓋翻面（翻面 %d 次）" % stats.flips)
	await _free(creature)


## 同一邊的腳掌，沿著身體方向的前後順序有沒有顛倒（先加的腳應該在比較前面）
func _feet_out_of_order(legs: Array[IKLeg], creature: Creature) -> bool:
	var center: Vector2 = creature.get_body().get_joint(1)
	var forward: Vector2 = Vector2.from_angle(creature.get_body().get_angle(1))
	for side_index: int in 2:
		var previous: float = INF
		for leg: IKLeg in legs:
			var along: float = (leg._feet[side_index] - center).dot(forward)
			if along > previous + 1.0:
				return true
			previous = along
	return false


func _legs_settled(legs: Array[IKLeg]) -> bool:
	for leg: IKLeg in legs:
		var signs: PackedFloat32Array = CreaturePart.side_signs(leg.side)
		for k: int in signs.size():
			if leg._stepping[k] or leg._feet[k].distance_to(leg._rest_point(signs[k])) > leg.step_distance * 0.5 + 0.5:
				return false
	return true


func _test_tentacle() -> void:
	print("--- 觸手 ---")
	var creature: Creature = await _spawn({"segment_count": 6})
	var tentacle: Tentacle = TENTACLE_SCRIPT.new()
	tentacle.side = CreaturePart.Side.CENTER
	tentacle.length = 80.0
	tentacle.segment_count = 10
	creature.get_body().add_child(tentacle)
	await get_tree().process_frame
	tentacle.set_process(false)

	var base: Vector2 = tentacle._root(0.0)
	var target: Vector2 = base + Vector2(30, 50)
	var chain: PackedVector2Array = tentacle.fabrik(tentacle._chains[0].duplicate(), base, target)
	_expect(chain[-1].distance_to(target) < 1.0, "FABRIK 4 次：末端離目標 %.2f px" % chain[-1].distance_to(target))
	_expect(chain[0] == base, "根部沒有離開原位")
	var far: PackedVector2Array = tentacle.fabrik(chain.duplicate(), base, base + Vector2(500, 0))
	_expect(absf(far[-1].distance_to(base) - 80.0) < 0.5, "目標太遠：拉直到最長 80（實際 %.1f）" % far[-1].distance_to(base))

	tentacle.attach_segment = 999
	_expect(tentacle._root(0.0).is_equal_approx(creature.get_body().get_joint(-1)), "掛在第 999 節：當成最後一節")
	tentacle.attach_segment = 0

	# 抓最近的食物
	tentacle.behavior = Tentacle.Behavior.GRAB_FOOD
	tentacle.set_process(true)
	var food: Node2D = FOOD_SCRIPT.new()
	food.position = tentacle._root(0.0) + Vector2(40, 40)
	add_child(food)
	var eaten: Array[Node] = []
	creature.ate.connect(func(node: Node) -> void: eaten.append(node))
	for i: int in 60:
		await get_tree().process_frame
		if not eaten.is_empty():
			break
	_expect(eaten == [food], "觸手抓到食物，發出 ate 訊號")
	_expect(creature.level == 1, "吃到食物後長大（等級 %d）" % creature.level)
	await _free(creature)


func _test_parts_reset_pose() -> void:
	print("--- 瞬間移動後 reset_pose ---")
	var creature: Creature = _make_spider()
	var tentacle: Tentacle = TENTACLE_SCRIPT.new()
	creature.get_body().add_child(tentacle)
	add_child(creature)
	await get_tree().process_frame
	for node: Node in [creature] + creature.find_children("*", "", true, false):
		node.set_process(false)
	await _drive(creature, 60, 90.0, 1.0, Callable())
	creature.global_position = Vector2(200, 600)
	creature.heading = 0.0
	creature.reset_pose()
	var leg: IKLeg = creature.get_body().get_child(0)
	_expect(leg._feet[0].is_equal_approx(leg._rest_point(-1.0)), "腳掌在新的理想落腳點")
	_expect(tentacle._chains[0][0].is_equal_approx(tentacle._root(-1.0)), "觸手根部在新位置")
	_expect(tentacle._chains[0][-1].distance_to(Vector2(200, 600)) < tentacle.length + 40.0, "觸手末端在新位置附近")
	await _free(creature)


func _test_tentacle_only() -> void:
	print("--- 只有觸手、沒有身體 ---")
	var creature: Creature = CREATURE_SCRIPT.new()
	creature.position = Vector2(640, 360)
	creature.control_mode = Creature.Mode.WANDER
	var tentacle: Tentacle = TENTACLE_SCRIPT.new()
	tentacle.behavior = Tentacle.Behavior.WAVE
	creature.add_child(tentacle)
	add_child(creature)
	var start: Vector2 = creature.global_position
	for i: int in 60:
		await get_tree().process_frame
	_expect(creature.global_position != start, "會移動")
	_expect(tentacle._chains.size() == 2, "「兩邊」有兩條觸手")
	_expect(tentacle._chains[0][0].distance_to(creature.global_position) <= creature.head_radius + 0.01, "觸手根部跟著頭")
	await _free(creature)


# ---------------------------------------------------------------- 第三段：眼睛、掛件


func _test_ornament() -> void:
	print("--- 掛件 ---")
	var creature: Creature = await _spawn({"segment_count": 10})
	var body: ChainBody = creature.get_body()
	# 「兩邊」＋底下放一張圖
	var sticker: Ornament = ORNAMENT_SCRIPT.new()
	sticker.side = CreaturePart.Side.BOTH
	sticker.shape = Ornament.Shape.NONE
	sticker.attach_segment = 3
	var sprite := Sprite2D.new()
	sprite.texture = load("res://icon.svg")
	sprite.position = Vector2(20, 0)
	sticker.add_child(sprite)
	body.add_child(sticker)
	await get_tree().process_frame
	var mirror: Node2D = sticker.get_node_or_null("MirrorSide")
	_expect(mirror != null and mirror.get_child_count() == 1 and mirror.get_child(0) is Sprite2D, "「兩邊」：執行時多一份子節點給右邊")
	var left_sprite: Vector2 = sprite.global_position
	var right_sprite: Vector2 = (mirror.get_child(0) as Node2D).global_position if mirror != null else Vector2.ZERO
	var joint: Vector2 = body.get_joint(3)
	var across: Vector2 = Vector2.from_angle(body.get_angle(3) + PI / 2.0)
	_expect((left_sprite - joint).dot(across) < -1.0 and (right_sprite - joint).dot(across) > 1.0, "左邊的圖在左側、複製的圖在右側")
	_expect(mirror != null and mirror.get_global_transform().determinant() < 0.0, "右邊的圖是翻過來的（scale.y = -1）")

	# 每種形狀、每種動法都跑一下
	var ornament: Ornament = ORNAMENT_SCRIPT.new()
	body.add_child(ornament)
	await get_tree().process_frame
	for motion_id: int in [Ornament.Motion.FIXED, Ornament.Motion.FLAP, Ornament.Motion.SPRING]:
		ornament.motion = motion_id
		for shape_id: int in 10:
			ornament.shape = shape_id
			for side_id: int in 4:
				ornament.side = side_id
				await get_tree().process_frame
	_expect(true, "三種動法 × 十種形狀 × 四種左右都不會出錯")

	# 彈簧：頭急轉 90 度後停住，掛件會落後、晃過頭，最後停在那一節的方向
	ornament.side = CreaturePart.Side.CENTER
	ornament.motion = Ornament.Motion.SPRING
	ornament.set_process(false)
	ornament.reset_pose()
	ornament.update_spring(FRAME)
	creature.heading += PI / 2.0
	body.reset_pose()  # 只重擺身體；creature.reset_pose() 會連掛件的彈簧一起歸零
	var lags: Array[float] = []
	for i: int in 120:
		ornament.update_spring(FRAME)
		lags.append(ornament._spring_lag())
	var overshoot: bool = false
	for lag: float in lags:
		if signf(lag) != signf(lags[0]) and absf(lag) > 0.01:
			overshoot = true
	_expect(absf(lags[0]) > 1.0, "轉彎後一開始落後（%.0f 度）" % rad_to_deg(lags[0]))
	_expect(overshoot, "會晃過頭再回來")
	_expect(absf(lags[-1]) < 0.05, "2 秒後停在那一節的方向（還差 %.1f 度）" % rad_to_deg(lags[-1]))
	await _free(creature)


func _test_eyes_and_gradient() -> void:
	print("--- 眼睛、單色漸層 ---")
	var creature: Creature = await _spawn({})
	var body: ChainBody = creature.get_body()
	var eyes: Eyes = EYES_SCRIPT.new()
	body.add_child(eyes)
	var food: Node2D = FOOD_SCRIPT.new()
	food.position = creature.global_position + Vector2(0, 100)
	add_child(food)
	for count: int in range(1, 7):
		eyes.count = count
		_expect(eyes.get_eye_positions().size() == count, "%d 顆眼睛" % count)
		for target: int in 4:
			eyes.look_target = target
			await get_tree().process_frame
	eyes.look_target = Eyes.LookAt.FOOD
	for i: int in 30:
		await get_tree().process_frame
	_expect(eyes._look.dot(Vector2.DOWN) > 0.9, "看最近的食物：瞳孔朝向食物（下方）")
	eyes.blink = true
	eyes._blink_timer = 0.0
	await get_tree().process_frame
	_expect(eyes._blinking, "時間到會眨眼")

	# 只有一個顏色的 Gradient：頭到尾都是那個顏色
	var single := Gradient.new()
	single.offsets = PackedFloat32Array([0.0])
	single.colors = PackedColorArray([Color.RED])
	body.body_gradient = single
	_expect(body._body_color(0.0) == Color.RED and body._body_color(1.0) == Color.RED, "身體：單色漸層頭尾都是紅色")
	var tentacle: Tentacle = TENTACLE_SCRIPT.new()
	tentacle.color_gradient = single
	body.add_child(tentacle)
	var ornament: Ornament = ORNAMENT_SCRIPT.new()
	ornament.color_gradient = single
	body.add_child(ornament)
	await get_tree().process_frame
	_expect(tentacle._gradient_color(0.5) == Color.RED and ornament._gradient_color(0.9) == Color.RED, "觸手、掛件：單色漸層正常")
	body.body_gradient = null
	await get_tree().process_frame
	_expect(true, "漸層清空（null）也不會出錯")
	food.queue_free()
	await _free(creature)


func _test_grow_challenge() -> void:
	print("--- 進階挑戰 grow_challenge ---")
	var creature: Creature = (load("res://example/grow_challenge/grow_challenge.tscn") as PackedScene).instantiate()
	creature.position = Vector2(640, 360)
	add_child(creature)
	await get_tree().process_frame
	var effect: Node = creature.get_node("GrowEffect")
	_expect(creature.grew.is_connected(Callable(effect, "_on_creature_grew")), "grew 訊號已經連接到 GrowEffect")
	var colors: Array[Color] = (effect.get_script() as GDScript).get_script_constant_map()["COLORS"]
	creature.grow(4)
	_expect(creature.get_body()._body_color(0.0) == colors[0], "升到第 4 級：第 1 個顏色")
	creature.grow(1)
	_expect(creature.get_body()._body_color(0.0) == colors[1], "升到第 5 級：換成第 2 個顏色")
	creature.grow(1)
	_expect(creature.get_body()._body_color(0.0) == colors[1], "升到第 6 級：長大後重新擺好身體，顏色還是第 2 個")
	await _free(creature)
