extends Node
## 工坊教學步驟卡的自動測試（步驟卡接在工坊上，實際操作工坊）：
## 1. 打開工坊：步驟卡在水族箱左上，全部未完成、顯示第 1 步
## 2. 改名字、把身體折斷再修好：步驟卡跟著過關，顯示這一步的原理
## 3. 做過的步驟又弄壞：還是算過（存檔除外）
## 4. 存檔：過關；存完又改：變回未完成
## 5. 預覽等級、讀別的範例：紀錄留著
## 6. 上一步／下一步、收起來（收起來卡片變矮）
## 7. 按住最上面那一行拖動，拖不出水族箱；工坊換大字，卡片跟著變寬
##
## 測試會在 my_creature/ 建立 zz_tutorial_test 資料夾，結束時刪掉。
## 工坊的設定檔（user://workshop_settings.cfg）測試前先備份、結束時放回去。
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/tutorial_test.tscn

const WORKSHOP_SCENE: PackedScene = preload("res://lesson/workshop/workshop.tscn")
const TEST_FOLDER: String = "zz_tutorial_test"

var _failures: int = 0
var _workshop: Control
var _panel: TutorialPanel
var _old_settings: String = ""


func _ready() -> void:
	_cleanup()
	if FileAccess.file_exists(WorkshopSettings.SAVE_PATH):
		_old_settings = FileAccess.get_file_as_string(WorkshopSettings.SAVE_PATH)
	DirAccess.remove_absolute(WorkshopSettings.SAVE_PATH)  # 從小字開始
	_workshop = WORKSHOP_SCENE.instantiate()
	add_child(_workshop)
	await _frames(3)
	var panels: Array[Node] = _workshop.find_children("*", "TutorialPanel", true, false)
	_panel = panels[0] as TutorialPanel if not panels.is_empty() else null
	_expect(_panel != null, "工坊裡有步驟卡")
	if _panel != null:
		_test_open()
		_test_steps()
		await _test_save()
		_test_record_kept()
		await _test_navigation()
		await _test_drag_and_font()

	_workshop.queue_free()
	await _frames(2)
	_cleanup()
	DirAccess.remove_absolute(WorkshopSettings.SAVE_PATH)
	if _old_settings != "":
		FileAccess.open(WorkshopSettings.SAVE_PATH, FileAccess.WRITE).store_string(_old_settings)
	if _failures == 0:
		print("[教學步驟卡測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[教學步驟卡測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_open() -> void:
	print("--- 打開工坊 ---")
	_expect(_panel.position.x < 50.0 and _panel.position.y < 50.0, "步驟卡在水族箱左上（%s）" % _panel.position)
	_expect(not _panel.passed.has(true), "全部未完成")
	_expect(_progress() == "已完成 0／6 步　額外：0／3", "進度：%s" % _progress())
	_expect(_panel.current == 0 and "1." in _row_text("TitleLabel"), "顯示第 1 步")
	_expect("還差一點" in _row_text("MessageLabel"), "第 1 步顯示還差什麼：%s" % _row_text("MessageLabel"))


func _test_steps() -> void:
	print("--- 改名字、把身體折斷再修好 ---")
	var name_edit: LineEdit = _workshop.get("_name_edit")
	name_edit.text = "測試阿蛇"
	name_edit.text_changed.emit(name_edit.text)
	_expect(_panel.passed[0], "改了名字：第 1 步過了")
	_expect("通過" in _row_text("MessageLabel") and "接下來" in _row_text("MessageLabel"), "顯示這一步的原理：%s" % _row_text("MessageLabel"))

	_set_bend(170.0)
	_expect(not _panel.passed[1], "彎曲角拉到 170：還沒調回來")
	_set_bend(40.0)
	_expect(_panel.passed[1], "調回 40：第 2 步過了")
	_set_bend(170.0)
	_expect(_panel.passed[1], "又拉到 170：做過的還是算過")
	_set_bend(40.0)
	_expect(_progress().begins_with("已完成 2／6"), "進度：%s" % _progress())

	_workshop.call("undo")
	_expect(_panel.passed[1], "按復原：做過的還是算過")


func _test_save() -> void:
	print("--- 存檔 ---")
	(_workshop.get("_folder_edit") as LineEdit).text = TEST_FOLDER
	_workshop.call("_on_save_pressed")
	await _frames(1)
	_expect(_panel.passed[TutorialChecker.SAVE_STEP], "存檔：第 6 步過了")
	_design().body.thickness += 3.0
	_workshop.call("_on_design_changed")
	_expect(not _panel.passed[TutorialChecker.SAVE_STEP], "存完又改：第 6 步變回未完成")
	_expect(TutorialChecker.check(TutorialChecker.SAVE_STEP, _design(), _panel.record).contains("又改了"), "原因是存完又改了")


func _test_record_kept() -> void:
	print("--- 預覽等級、讀別的範例 ---")
	var slider: HSlider = _workshop.get("_level_slider")
	slider.value = 6
	_expect(_panel.record.max_level_seen == 6, "預覽等級拉到 6 有記下來")
	_workshop.call("_load_design", "res://example/creatures/spider/design.tres")
	_expect(_panel.passed[0] and _panel.passed[1], "讀了別的範例：做過的步驟還在")
	_expect(_panel.record.max_level_seen == 6 and str(_panel.record.start.get("creature_name")) == _design().creature_name, "紀錄留著，起點換成新讀的這隻")


func _test_navigation() -> void:
	print("--- 上一步／下一步、收起來 ---")
	var prev: Button = _panel.get_node("%PrevButton")
	var next: Button = _panel.get_node("%NextButton")
	var fold: Button = _panel.get_node("%FoldButton")
	_panel.show_step(0)
	_expect(prev.disabled and not next.disabled, "第 1 步：上一步不能按")
	next.pressed.emit()
	_expect(_panel.current == 1 and "2." in _row_text("TitleLabel"), "按下一步：第 2 步")
	_panel.show_step(TutorialChecker.STEP_COUNT - 1)
	_expect(next.disabled and "9." in _row_text("TitleLabel"), "最後一步：下一步不能按")
	var open_height: float = _panel.size.y
	fold.pressed.emit()
	await _frames(2)
	_expect(not (_panel.get_node("%StepRow") as Control).visible and fold.text == "展開", "收起來")
	_expect(_panel.size.y < open_height * 0.5, "收起來卡片變矮（%d → %d）" % [open_height, _panel.size.y])
	fold.pressed.emit()
	await _frames(2)
	_expect((_panel.get_node("%StepRow") as Control).visible, "再按一次展開")


func _test_drag_and_font() -> void:
	print("--- 拖動、字的大小 ---")
	var header: Control = _panel.get_node("%Header")
	var start: Vector2 = _panel.position
	_header_event(_mouse_button(true))
	_header_event(_mouse_motion(Vector2(120, 60)))
	_header_event(_mouse_button(false))
	_expect(_panel.position.is_equal_approx(start + Vector2(120, 60)), "按住拖動：卡片跟著移（%s → %s）" % [start, _panel.position])
	_header_event(_mouse_motion(Vector2(50, 0)))
	_expect(_panel.position.is_equal_approx(start + Vector2(120, 60)), "放開之後滑鼠動：卡片不動")
	_header_event(_mouse_button(true))
	_header_event(_mouse_motion(Vector2(-5000, 9000)))
	_header_event(_mouse_button(false))
	var area: Control = _panel.get_parent_control()
	_expect(_panel.position.x == 0.0 and is_equal_approx(_panel.position.y + _panel.size.y, area.size.y), "拖太遠：停在水族箱邊上（%s）" % _panel.position)
	_expect(header.mouse_default_cursor_shape == Control.CURSOR_MOVE, "滑鼠移到最上面那一行：移動的游標")

	var small_width: float = _panel.size.x
	_workshop.call("set_font_size", 22)
	await _frames(3)
	_expect(_panel.size.x > small_width * 1.5, "工坊換大字：卡片變寬（%d → %d）" % [small_width, _panel.size.x])
	_expect(_panel.position.y + _panel.size.y <= area.size.y + 0.5, "變大之後還在水族箱裡面")
	_workshop.call("set_font_size", 11)
	await _frames(3)
	_expect(is_equal_approx(_panel.size.x, small_width), "換回小字：寬度回來（%d）" % _panel.size.x)


func _header_event(event: InputEvent) -> void:
	(_panel.get_node("%Header") as Control).gui_input.emit(event)


func _mouse_button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


# ---------------------------------------------------------------- 工具


func _set_bend(degrees: float) -> void:
	_design().body.max_bend = deg_to_rad(degrees)
	_workshop.call("_on_design_changed")


func _design() -> CreatureDesign:
	return _workshop.get("design")


func _progress() -> String:
	return (_panel.get_node("%ProgressLabel") as Label).text


func _row_text(label_name: String) -> String:
	var row: Node = _panel.get_node("%StepRow")
	return (row.get_node("%" + label_name) as Label).text


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _cleanup() -> void:
	var path: String = "res://my_creature/" + TEST_FOLDER
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
