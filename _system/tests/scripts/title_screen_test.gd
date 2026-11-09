extends Node
## 標題畫面、音量設定、暫停選單的自動測試：
## 1. 池塘場景欄位空的、找不到檔案、選到不是場景的檔案 → 顯示提示，不會換場景
## 2. 設定面板可以打開、關閉；電腦版看得到「離開遊戲」；標題音樂會自動播放、播完重播
## 3. 音量：調整後會存檔，重新讀取後音量和滑桿位置都對；拉到 0 是靜音
## 4. 暫停選單：打開時遊戲暫停、選單照常運作；繼續後解除暫停；按 Esc 也能打開；回到標題時已解除暫停
##
## （「標題 → 池塘 → 結算 → 回標題」的完整流程等 T3 做好池塘再加）
##
## 測試會暫時改掉 user://sound_settings.cfg，結束時還原。
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/title_screen_test.tscn

const TITLE_SCENE: PackedScene = preload("res://game/title_screen/title_screen.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://game/pause_menu/pause_menu.tscn")
const TITLE_PATH: String = "res://game/title_screen/title_screen.tscn"
const TIMEOUT_SECONDS: float = 10.0

var _failures: int = 0


func _ready() -> void:
	await _test_problem("", "還沒有設定池塘場景")
	await _test_problem("res://my_creature/不存在的場景.tscn", "找不到池塘場景")
	await _test_problem("res://lesson/card_draw/data/card_deck.tres", "不是場景")
	await _test_settings_panel()
	await _test_title_music()
	await _test_sound_settings()
	await _test_pause_menu()

	if _failures == 0:
		print("[標題畫面測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[標題畫面測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_problem(path: String, expected_text: String) -> void:
	print("--- 池塘場景設成「%s」 ---" % path)
	var title: Control = TITLE_SCENE.instantiate()
	title.set("pond_scene", path)
	add_child(title)
	await get_tree().process_frame

	var message_label: Label = title.get_node("%MessageLabel")
	_expect(not message_label.visible, "一開始不顯示提示")
	(title.get_node("%StartButton") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(message_label.visible, "按開始後顯示提示")
	_expect(expected_text in message_label.text, "提示內容包含「%s」" % expected_text)
	_expect(get_tree().current_scene == self, "沒有換場景")
	title.queue_free()
	await get_tree().process_frame


func _test_settings_panel() -> void:
	print("--- 設定面板 ---")
	var title: Control = TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	var panel: Control = title.get_node("%SettingsPanel")
	_expect((title.get_node("%QuitButton") as Button).visible, "電腦版看得到「離開遊戲」")
	_expect(not panel.visible, "一開始設定面板是關的")
	(title.get_node("%SettingsButton") as Button).pressed.emit()
	_expect(panel.visible, "按「設定」打開面板")
	(title.get_node("%BackButton") as Button).pressed.emit()
	_expect(not panel.visible, "按「返回」關掉面板")
	title.queue_free()
	await get_tree().process_frame


func _test_title_music() -> void:
	print("--- 標題音樂 ---")
	var title: Control = TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	_expect(not title.has_node("TitleMusicPlayer"), "預設沒有放音樂，不會建立播放器、不會出錯")
	title.queue_free()
	await get_tree().process_frame

	# 放一個 0.5 秒的靜音檔，確認會自動播放、播完會重播
	title = TITLE_SCENE.instantiate()
	title.set("title_music", load("res://_system/tests/audio/silence.wav"))
	add_child(title)
	await get_tree().process_frame
	var music: AudioStreamPlayer = title.get_node_or_null("TitleMusicPlayer")
	_expect(music != null and music.playing, "放了音樂就會自動播放")
	_expect(music != null and music.bus == &"Music", "標題音樂走 Music 匯流排（設定裡的「音樂」管得到）")
	await get_tree().create_timer(1.2).timeout
	_expect(music != null and music.playing, "播完會從頭再播")
	title.queue_free()
	await get_tree().process_frame


func _test_sound_settings() -> void:
	print("--- 音量存檔 ---")
	var save_path: String = SoundSettings.SAVE_PATH
	var backup: String = FileAccess.get_file_as_string(save_path) if FileAccess.file_exists(save_path) else ""

	SoundSettings.set_volume("Music", 0.4)
	SoundSettings.set_volume("SFX", 0.0)
	await get_tree().create_timer(SoundSettings.SAVE_DELAY + 0.2).timeout
	_expect(FileAccess.file_exists(save_path), "調整後有存檔")
	_expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "音效拉到 0 是靜音")

	# 模擬重新開遊戲：先把音量改回 1，再讓一個新的 SoundSettings 讀檔
	for bus_name: String in ["Music", "SFX"]:
		var index: int = AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_mute(index, false)
		AudioServer.set_bus_volume_db(index, 0.0)
	var reloaded: Node = (SoundSettings.get_script() as GDScript).new()
	add_child(reloaded)
	_expect(is_equal_approx(SoundSettings.get_volume("Music"), 0.4), "重新讀檔後音樂是 0.4")
	_expect(is_equal_approx(SoundSettings.get_volume("SFX"), 0.0), "重新讀檔後音效是 0（靜音）")
	reloaded.queue_free()

	var title: Control = TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	_expect(is_equal_approx((title.get_node("%MusicSlider") as HSlider).value, 0.4), "設定面板的音樂滑桿在 0.4")
	(title.get_node("%MusicSlider") as HSlider).value = 0.8
	_expect(is_equal_approx(SoundSettings.get_volume("Music"), 0.8), "拖滑桿會改變音量")
	title.queue_free()
	await get_tree().process_frame

	# 還原：音量回到 1，存檔回到測試前的內容
	SoundSettings.set_volume("Music", 1.0)
	SoundSettings.set_volume("SFX", 1.0)
	await get_tree().create_timer(SoundSettings.SAVE_DELAY + 0.2).timeout
	if backup == "":
		DirAccess.remove_absolute(save_path)
	else:
		var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
		file.store_string(backup)
		file.close()


## 用一個假的「遊戲場景」放暫停選單：裡面有一個會一直往上數的計時節點，用來確認暫停時真的停住
func _test_pause_menu() -> void:
	print("--- 暫停選單 ---")
	var game := Node.new()
	game.name = "FakePond"
	var counter := _FrameCounter.new()
	game.add_child(counter)
	var menu: CanvasLayer = PAUSE_MENU_SCENE.instantiate()
	game.add_child(menu)
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	get_tree().current_scene = game
	await get_tree().process_frame

	var menu_panel: Control = menu.get_node("%MenuPanel")
	(menu.get_node("%MenuButton") as Button).pressed.emit()
	_expect(menu_panel.visible and get_tree().paused, "按「選單」打開選單，遊戲暫停")
	var frames_before: int = counter.frames
	for i: int in 5:
		await get_tree().process_frame
	_expect(counter.frames == frames_before, "暫停時遊戲裡的節點停住")
	_expect(menu.can_process(), "暫停時選單本身照常運作")

	(menu.get_node("%ResumeButton") as Button).pressed.emit()
	_expect(not menu_panel.visible and not get_tree().paused, "按「繼續遊戲」關掉選單，解除暫停")
	for i: int in 3:
		await get_tree().process_frame
	_expect(counter.frames > frames_before, "解除暫停後遊戲繼續（對照組）")

	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(menu_panel.visible and get_tree().paused, "按 Esc 也能打開選單")

	(menu.get_node("%TitleButton") as Button).pressed.emit()
	_expect(await _wait_until(func() -> bool: return _current_scene_path() == TITLE_PATH), "按「回到標題」回到標題畫面")
	_expect(not get_tree().paused, "回到標題時已解除暫停")


func _current_scene_path() -> String:
	var scene: Node = get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


func _wait_until(condition: Callable) -> bool:
	var time_left: float = TIMEOUT_SECONDS
	while time_left > 0.0:
		if condition.call():
			return true
		await get_tree().process_frame
		time_left -= get_process_delta_time()
	return false


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1


## 每個畫面數一次，用來確認遊戲有沒有被暫停
class _FrameCounter extends Node:
	var frames: int = 0

	func _process(_delta: float) -> void:
		frames += 1
