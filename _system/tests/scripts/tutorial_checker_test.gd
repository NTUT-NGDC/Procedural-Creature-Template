extends Node
## 教學關檢查邏輯（creature_checker.gd）的自動測試。
## 每個範例資料夾（_system/tests/tutorial_fixtures/）模擬一種社員的 my_creature，
## 用 10 個字元表示 10 步該不該過：P 是過、F 是沒過、. 是不檢查。再檢查幾個「還差一點」的原因文字。
##
## 範例資料夾用 make_tutorial_fixtures.tscn 產生。
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/tutorial_checker_test.tscn

const FIXTURES: String = "res://_system/tests/tutorial_fixtures/"
const FULL_TITLE: String = FIXTURES + "full_pass/title_screen.tscn"

## [資料夾, 10 步的結果, {第幾步（從 1 開始）: 原因要包含的文字}, 標題畫面（空的就用真的標題畫面）]
const CASES: Array = [
	["empty", "FFFFFFFFFF", {1: "還沒有生物", 2: "先完成第 1 步", 5: "還沒有池塘"}, ""],
	["garbage", "FFFFFFFFFF", {1: "讀不出來"}, ""],
	["same_name", "FFFFFFFFFF", {1: "檔名跟範例一樣"}, ""],
	["copy_only", "PFFFFFFFFF", {2: "都跟範例一樣", 3: "還沒有腳", 4: "還沒有觸手", 6: "還是 example/pond/pond.tscn"}, ""],
	["body_one", "PFFFFFFFFF", {2: "只改了 1 項（節數）"}, ""],
	["body_two", "PPFFFFFFFF", {}, ""],
	["legs_added", "PFPFFFFFFF", {}, ""],
	["spider_same", "PFFFFFFFFF", {3: "數量跟範例一樣"}, ""],
	["spider_leg_changed", "PFPFFFFFFF", {}, ""],
	["tentacle_grab", "PFFPFFFPFF", {}, ""],
	["pond_example_player", "PFFFFFFFFF", {5: "還在用範例的生物", 7: "還是範例的生物"}, ""],
	["pond_no_rule", "PFFFFFFFFF", {5: "規則都跟範例一樣"}, ""],
	["script_no_connect", "PFFFFFFFFF", {9: "還沒連接 grew"}, ""],
	["script_code_connect", "PFFFFFFFPF", {}, ""],
	["ornament_horn", "PFFFFFFFFF", {10: "預設的「角」"}, ""],
	["ornament_sprite", "PFFFFFFFFP", {}, ""],
	["full_pass", "PPPPPFPPPP", {6: "按上面的「試玩」"}, FULL_TITLE],
]

var _failures: int = 0


func _ready() -> void:
	for test_case: Array in CASES:
		_check_case(test_case[0], test_case[1], test_case[2], test_case[3], false, "")
	print("--- full_pass 試玩到結算 ---")
	var pond_path: String = FIXTURES + "full_pass/my_pond.tscn"
	_check_case("full_pass", "PPPPPPPPPP", {6: "玩到結算了"}, FULL_TITLE, true, pond_path)
	_check_case("full_pass", ".....F....", {6: "按上面的「試玩」"}, FULL_TITLE, true, FIXTURES + "other_pond.tscn")
	_test_misplaced()
	_test_title_pond()

	if _failures == 0:
		print("[教學關檢查測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[教學關檢查測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _check_case(folder: String, expected: String, reasons: Dictionary, title: String, played: bool, played_pond: String) -> void:
	var checker: CreatureChecker = CreatureChecker.new(FIXTURES + folder, title if title != "" else CreatureChecker.DEFAULT_TITLE_SCENE)
	var results: Array[CreatureChecker.Result] = _all_results(checker, played, played_pond)
	var actual: String = ""
	for result: CreatureChecker.Result in results:
		actual += "P" if result.passed else "F"
	var matches: bool = true
	for i: int in expected.length():
		if expected[i] != "." and expected[i] != actual[i]:
			matches = false
	_expect(matches, "%s：預期 %s，實際 %s" % [folder, expected, actual])
	if not matches:
		for i: int in results.size():
			print("      第 %d 步：%s" % [i + 1, results[i].message])
	for step: int in reasons:
		var message: String = results[step - 1].message
		_expect(reasons[step] in message, "%s 第 %d 步的原因包含「%s」（%s）" % [folder, step, reasons[step], message])


func _all_results(checker: CreatureChecker, played: bool, played_pond: String) -> Array[CreatureChecker.Result]:
	return [
		checker.check_copy(), checker.check_body(), checker.check_legs(), checker.check_tentacles(),
		checker.check_pond(), checker.check_title_and_play(played, played_pond), checker.check_predator(),
		checker.check_grab(), checker.check_script(), checker.check_ornament(),
	]


## 複製的生物存在範例資料夾裡，沒有搬到 my_creature
func _test_misplaced() -> void:
	print("--- 存錯地方 ---")
	var checker := CreatureChecker.new(FIXTURES + "empty", CreatureChecker.DEFAULT_TITLE_SCENE, FIXTURES + "misplaced_examples")
	var result: CreatureChecker.Result = checker.check_copy()
	_expect(not result.passed and "misplaced_examples/my_snake.tscn" in result.message and "要放在" in result.message, "在範例資料夾找到複製的生物：提示要放到 my_creature（%s）" % result.message)


func _test_title_pond() -> void:
	print("--- 讀標題畫面的 Pond Scene ---")
	var real := CreatureChecker.new(FIXTURES + "empty")
	_expect(real.get_title_pond() == "res://example/pond/pond.tscn", "真的標題畫面接的是範例池塘")
	var fixture := CreatureChecker.new(FIXTURES + "empty", FULL_TITLE)
	_expect(fixture.get_title_pond() == FIXTURES + "full_pass/my_pond.tscn", "full_pass 的標題畫面接的是自己的池塘")
	var missing := CreatureChecker.new(FIXTURES + "empty", FIXTURES + "不存在.tscn")
	_expect(missing.get_title_pond() == "" and not missing.check_title_and_play(true, "").passed, "標題畫面讀不到：第 6 步沒過、不會當掉")


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
