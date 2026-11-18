extends Node
## 長大方式、能力計算、平衡資料的自動測試：
## 1. 三種長大方式：每升一級體型增加一樣多（升 1～10 級都比對）
## 2. 一開始的體型夾在上下限之間：太大的縮小、太小的放大
## 3. ① 等比放大節數不變、長度變大；② 每隔幾節長一對腳、A／B 組交錯；③ 腳數不變
## 4. 節數到上限後改成等比放大，體型還是對的
## 5. shape_at() 不會改到原本的設計檔
## 6. 生物升級：身體照長大方式變；長出新腳要重長時，身體維持原本的姿勢
## 7. 能力：腳多跑得快、越大越慢、越長越難轉、觸手長抓得遠、眼睛多看得遠；都有上限；能力越強升級越貴
## 8. 平衡資料檔讀得到，星星 1～5
## 9. 複雜度：範例都在上限內；長大不會超過上限（到上限改成整隻放大）；零件越多升級越貴，掛件不算成本
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/creature_growth_test.tscn

const EXAMPLES: String = "res://example/creatures/"

var _failures: int = 0
var _balance: CreatureBalance


func _ready() -> void:
	_balance = CreatureBalance.get_default()
	_test_equal_growth()
	_test_start_size()
	_test_modes()
	_test_segment_cap()
	_test_original_untouched()
	await _test_creature_grow()
	_test_stats()
	_test_balance_file()
	_test_complexity()

	if _failures == 0:
		print("[長大與能力測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[長大與能力測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_equal_growth() -> void:
	print("--- 每升一級體型增加一樣多 ---")
	for example: String in ["snake", "centipede", "spider", "dragon"]:
		for mode: int in 3:
			var design: CreatureDesign = _example(example)
			design.growth_mode = mode
			var start: float = _size(design, 0)
			var worst: float = 0.0
			for level: int in range(1, 11):
				var expected: float = start + _balance.size_per_level * level
				worst = maxf(worst, absf(_size(design, level) - expected) / expected)
			_expect(worst < 0.001, "%s 長大方式 %d：升 1～10 級，體型誤差最多 %.3f%%" % [example, mode + 1, worst * 100.0])


func _test_start_size() -> void:
	print("--- 一開始的體型夾在上下限之間 ---")
	var huge: CreatureDesign = _example("predator_eel")
	huge.body.thickness = 60.0
	_expect(is_equal_approx(_size(huge, 0), _balance.max_start_size), "太大：縮到上限 %.0f（實際 %.0f）" % [_balance.max_start_size, _size(huge, 0)])
	var tiny: CreatureDesign = _example("jellyfish")
	tiny.body.thickness = 5.0
	_expect(is_equal_approx(_size(tiny, 0), _balance.min_start_size), "太小：放大到下限 %.0f（實際 %.0f）" % [_balance.min_start_size, _size(tiny, 0)])
	var normal: CreatureDesign = _example("snake")
	_expect(is_equal_approx(_size(normal, 0), CreatureGrowth.body_size(normal.body)), "在範圍內：不縮放")


func _test_modes() -> void:
	print("--- 三種長大方式長在哪裡 ---")
	var design: CreatureDesign = _example("dragon")
	design.growth_mode = CreatureDesign.Growth.SCALE
	var scaled: CreatureDesign = CreatureGrowth.shape_at(design, 5, _balance)
	_expect(scaled.body.segment_count == design.body.segment_count and scaled.legs.size() == design.legs.size(), "① 等比放大：節數、腳數不變")
	_expect(scaled.body.spacing > design.body.spacing and scaled.legs[0].thigh_length > design.legs[0].thigh_length and scaled.ornaments[0].size > design.ornaments[0].size, "① 等比放大：間距、腳長、掛件都變大")

	design.growth_mode = CreatureDesign.Growth.LONGER
	var longer: CreatureDesign = CreatureGrowth.shape_at(design, 5, _balance)
	_expect(longer.body.segment_count > design.body.segment_count and longer.legs.size() == design.legs.size(), "③ 只變長：節數 %d → %d，腳數不變" % [design.body.segment_count, longer.body.segment_count])
	_expect(is_equal_approx(longer.body.spacing, design.body.spacing), "③ 只變長：間距不變")

	design.growth_mode = CreatureDesign.Growth.LONGER_WITH_LEGS
	design.legs_every = 3
	_expect(CreatureGrowth.shape_at(design, 0, _balance).legs.size() == design.legs.size(), "② 還沒長大（0 級）：腳數跟設計檔一樣")
	var legged: CreatureDesign = CreatureGrowth.shape_at(design, 5, _balance)
	var last: LegDesign = design.legs[-1]
	var ok: bool = legged.legs.size() > design.legs.size()
	for i: int in range(design.legs.size(), legged.legs.size()):
		var leg: LegDesign = legged.legs[i]
		var previous: LegDesign = legged.legs[i - 1]
		ok = ok and leg.attach_segment == previous.attach_segment + 3 and leg.group != previous.group
	var original_gap: int = design.body.segment_count - 1 - design.legs[-1].attach_segment
	ok = ok and legged.body.segment_count - 1 - legged.legs[-1].attach_segment >= original_gap
	_expect(ok, "② 變長＋長出腳：腳 %d → %d 組，每隔 3 節一組、A／B 交錯、離尾巴的距離跟原本一樣" % [design.legs.size(), legged.legs.size()])
	_expect(is_equal_approx(legged.legs[-1].thigh_length, last.thigh_length), "② 新的腳複製最後一組腳的樣子")

	var no_legs: CreatureDesign = _example("snake")
	no_legs.growth_mode = CreatureDesign.Growth.LONGER_WITH_LEGS
	_expect(CreatureGrowth.shape_at(no_legs, 5, _balance).legs.is_empty(), "② 沒有腳的生物：只變長，不會憑空長腳")

	var thick: CreatureDesign = _example("snake")
	thick.growth_mode = CreatureDesign.Growth.LONGER
	thick.thicken_ratio = 0.0
	var thin_5: CreatureDesign = CreatureGrowth.shape_at(thick, 5, _balance)
	var start: CreatureDesign = CreatureGrowth.shape_at(thick, 0, _balance)
	thick.thicken_ratio = 0.5
	var thick_5: CreatureDesign = CreatureGrowth.shape_at(thick, 5, _balance)
	_expect(absf(thin_5.body.thickness - start.body.thickness) < start.body.thickness * 0.05, "變粗佔 0 成：只變長，粗細差不多（%.1f → %.1f，節數取整數時微調）" % [start.body.thickness, thin_5.body.thickness])
	_expect(thick_5.body.thickness > start.body.thickness and thick_5.body.segment_count > start.body.segment_count, "變粗佔 5 成：粗細 %.1f → %.1f、節數 %d → %d，又粗又長" % [start.body.thickness, thick_5.body.thickness, start.body.segment_count, thick_5.body.segment_count])
	_expect(thick_5.body.segment_count < thin_5.body.segment_count, "變粗佔 5 成：節數比只變長少（%d < %d）" % [thick_5.body.segment_count, thin_5.body.segment_count])
	_expect(absf(CreatureGrowth.body_size(thick_5.body) - CreatureGrowth.body_size(thin_5.body)) < CreatureGrowth.body_size(thin_5.body) * 0.05, "變粗佔幾成都一樣：升 5 級的體型差不多（%.0f、%.0f）" % [CreatureGrowth.body_size(thick_5.body), CreatureGrowth.body_size(thin_5.body)])
	var dict: Dictionary = thick.to_dict()
	_expect(is_equal_approx(CreatureDesign.from_data(dict).thicken_ratio, 0.5), "變粗佔幾成：存讀一致")
	dict.erase("thicken_ratio")
	_expect(CreatureDesign.from_data(dict).thicken_ratio == 0.0, "舊的設計檔沒有這一欄：用 0（只變長，跟以前一樣）")


func _test_segment_cap() -> void:
	print("--- 節數上限 ---")
	var design: CreatureDesign = _example("snake")
	design.growth_mode = CreatureDesign.Growth.LONGER
	var shape: CreatureDesign = CreatureGrowth.shape_at(design, 60, _balance)
	var expected: float = _size(design, 0) + _balance.size_per_level * 60
	_expect(shape.body.segment_count <= _balance.max_grow_segments, "升 60 級：節數 %d，沒超過上限 %d" % [shape.body.segment_count, _balance.max_grow_segments])
	_expect(absf(CreatureGrowth.body_size(shape.body) - expected) / expected < 0.001, "節數到上限後改成等比放大，體型還是對的")


func _test_original_untouched() -> void:
	print("--- 不改到原本的設計檔 ---")
	var design: CreatureDesign = _example("dragon")
	design.growth_mode = CreatureDesign.Growth.LONGER_WITH_LEGS
	var before: Dictionary = design.to_dict()
	CreatureGrowth.shape_at(design, 8, _balance)
	_expect(design.to_dict() == before, "shape_at() 之後原本的設計檔不變")


func _test_creature_grow() -> void:
	print("--- 生物升級 ---")
	var design: CreatureDesign = _example("centipede")
	design.growth_mode = CreatureDesign.Growth.LONGER_WITH_LEGS
	var creature := Creature.new()
	creature.design = design
	creature.position = Vector2(640, 360)
	creature.control_mode = Creature.Mode.WANDER
	add_child(creature)
	for i: int in 60:
		await get_tree().process_frame
	var body: ChainBody = creature.get_body()
	var joints_before: PackedVector2Array = body.get_joints()
	var legs_before: int = creature.shape.legs.size()
	creature.grow(4)
	var new_body: ChainBody = creature.get_body()
	_expect(creature.shape.legs.size() > legs_before, "升 4 級：腳 %d → %d 組（重長了）" % [legs_before, creature.shape.legs.size()])
	_expect(new_body.joint_count() == creature.shape.body.segment_count, "身體節數跟現在的形狀一樣（%d）" % new_body.joint_count())
	var same_pose: bool = true
	for i: int in joints_before.size():
		same_pose = same_pose and new_body.get_joint(i).is_equal_approx(joints_before[i])
	_expect(same_pose, "重長後身體維持原本的姿勢（沒有突然拉直）")
	_expect(is_equal_approx(CreatureGrowth.body_size(creature.shape.body), _size(design, 4)), "體型等於「設計檔升 4 級」")
	creature.shrink(10)
	_expect(creature.shape.body.segment_count == _example("centipede").body.segment_count, "等級變成負的：當作 0 級，回到原本的大小")
	for i: int in 10:
		await get_tree().process_frame
	_expect(is_instance_valid(creature), "長大、變短後繼續動不會當掉")
	creature.queue_free()


func _test_stats() -> void:
	print("--- 能力 ---")
	var base: CreatureDesign = _example("spider")
	var stats: CreatureStats = _stats(base)

	var fewer_legs: CreatureDesign = _example("spider")
	fewer_legs.legs.resize(2)
	_expect(_stats(fewer_legs).speed < stats.speed, "腳少跑得慢：%.0f < %.0f" % [_stats(fewer_legs).speed, stats.speed])
	_expect(_stats(base, 5).speed < stats.speed, "越大越慢：升 5 級 %.0f < %.0f" % [_stats(base, 5).speed, stats.speed])
	var floor_speed: float = stats.speed * _balance.min_speed_ratio
	_expect(_stats(base, 5).speed < floor_speed, "（前提）只看形狀的話，蜘蛛升 5 級會慢到下限以下：%.0f < %.0f" % [_stats(base, 5).speed, floor_speed])
	var at_5: CreatureStats = CreatureStats.at_level(base, 5, _balance)
	_expect(is_equal_approx(at_5.speed, floor_speed), "長大最多慢到 0 級的 %.0f%%：升 5 級 %.0f" % [_balance.min_speed_ratio * 100.0, at_5.speed])
	var snake: CreatureDesign = _example("snake")
	_expect(is_equal_approx(CreatureStats.at_level(snake, 1, _balance).speed, _stats(snake, 1).speed), "還沒慢到下限：照形狀算（蛇升 1 級 %.0f）" % _stats(snake, 1).speed)
	_expect(is_equal_approx(CreatureStats.at_level(base, 0, _balance).speed, stats.speed), "0 級：照形狀算")
	var snake_tentacle: CreatureDesign = _example("snake")
	var tentacle := TentacleDesign.new()
	tentacle.length = 200.0
	snake_tentacle.tentacles.append(tentacle)
	_expect(_stats(snake_tentacle).turn < _stats(snake).turn, "觸手越長越難轉：蛇加一條 200 的觸手 %.0f → %.0f 度／秒" % [rad_to_deg(_stats(snake).turn), rad_to_deg(_stats(snake_tentacle).turn)])
	_expect(_stats(_example("jellyfish")).turn <= _balance.max_turn + 0.001, "身體很短的水母：轉向也不超過上限 %.0f" % rad_to_deg(_balance.max_turn))

	var swimmer: CreatureDesign = _example("snake")
	var still: CreatureDesign = _example("snake")
	still.body.swim_amplitude = 0.0
	_expect(_stats(swimmer).speed > _stats(still).speed, "游動擺幅也算推進力：%.0f > %.0f" % [_stats(swimmer).speed, _stats(still).speed])

	var long_body: CreatureDesign = _example("spider")
	long_body.body.segment_count = 20
	long_body.body.thickness = 5.0
	_expect(_stats(long_body).turn < stats.turn, "身體越長越難轉：%.0f° < %.0f°" % [rad_to_deg(_stats(long_body).turn), rad_to_deg(stats.turn)])

	var octopus: CreatureDesign = _example("octopus")
	_expect(stats.grab == 0.0 and _stats(octopus).grab > 0.0, "沒觸手抓取 0；章魚抓取 %.0f" % _stats(octopus).grab)
	octopus.tentacles[0].length = 400.0
	_expect(_stats(octopus).grab == _balance.max_grab, "觸手再長，抓取最多 %.0f" % _balance.max_grab)

	var more_eyes: CreatureDesign = _example("spider")
	more_eyes.eyes[0].count = 1
	_expect(_stats(more_eyes).sight < stats.sight, "眼睛少看得近：%.0f < %.0f" % [_stats(more_eyes).sight, stats.sight])

	var fast: CreatureDesign = _example("spider")
	for leg: LegDesign in fast.legs:
		leg.side = CreaturePart.Side.BOTH
	fast.legs.append_array(fast.legs.duplicate())
	_expect(_stats(fast).speed <= _balance.max_speed, "速度有上限 %.0f" % _balance.max_speed)

	var ornate: CreatureDesign = _example("spider")
	for i: int in 10:
		ornate.ornaments.append(OrnamentDesign.new())
	_expect(_stats(ornate).speed == stats.speed and _stats(ornate).level_cost == stats.level_cost, "掛件不算能力、不花成本")

	var weak: CreatureDesign = _example("spider")
	weak.legs.clear()
	weak.eyes.clear()
	_expect(_stats(weak).level_cost < stats.level_cost, "能力越強升級越貴：沒腳沒眼睛 %d < 原本 %d" % [_stats(weak).level_cost, stats.level_cost])
	var costs: Array[int] = []
	for mode: int in 3:
		var design: CreatureDesign = _example("spider")
		design.growth_mode = mode
		costs.append(_stats(design).level_cost)
	_expect(costs[2] < costs[0] and costs[0] < costs[1], "成本：③ 只變長 %d < ① 等比放大 %d < ② 變長＋長腳 %d" % [costs[2], costs[0], costs[1]])

	print("  （參考）8 隻範例 0 級的能力：")
	for example: String in ["snake", "centipede", "octopus", "spider", "jellyfish", "dragon", "doodle", "predator_eel"]:
		var s: CreatureStats = _stats(_example(example))
		print("    %-12s 體型 %5.0f　速度 %3.0f %s　轉向 %3.0f° %s　抓取 %3.0f %s　視野 %3.0f %s　升一級吃 %d 個" % [example, s.size,
			s.speed, _star_text(s, "speed"), rad_to_deg(s.turn), _star_text(s, "turn"), s.grab, _star_text(s, "grab"), s.sight, _star_text(s, "sight"), s.level_cost])


func _test_balance_file() -> void:
	print("--- 平衡資料檔 ---")
	_expect(ResourceLoader.exists(CreatureBalance.DEFAULT_PATH) and load(CreatureBalance.DEFAULT_PATH) is CreatureBalance, "balance.tres 讀得到")
	var stats: CreatureStats = _stats(_example("spider"))
	var ok: bool = true
	for ability: String in ["speed", "turn", "sight"]:
		var count: int = stats.stars(ability, _balance.max_stars)
		ok = ok and count >= 1 and count <= _balance.max_stars
	_expect(ok and stats.stars("grab", _balance.max_stars) == 0, "星星在 1～%d 之間；沒有的能力 0 顆" % _balance.max_stars)


func _test_complexity() -> void:
	print("--- 複雜度 ---")
	var limit: int = _balance.max_complexity
	print("  （參考）範例的複雜度（上限 %d）：0 級 → 8 級 → 30 級" % limit)
	for example: String in ["snake", "centipede", "octopus", "spider", "jellyfish", "dragon", "doodle", "predator_eel"]:
		var design: CreatureDesign = _example(example)
		print("    %-12s %3d → %3d → %3d" % [example, _stats(design).complexity, _stats(design, 8).complexity, _stats(design, 30).complexity])
		_expect(_stats(design).complexity <= limit, "%s 0 級在上限內" % example)
		var worst: int = 0
		for mode: int in 3:
			design.growth_mode = mode
			for level: int in [1, 5, 10, 20, 30, 60]:
				worst = maxi(worst, _stats(design, level).complexity)
		_expect(worst <= limit, "%s 三種長大方式升到 60 級，複雜度最多 %d，沒超過上限" % [example, worst])

	var centipede: CreatureDesign = _example("centipede")
	var start: CreatureDesign = CreatureGrowth.shape_at(centipede, 0, _balance)
	var grown: CreatureDesign = CreatureGrowth.shape_at(centipede, 30, _balance)
	_expect(grown.legs.size() > start.legs.size() and grown.body.segment_count > start.body.segment_count, "② 蜈蚣長大：先加節、加腳（%d → %d 組腳）" % [start.legs.size(), grown.legs.size()])
	_expect(grown.body.spacing > start.body.spacing, "② 蜈蚣到上限後改成整隻放大（間距 %.1f → %.1f）" % [start.body.spacing, grown.body.spacing])

	# 會抓食物的觸手：抓取角度越大越貴（90 度每條多 points_per_grab_angle 點），其他行為不算角度
	var arm: CreatureDesign = _example("snake")
	var grabber := TentacleDesign.new()
	grabber.side = CreaturePart.Side.BOTH
	arm.tentacles.append(grabber)
	var waving: int = _stats(arm).complexity
	grabber.behavior = Tentacle.Behavior.GRAB_FOOD
	grabber.grab_angle = deg_to_rad(90.0)
	var wide: int = _stats(arm).complexity
	grabber.grab_angle = deg_to_rad(45.0)
	var narrow: int = _stats(arm).complexity
	_expect(wide - waving == roundi(_balance.points_per_grab_angle * 2) and narrow - waving == roundi(_balance.points_per_grab_angle), "抓食物的觸手（兩邊）：90 度多 %d 點、45 度多 %d 點；不抓的不算角度" % [wide - waving, narrow - waving])

	var heavy: CreatureDesign = _example("centipede")
	heavy.body.segment_count = 60
	var heavy_start: int = _stats(heavy).complexity
	_expect(heavy_start > limit and _stats(heavy, 20).complexity <= heavy_start, "原本就超過上限的設計檔（%d）：長大時不會再變多（%d）" % [heavy_start, _stats(heavy, 20).complexity])

	var ornate: CreatureDesign = _example("spider")
	var plain_stats: CreatureStats = _stats(ornate)
	ornate.ornaments.append(OrnamentDesign.new())
	var both := OrnamentDesign.new()
	both.side = CreaturePart.Side.BOTH
	ornate.ornaments.append(both)
	_expect(_stats(ornate).complexity == plain_stats.complexity + _balance.points_per_ornament * 3, "掛件算複雜度：一個 + 兩邊一對 = %d 點" % (_balance.points_per_ornament * 3))
	_expect(_stats(ornate).level_cost == plain_stats.level_cost, "掛件不算進升級成本")

	var dense: CreatureDesign = _example("octopus")
	for tentacle: TentacleDesign in dense.tentacles:
		tentacle.segment_count *= 2  # 長度不變，只是節數變多（抓取範圍一樣）
	_expect(_stats(dense).grab == _stats(_example("octopus")).grab and _stats(dense).level_cost > _stats(_example("octopus")).level_cost,
		"觸手節數變多（抓取一樣）：複雜度 %d → %d，升級變貴 %d → %d" % [_stats(_example("octopus")).complexity, _stats(dense).complexity, _stats(_example("octopus")).level_cost, _stats(dense).level_cost])


# ---------------------------------------------------------------- 工具


## 讀一隻範例的設計檔（複製一份，改了不會影響別的測試）
func _example(example: String) -> CreatureDesign:
	return CreatureDesign.from_data((load(EXAMPLES + example + "/design.tres") as CreatureDesign).to_dict())


func _size(design: CreatureDesign, level: int) -> float:
	return CreatureGrowth.body_size(CreatureGrowth.shape_at(design, level, _balance).body)


func _stats(design: CreatureDesign, level: int = 0) -> CreatureStats:
	return CreatureStats.compute(CreatureGrowth.shape_at(design, level, _balance), _balance)


func _star_text(stats: CreatureStats, ability: String) -> String:
	var count: int = stats.stars(ability, _balance.max_stars)
	return "★".repeat(count) + "☆".repeat(_balance.max_stars - count)


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
