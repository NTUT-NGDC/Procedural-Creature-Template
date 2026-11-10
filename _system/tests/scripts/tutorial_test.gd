extends Node
## 教學關介面的自動測試（檢查邏輯本身在 tutorial_checker_test.gd 測）：
## 1. 空資料夾：10 步都未完成、進度 0／6、不會當掉
## 2. 每一步都做到的資料夾：試玩以外都完成；按「試玩」玩到結算，按「回標題」回到教學關，第 6 步完成
## 3. 試玩到一半按「結束試玩」：第 6 步不算完成
## 4. 試玩時從暫停選單「回到標題」：回到教學關，不會離開教學關
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/tutorial_test.tscn

const TUTORIAL_SCENE: PackedScene = preload("res://lesson/tutorial/tutorial.tscn")
const FIXTURES: String = "res://_system/tests/tutorial_fixtures/"
const FULL_TITLE: String = FIXTURES + "full_pass/title_screen.tscn"

var _failures: int = 0


func _ready() -> void:
	await _test_empty_folder()
	await _test_full_pass_play()
	await _test_stop_midway()
	await _test_pause_menu_title()

	get_tree().paused = false
	if _failures == 0:
		print("[教學關介面測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[教學關介面測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_empty_folder() -> void:
	print("--- 空資料夾 ---")
	var tutorial: Control = await _spawn("empty", CreatureChecker.DEFAULT_TITLE_SCENE)
	_expect(tutorial.get_node("%StepList").get_child_count() == 10, "列出 10 個步驟")
	_expect(_status_texts(tutorial) == ",".join(_repeat("未完成", 10)), "10 步都未完成")
	_expect(_progress(tutorial) == "已完成 0／6 步　額外：0／4", "進度顯示 0／6、額外 0／4")
	(tutorial.get_node("%CheckButton") as Button).pressed.emit()
	_expect(true, "按檢查不會當掉")
	await _free(tutorial)


func _test_full_pass_play() -> void:
	print("--- 每一步都做到，試玩到結算 ---")
	var tutorial: Control = await _spawn("full_pass", FULL_TITLE)
	_expect(_status_texts(tutorial) == "完成！,完成！,完成！,完成！,完成！,未完成,完成！,完成！,完成！,完成！", "試玩以外都完成，第 6 步還沒")
	_expect(_progress(tutorial) == "已完成 5／6 步　額外：4／4", "進度顯示 5／6、額外 4／4")
	_expect("full_pass/my_pond.tscn" in (tutorial.get_node("%PlayLabel") as Label).text, "試玩的是標題畫面接上的池塘")

	var pond: Pond = await _start_play(tutorial)
	_expect(pond != null and not (tutorial.get_node("%MainPanel") as Control).visible, "試玩時藏起教學介面、池塘在跑")
	if pond == null:
		await _free(tutorial)
		return
	# 玩到結算：一直吃到長度 20
	for i: int in 10:
		(pond.get("_player") as Creature).eat(pond.get_node("%Foods").get_child(0))
	await get_tree().process_frame
	_expect(get_tree().paused and (pond.get_node("%Result") as CanvasLayer).visible, "玩到結算畫面")
	(pond.get_node("%TitleButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(get_tree().current_scene == self, "按「回標題」沒有離開教學關")
	_expect((tutorial.get_node("%MainPanel") as Control).visible and not get_tree().paused, "回到教學介面、解除暫停")
	_expect(_status_texts(tutorial) == ",".join(_repeat("完成！", 10)), "10 步全部完成")
	_expect(_progress(tutorial) == "已完成 6／6 步　額外：4／4", "進度顯示 6／6")
	await _free(tutorial)


func _test_stop_midway() -> void:
	print("--- 試玩到一半按結束 ---")
	var tutorial: Control = await _spawn("full_pass", FULL_TITLE)
	await _start_play(tutorial)
	(tutorial.get_node("%StopButton") as Button).pressed.emit()
	await get_tree().process_frame
	_expect((tutorial.get_node("%MainPanel") as Control).visible, "按結束試玩回到教學介面")
	_expect(_status_texts(tutorial).split(",")[5] == "未完成", "第 6 步不算完成")
	await _free(tutorial)


func _test_pause_menu_title() -> void:
	print("--- 試玩時從暫停選單回到標題 ---")
	var tutorial: Control = await _spawn("full_pass", FULL_TITLE)
	var pond: Pond = await _start_play(tutorial)
	var menu: CanvasLayer = pond.get_node("%PauseMenu")
	(menu.get_node("%MenuButton") as Button).pressed.emit()
	_expect(get_tree().paused, "打開暫停選單，遊戲暫停")
	(menu.get_node("%TitleButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(get_tree().current_scene == self and (tutorial.get_node("%MainPanel") as Control).visible, "回到教學關，沒有換到標題畫面")
	_expect(not get_tree().paused, "已解除暫停")
	_expect(_status_texts(tutorial).split(",")[5] == "未完成", "沒玩到結算，第 6 步不算完成")
	await _free(tutorial)


# ---------------------------------------------------------------- 工具


func _spawn(folder_name: String, title: String) -> Control:
	get_tree().paused = false
	var tutorial: Control = TUTORIAL_SCENE.instantiate()
	tutorial.set("creature_folder", FIXTURES + folder_name)
	tutorial.set("title_scene", title)
	add_child(tutorial)
	await get_tree().process_frame
	return tutorial


## 按「試玩」，回傳正在跑的池塘
func _start_play(tutorial: Control) -> Pond:
	(tutorial.get_node("%PlayButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	return tutorial.get("_pond") as Pond


func _free(tutorial: Control) -> void:
	tutorial.queue_free()
	get_tree().paused = false
	await get_tree().process_frame


## 每個步驟的狀態文字，用逗號接起來
func _status_texts(tutorial: Control) -> String:
	var texts: PackedStringArray = []
	for row: Node in tutorial.get_node("%StepList").get_children():
		texts.append((row.get_node("%StatusLabel") as Label).text)
	return ",".join(texts)


func _progress(tutorial: Control) -> String:
	return (tutorial.get_node("%ProgressLabel") as Label).text


func _repeat(text: String, count: int) -> PackedStringArray:
	var texts: PackedStringArray = []
	for i: int in count:
		texts.append(text)
	return texts


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
