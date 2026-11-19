extends Node
## 平衡的自動測試（11/19 社課工坊看到的問題）：
## 1. 公式的上限（單人也有效）：身體長度、觸手長度、觸手實際抓得到的範圍、游動推進力、成長曲線、死掉掉多少飼料；
##    看得到的身體（太透明、不畫身體、太細）
## 2. 平衡檢查（BalanceCheck，多人時主機自動調整）：範例生物都不用調；
##    間距太稀、會抓食物的觸手太多，該調的會調、調完再檢查沒問題；
##    check() 不會改到原本的設計檔；壞掉、不完整的資料不會當掉
## 3. 對戰封包：主機調整封包裡的設計檔，沒問題的不動
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/balance_check_test.tscn

const EXAMPLES: PackedStringArray = ["snake", "centipede", "octopus", "spider", "jellyfish", "dragon", "doodle", "predator_eel", "sea_angel"]

var _failures: int = 0
var _balance: CreatureBalance


func _ready() -> void:
	_balance = CreatureBalance.get_default()
	_test_body_length()
	await _test_grab_reach()
	_test_swim()
	_test_cost_curve()
	_test_dropped_food()
	_test_examples_pass()
	_test_spacing()
	_test_visible()
	_test_tentacle_length()
	_test_grab_tentacles()
	_test_check_is_pure()
	_test_broken_data()
	_test_packet()

	if _failures == 0:
		print("[平衡測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[平衡測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


## 節數、間距拉滿的細長身體
func _long_snake() -> CreatureDesign:
	var design: CreatureDesign = _example("snake")
	design.body.segment_count = 80
	design.body.spacing = 60.0
	design.body.thickness = 2.0
	return design


func _test_body_length() -> void:
	print("--- 身體長度上限 ---")
	var design: CreatureDesign = _long_snake()
	var start: CreatureDesign = CreatureGrowth.shape_at(design, 0, _balance)
	_expect(CreatureGrowth.body_length(start.body) <= _balance.max_start_length + 0.5,
		"0 級最長 %.0f（%.0f）" % [_balance.max_start_length, CreatureGrowth.body_length(start.body)])
	var last: float = 0.0
	var grows: bool = true
	for level: int in [1, 5, 10, 20, 50]:
		var shape: CreatureDesign = CreatureGrowth.shape_at(design, level, _balance)
		var length: float = CreatureGrowth.body_length(shape.body)
		grows = grows and length >= last - 0.5 and length <= _balance.max_body_length + 0.5
		last = length
		var expected: float = clampf(CreatureGrowth.body_size(design.body), _balance.min_start_size, _balance.max_start_size) + _balance.size_per_level * level
		_expect(absf(CreatureGrowth.body_size(shape.body) - expected) < expected * 0.02, "%d 級：壓短之後體型不變（%.0f ≈ %.0f）" % [level, CreatureGrowth.body_size(shape.body), expected])
	_expect(grows, "長大時長度不會變短、不超過 %.0f（50 級 %.0f）" % [_balance.max_body_length, last])
	var normal: CreatureDesign = _example("snake")
	_expect(is_equal_approx(CreatureGrowth.shape_at(normal, 0, _balance).body.spacing, normal.body.spacing), "沒超過的不動（蛇的間距不變）")
	var long_turn: float = CreatureStats.at_level(design, 50, _balance).turn
	_expect(long_turn >= _balance.min_turn - 0.001, "轉向有下限 %.0f 度（50 級 %.0f）" % [rad_to_deg(_balance.min_turn), rad_to_deg(long_turn)])


func _test_grab_reach() -> void:
	print("--- 觸手實際抓得到的範圍 ---")
	var design: CreatureDesign = _example("octopus")
	for tentacle: TentacleDesign in design.tentacles:
		tentacle.length = 400.0
	var creature := Creature.new()
	creature.design = design
	add_child(creature)
	await get_tree().process_frame
	var reaches: Array[float] = []
	for node: Node in creature.find_children("*", "Tentacle", true, false):
		reaches.append((node as Tentacle).grab_reach())
	_expect(not reaches.is_empty() and reaches.max() <= _balance.max_grab, "觸手 400 長，抓得到的最遠 %.0f（%s）" % [_balance.max_grab, reaches])
	creature.set_level(20)
	await get_tree().process_frame
	reaches.clear()
	for node: Node in creature.find_children("*", "Tentacle", true, false):
		reaches.append((node as Tentacle).grab_reach())
	_expect(not reaches.is_empty() and reaches.max() <= _balance.max_grab, "長到 20 級也不超過 %.0f" % _balance.max_grab)
	creature.queue_free()
	var lone := Tentacle.new()
	_expect(is_equal_approx(lone.grab_reach(), lone.length), "沒有掛在生物上的觸手：照長度")
	lone.free()
	var many: CreatureDesign = _example("octopus")
	var few: CreatureDesign = _example("octopus")
	few.tentacles.resize(1)
	few.tentacles[0].side = CreaturePart.Side.CENTER
	_expect(CreatureStats.compute(many, _balance).base_cost > CreatureStats.compute(few, _balance).base_cost, "會抓食物的觸手越多條，升級越貴")


func _test_swim() -> void:
	print("--- 游動推進力上限 ---")
	var design: CreatureDesign = _example("snake")
	design.body.swim_amplitude = 40.0
	var huge: float = CreatureStats.compute(design, _balance).thrust
	_expect(huge <= _balance.base_thrust + _balance.max_swim_thrust + 0.01, "擺幅 40：推進力 %.0f 不超過基本＋上限 %.0f" % [huge, _balance.base_thrust + _balance.max_swim_thrust])
	design.body.swim_amplitude = 6.0
	_expect(is_equal_approx(CreatureStats.compute(design, _balance).thrust, _balance.base_thrust + 6.0 * _balance.thrust_per_swim), "擺幅小的照原本算")


func _test_cost_curve() -> void:
	print("--- 成長曲線 ---")
	var design: CreatureDesign = _example("snake")
	var costs: Array[int] = []
	for level: int in [0, 5, 10, 20]:
		costs.append(CreatureStats.at_level(design, level, _balance).level_cost)
	_expect(costs[0] < costs[1] and costs[1] < costs[2] and costs[2] < costs[3], "等級越高升級越貴：0／5／10／20 級 %s" % [costs])
	_expect(CreatureStats.cost_at(4.0, 0, _balance) == 4 and CreatureStats.cost_at(4.0, 4, _balance) == roundi(4.0 * (1.0 + 4 * _balance.cost_per_level)), "cost_at：基本 ×（1＋等級 × 係數）")
	_expect(CreatureStats.food_to_reach(4.0, 0, _balance) == 0 and CreatureStats.food_to_reach(4.0, 2, _balance) == CreatureStats.cost_at(4.0, 0, _balance) + CreatureStats.cost_at(4.0, 1, _balance), "food_to_reach：每一級加起來")
	_expect(CreatureStats.cost_at(0.0, 3, _balance) == 1, "成本最少 1")


func _test_dropped_food() -> void:
	print("--- 死掉掉多少飼料 ---")
	_expect(TankRules.dropped_food(0, 4.0, 0, _balance) == _balance.min_drop_food, "0 級：最少 %d 顆" % _balance.min_drop_food)
	var last: int = 0
	var ok: bool = true
	for level: int in 40:
		var count: int = TankRules.dropped_food(level, 4.0, 0, _balance)
		ok = ok and count >= last and count <= _balance.max_drop_food
		last = count
	_expect(ok, "等級越高掉越多、不超過 %d 顆" % _balance.max_drop_food)
	# 撞倒一隻 10 級的，自己（也是 10 級）升幾級：不能一口氣升好幾級
	var value: int = TankRules.dropped_food(10, 4.0, 0, _balance) * _balance.big_food_value
	var levels: int = 0
	var left: int = value
	while left >= CreatureStats.cost_at(4.0, 10 + levels, _balance):
		left -= CreatureStats.cost_at(4.0, 10 + levels, _balance)
		levels += 1
	_expect(levels <= 4, "撞倒同樣 10 級的：拿到 %d 個，升 %d 級（原本約 16 級）" % [value, levels])
	_expect(TankRules.dropped_food(5, 4.0, 3, _balance) >= TankRules.dropped_food(5, 4.0, 0, _balance), "吃到一半的也算")


func _test_examples_pass() -> void:
	print("--- 範例生物都不用調 ---")
	for example: String in EXAMPLES:
		var notes: PackedStringArray = BalanceCheck.check(_example(example), _balance)
		_expect(notes.is_empty(), "%s：%s" % [example, "沒問題" if notes.is_empty() else str(notes)])


func _test_spacing() -> void:
	print("--- 間距太稀 ---")
	var design: CreatureDesign = _long_snake()
	var area: float = design.body.spacing * design.body.thickness
	var notes: PackedStringArray = BalanceCheck.fix(design, _balance)
	_expect(notes.size() == 1, "調了 1 項：%s" % [notes])
	_expect(design.body.spacing <= design.body.thickness * _balance.max_spacing_ratio, "調完：間距 %.0f ≤ 粗細 %.0f × %.1f" % [design.body.spacing, design.body.thickness, _balance.max_spacing_ratio])
	_expect(absf(design.body.spacing * design.body.thickness - area) < area * 0.3, "間距 × 粗細差不多（%.0f → %.0f），還是細細長長" % [area, design.body.spacing * design.body.thickness])
	_expect(BalanceCheck.check(_reload(design), _balance).is_empty(), "調完（傳到別台電腦）再檢查沒問題")
	var edge: CreatureDesign = _example("snake")
	edge.body.thickness = 2.0
	edge.body.spacing = 5.0
	BalanceCheck.fix(edge, _balance)
	_expect(edge.body.spacing >= 4.0 and BalanceCheck.check(_reload(edge), _balance).is_empty(), "很細的身體：間距不會小於 4，調完沒問題（間距 %.0f、粗細 %.0f）" % [edge.body.spacing, edge.body.thickness])


func _test_visible() -> void:
	print("--- 看得到的身體（單人也有效）---")
	var design: CreatureDesign = _example("dragon")
	var colors: PackedColorArray = design.body.body_gradient.colors
	for i: int in colors.size():
		colors[i].a = 0.05
	design.body.body_gradient.colors = colors
	var shape: CreatureDesign = CreatureGrowth.shape_at(design, 0, _balance)
	var lowest: float = 1.0
	for color: Color in shape.body.body_gradient.colors:
		lowest = minf(lowest, color.a)
	_expect(lowest >= _balance.min_body_alpha - 0.001, "太透明：遊戲裡的不透明度至少 %.0f%%（%.0f%%）" % [_balance.min_body_alpha * 100.0, lowest * 100.0])
	_expect(is_equal_approx(design.body.body_gradient.colors[0].a, 0.05), "設計檔本身沒被改到")
	_expect(CreatureGrowth.visibility_notes(design, _balance).size() == 1, "工坊會顯示 1 項調整")
	var hidden: CreatureDesign = _example("snake")
	hidden.body.draw_body = false
	_expect(CreatureGrowth.shape_at(hidden, 0, _balance).body.draw_body, "不畫身體又沒有每一節的圖：遊戲裡還是畫身體")
	var beads: CreatureDesign = _example("snake")
	beads.body.draw_body = false
	beads.body.segment_image = "bead.png"
	_expect(CreatureGrowth.visibility_notes(beads, _balance).is_empty(), "有每一節的圖（一串珠子）：不用畫身體")
	var thin: CreatureDesign = _example("snake")
	thin.body.thickness = 2.0
	var thin_shape: CreatureDesign = CreatureGrowth.shape_at(thin, 0, _balance)
	var body: BodyDesign = thin_shape.body
	var width: float = CreatureGrowth.body_size(body) / (2.0 * body.spacing * body.segment_count)
	_expect(width >= _balance.min_body_width - 0.01, "太細：平均寬至少 %.1f（%.1f）" % [_balance.min_body_width, width])
	var expected: float = clampf(CreatureGrowth.body_size(thin.body), _balance.min_start_size, _balance.max_start_size)
	_expect(absf(CreatureGrowth.body_size(body) - expected) < expected * 0.02, "加粗之後體型不變（%.0f ≈ %.0f）" % [CreatureGrowth.body_size(body), expected])
	for example: String in EXAMPLES:
		var notes: PackedStringArray = CreatureGrowth.visibility_notes(_example(example), _balance)
		_expect(notes.is_empty(), "%s 不用調：%s" % [example, "沒問題" if notes.is_empty() else str(notes)])
	CreatureGrowth.visibility_notes(null, _balance)
	CreatureGrowth.visibility_notes(CreatureDesign.from_data({"body": {"thickness": -5, "body_gradient": "亂寫"}}), _balance)
	_expect(true, "壞掉的資料不會當掉")


func _test_tentacle_length() -> void:
	print("--- 觸手長度上限 ---")
	var design: CreatureDesign = _example("octopus")
	design.body.segment_count = 2
	design.body.thickness = 8.0
	for tentacle: TentacleDesign in design.tentacles:
		tentacle.length = 400.0
	for mode: int in 3:
		design.growth_mode = mode
		var start: float = _longest(CreatureGrowth.shape_at(design, 0, _balance))
		var grown: float = _longest(CreatureGrowth.shape_at(design, 50, _balance))
		_expect(start <= _balance.max_start_tentacle + 0.5 and grown <= _balance.max_tentacle_length + 0.5,
			"長大方式 %d：小身體＋長觸手，0 級 %.0f、50 級 %.0f（最長 %.0f／%.0f）" % [mode, start, grown, _balance.max_start_tentacle, _balance.max_tentacle_length])
	var jelly: CreatureDesign = _example("jellyfish")
	_expect(_longest(CreatureGrowth.shape_at(jelly, 20, _balance)) > _longest(CreatureGrowth.shape_at(jelly, 0, _balance)), "範例的觸手還是會跟著長大")


func _longest(shape: CreatureDesign) -> float:
	var longest: float = 0.0
	for tentacle: TentacleDesign in shape.tentacles:
		longest = maxf(longest, tentacle.length)
	return longest


func _test_grab_tentacles() -> void:
	print("--- 會抓食物的觸手太多 ---")
	var design: CreatureDesign = _example("octopus")
	while design.tentacles.size() < CreatureDesign.MAX_TENTACLES:
		design.tentacles.append(design.tentacles[0].duplicate() as TentacleDesign)
	design.tentacles[0].length = 300.0
	var notes: PackedStringArray = BalanceCheck.fix(design, _balance)
	var count: int = 0
	for tentacle: TentacleDesign in design.tentacles:
		if tentacle.behavior == Tentacle.Behavior.GRAB_FOOD:
			count += 2 if tentacle.side == CreaturePart.Side.BOTH else 1
	_expect(notes.size() == 1 and count <= _balance.max_grab_tentacles and count > 0, "剩 %d 條會抓（最多 %d）" % [count, _balance.max_grab_tentacles])
	_expect(design.tentacles[0].behavior == Tentacle.Behavior.GRAB_FOOD, "最長的那組留著抓食物")
	_expect(BalanceCheck.check(_reload(design), _balance).is_empty(), "調完再檢查沒問題")


func _test_check_is_pure() -> void:
	print("--- check() 不會改到設計檔 ---")
	var design: CreatureDesign = _long_snake()
	design.body.draw_body = false
	var before: Dictionary = design.to_dict()
	var notes: PackedStringArray = BalanceCheck.check(design, _balance)
	_expect(notes.size() == 1 and design.to_dict() == before, "檢查出 %d 項，設計檔沒變" % notes.size())


func _test_broken_data() -> void:
	print("--- 壞掉的資料不會當掉 ---")
	_expect(BalanceCheck.check(null, _balance).is_empty() and BalanceCheck.fix(null, _balance).is_empty(), "null")
	var empty: CreatureDesign = CreatureDesign.from_data({})
	BalanceCheck.check(empty, _balance)
	_expect(true, "空的資料")
	var no_gradient: CreatureDesign = _example("snake")
	no_gradient.body.body_gradient = null
	BalanceCheck.fix(no_gradient, _balance)
	CreatureGrowth.shape_at(no_gradient, 3, _balance)
	_expect(true, "沒有漸層")
	var weird: CreatureDesign = CreatureDesign.from_data({"body": {"spacing": "很多", "thickness": -5}, "tentacles": [{"behavior": 99}, "亂寫"]})
	BalanceCheck.fix(weird, _balance)
	_expect(BalanceCheck.check(_reload(weird), _balance).is_empty(), "亂寫的資料：from_dict() 夾完，調完沒問題")
	_expect(BattlePacket.balance_packet({}, _balance).is_empty() and BattlePacket.balance_packet({"design": "不是字典"}, _balance).is_empty(), "封包沒有設計檔")


func _test_packet() -> void:
	print("--- 對戰封包 ---")
	var packet: Dictionary = BattlePacket.build("測試", _long_snake(), {})
	var notes: PackedStringArray = BattlePacket.balance_packet(packet, _balance)
	_expect(not notes.is_empty() and BalanceCheck.check(CreatureDesign.from_data(packet.design), _balance).is_empty(), "主機調整封包裡的設計檔（%d 項）" % notes.size())
	_expect(BattlePacket.check(packet, _balance) == "", "調完的封包還是合格")
	var fine: Dictionary = BattlePacket.build("測試", _example("snake"), {})
	var before: Dictionary = fine.design.duplicate(true)
	_expect(BattlePacket.balance_packet(fine, _balance).is_empty() and fine.design == before, "沒問題的不動")


## 範例設計檔（複製一份，不會改到檔案）
func _example(example: String) -> CreatureDesign:
	return CreatureDesign.from_data((load("res://example/creatures/%s/design.tres" % example) as CreatureDesign).to_dict())


## 像傳到別台電腦一樣：轉成資料再讀回來（from_dict() 會把數字夾回範圍）
func _reload(design: CreatureDesign) -> CreatureDesign:
	return CreatureDesign.from_data(design.to_dict())


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
