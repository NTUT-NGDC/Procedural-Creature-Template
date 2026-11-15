extends Node
## 工坊教學步驟檢查（TutorialChecker）的自動測試：每一步都用「該過」和「不該過」的設計檔測，
## 並確認沒過時的原因文字對得上；最後用亂七八糟的資料確認檢查不會當掉。
##
## 設計檔直接從範例複製一份來改（不另外放測試用的 .tres），
## 實驗紀錄（TutorialRecord）照社員的操作順序一步一步餵。
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/tutorial_checker_test.tscn

var _failures: int = 0


func _ready() -> void:
	_test_name()
	_test_bend()
	_test_body()
	_test_tentacle()
	_test_legs()
	_test_saved()
	_test_growth()
	_test_ornaments()
	_test_broken_data()
	if _failures == 0:
		print("[教學檢查測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[教學檢查測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_name() -> void:
	print("--- 1. 取名字 ---")
	var design: CreatureDesign = _example("snake")
	var record := _record(design)
	_check(0, design, record, false, "名字還是", "沒改名字")
	design.creature_name = "我的生物"
	_check(0, design, record, false, "取一個", "預設的名字")
	design.creature_name = "   "
	_check(0, design, record, false, "取一個", "只有空白")
	design.creature_name = "阿蛇"
	_check(0, design, record, true, "", "改成自己的名字")


func _test_bend() -> void:
	print("--- 2. 把身體折斷 ---")
	var design: CreatureDesign = _example("snake")
	var record := _record(design)
	_check(1, design, record, false, "還沒把", "還沒動")
	_edit(design, record, func() -> void: design.body.max_bend = deg_to_rad(140.0))
	_edit(design, record, func() -> void: design.body.max_bend = deg_to_rad(40.0))
	_check(1, design, record, false, "還沒把", "只拉到 140 度：不算弄壞")
	_edit(design, record, func() -> void: design.body.max_bend = deg_to_rad(170.0))
	_check(1, design, record, false, "調回", "拉到 170 度但還沒調回來")
	_edit(design, record, func() -> void: design.body.max_bend = deg_to_rad(70.0))
	_check(1, design, record, false, "調回", "調回 70 度：還不夠")
	_edit(design, record, func() -> void: design.body.max_bend = deg_to_rad(45.0))
	_check(1, design, record, true, "", "弄壞再調回 45 度")


func _test_body() -> void:
	print("--- 3. 改出自己的身體 ---")
	var design: CreatureDesign = _example("snake")
	var record := _record(design)
	_check(2, design, record, false, "改了 0 種", "還沒改")
	design.body.max_bend = deg_to_rad(10.0)
	design.body.swim_amplitude = 30.0
	_check(2, design, record, false, "改了 0 種", "只改彎曲角、游動：不算")
	design.body.segment_count += 5
	_check(2, design, record, false, "改了 1 種（節數）", "只改節數")
	design.body.pattern_color = Color.RED
	_check(2, design, record, true, "", "節數＋花紋顏色")
	var other: CreatureDesign = _example("snake")
	var other_record := _record(other)
	other.body.width_curve.set_point_value(0, 0.1)
	other.body.body_gradient.set_color(0, Color.BLUE)
	_check(2, other, other_record, true, "", "粗細形狀＋顏色（改漸層、曲線本身）")


func _test_tentacle() -> void:
	print("--- 4. 觸手跟不上 ---")
	var design: CreatureDesign = _example("snake")
	design.tentacles.clear()
	var record := _record(design)
	_check(3, design, record, false, "還沒有觸手", "沒有觸手")
	_edit(design, record, func() -> void: design.tentacles.append(TentacleDesign.new()))
	_check(3, design, record, false, "拉到 1", "加了觸手但沒做實驗")
	_edit(design, record, func() -> void: design.tentacles[0].iterations = 2)
	_check(3, design, record, false, "拉到 1", "只調到 2：不算")
	_edit(design, record, func() -> void: design.tentacles[0].iterations = 1)
	_check(3, design, record, false, "調回", "調到 1 還沒調回來")
	_edit(design, record, func() -> void: design.tentacles[0].iterations = 3)
	_check(3, design, record, true, "", "調到 1 再調回 3")
	_edit(design, record, func() -> void:
		var second := TentacleDesign.new()
		second.iterations = 2
		design.tentacles.append(second))
	_check(3, design, record, false, "現在有一隻是 2", "第二隻觸手只有 2 次")


func _test_legs() -> void:
	print("--- 5. 腳打直、腳亂走 ---")
	var design: CreatureDesign = _example("spider")
	var record := _record(design)
	_check(4, design, record, false, "拉到 1", "蜘蛛還沒做實驗")
	var one_leg: CreatureDesign = _example("snake")
	one_leg.legs.assign([LegDesign.new()])
	_check(4, one_leg, _record(one_leg), false, "2 組以上", "只有 1 組腳")
	_edit(design, record, func() -> void: design.legs[0].rest_distance = 1.0)
	_check(4, design, record, false, "調回", "腳打直還沒調回來")
	_edit(design, record, func() -> void: design.legs[0].rest_distance = 0.95)
	_check(4, design, record, false, "調回", "調回 0.95：還不夠")
	_edit(design, record, func() -> void: design.legs[0].rest_distance = 0.8)
	_check(4, design, record, false, "同一組", "① 做完、② 還沒做")
	_edit(design, record, func() -> void:
		for leg: LegDesign in design.legs:
			leg.group = IKLeg.Group.B)
	_check(4, design, record, false, "改回", "全部同一組還沒改回來")
	_edit(design, record, func() -> void: design.legs[1].group = IKLeg.Group.A)
	_check(4, design, record, true, "", "① ② 都做完")


func _test_saved() -> void:
	print("--- 6. 存檔 ---")
	var design: CreatureDesign = _example("snake")
	var record := _record(design)
	_check(5, design, record, false, "還沒存檔", "還沒存")
	record.mark_saved(design)
	_check(5, design, record, true, "", "存好了")
	design.body.thickness += 3.0
	_check(5, design, record, false, "又改了", "存完又改")
	_expect(not TutorialChecker.is_sticky(TutorialChecker.SAVE_STEP) and TutorialChecker.is_sticky(1), "只有「存檔」改了會變回沒過")


func _test_growth() -> void:
	print("--- 7. 額外：看它長大 ---")
	var design: CreatureDesign = _example("snake")
	var record := _record(design)
	record.observe_level(4)
	_check(6, design, record, false, "預覽等級", "只拉到 4 級")
	record.observe_level(6)
	record.observe_level(0)
	_check(6, design, record, false, "長大方式", "拉到 6 級、還沒換長大方式")
	design.growth_mode = (design.growth_mode + 1) % 3
	_check(6, design, record, true, "", "拉到 6 級、換了長大方式")


func _test_ornaments() -> void:
	print("--- 8、9. 額外：掛件 ---")
	var design: CreatureDesign = _example("snake")
	design.ornaments.clear()
	var record := _record(design)
	_check(7, design, record, false, "還沒有掛件", "沒有掛件（動法）")
	_check(8, design, record, false, "還沒有掛件", "沒有掛件（圖）")
	var ornament := OrnamentDesign.new()
	design.ornaments.append(ornament)
	_check(7, design, record, false, "拍動", "掛件是固定的")
	_check(8, design, record, false, "匯入圖片", "掛件沒有圖")
	ornament.motion = Ornament.Motion.SPRING
	ornament.image_file = "head.png"
	_check(7, design, record, true, "", "掛件會彈")
	_check(8, design, record, true, "", "掛件有自己的圖")


func _test_broken_data() -> void:
	print("--- 資料不完整、亂七八糟 ---")
	var broken: CreatureDesign = CreatureDesign.from_data({"creature_name": 3, "body": 5, "legs": "abc", "tentacles": [1, "x", {}], "ornaments": [null, {"motion": "飛"}]})
	var record := TutorialRecord.new()
	record.observe(broken)
	for i: int in TutorialChecker.STEP_COUNT:
		TutorialChecker.check(i, broken, record)  # 不當掉就好
	record.open(broken)
	for i: int in TutorialChecker.STEP_COUNT:
		TutorialChecker.check(i, broken, record)
	_expect(TutorialChecker.check(0, null, record) != "", "沒有設計檔：沒過、不當掉")
	_expect(TutorialChecker.check(0, broken, null) != "", "沒有紀錄：沒過、不當掉")
	_expect(TutorialChecker.check(-1, broken, record) != "" and TutorialChecker.check(99, broken, record) != "", "沒有這一步：沒過、不當掉")
	var empty_start := TutorialRecord.new()  # 沒呼叫 open()：起點是空的
	_expect(TutorialChecker.check(2, _example("snake"), empty_start) == "", "起點是空的：身體每一種都算改過、不當掉")
	var steps: TutorialSteps = load("res://lesson/tutorial/data/tutorial_steps.tres")
	_expect(steps.steps.size() == TutorialChecker.STEP_COUNT, "步驟文字有 %d 步（%d）" % [TutorialChecker.STEP_COUNT, steps.steps.size()])
	for step: TutorialStep in steps.steps:
		_expect(step.title != "" and step.description != "" and step.hint != "" and step.done_text != "", "「%s」每一欄都有字" % step.title)


# ---------------------------------------------------------------- 工具


## 一份範例設計檔的複本（改了不會動到範例）
func _example(folder: String) -> CreatureDesign:
	var loaded: CreatureDesign = ResourceLoader.load("res://example/creatures/%s/design.tres" % folder, "", ResourceLoader.CACHE_MODE_IGNORE)
	return CreatureDesign.from_data(loaded.to_dict())


func _record(design: CreatureDesign) -> TutorialRecord:
	var record := TutorialRecord.new()
	record.open(design)
	return record


## 像工坊那樣：改了設計檔就通知紀錄
func _edit(design: CreatureDesign, record: TutorialRecord, change: Callable) -> void:
	change.call()
	record.observe(design)


func _check(index: int, design: CreatureDesign, record: TutorialRecord, should_pass: bool, reason_part: String, label: String) -> void:
	var reason: String = TutorialChecker.check(index, design, record)
	var ok: bool = (reason == "") == should_pass and (should_pass or reason_part in reason)
	_expect(ok, "第 %d 步 %s：%s%s" % [index + 1, label, "過" if should_pass else "沒過", "" if reason == "" else "（%s）" % reason])


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
