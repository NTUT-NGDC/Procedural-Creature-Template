extends Node
## 標題畫面、音量設定、暫停選單的自動測試：
## 1. 玩家生物沒設定、生態缸場景找不到 → 顯示提示，不會換場景
## 2. 設定面板可以打開、關閉；電腦版看得到「離開遊戲」；標題音樂會自動播放、播完重播
## 3. 音量：調整後會存檔，重新讀取後音量和滑桿位置都對；拉到 0 是靜音
## 4. 暫停選單：打開時遊戲暫停、選單照常運作；繼續後解除暫停；按 Esc 也能打開；回到標題時已解除暫停
## 5. 背景：玩家生物用「漫遊」在按鈕後面游；沒設定玩家生物時不顯示、不會當掉
## 5.5 換生物：「＜」「＞」換、背景跟著換、繞一圈、回標題還記得、可以關掉
## 6. 完整流程跑兩輪：標題 → 開始 → 生態缸（玩家生物就是標題設定的那隻）→ 吃東西升級 → 暫停選單回標題
## 7. 連線對戰：標題選塗鴉蛇 → 連線畫面（預覽、圖多大）→ 開主機 → 離開 → 回標題（連線本身在 battle_test 測）
##
##
## 測試會暫時改掉 user://sound_settings.cfg，結束時還原。
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/title_screen_test.tscn

const TITLE_SCENE: PackedScene = preload("res://game/title_screen/title_screen.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://game/pause_menu/pause_menu.tscn")
const TITLE_PATH: String = "res://game/title_screen/title_screen.tscn"
const TANK_PATH: String = "res://game/tank/tank.tscn"
const LOBBY_PATH: String = "res://lesson/battle/battle_lobby.tscn"
const BATTLE_PATH: String = "res://lesson/battle/online_battle.tscn"
const SNAKE_DESIGN: String = "res://example/creatures/snake/design.tres"
const TIMEOUT_SECONDS: float = 10.0

var _failures: int = 0


func _ready() -> void:
	await _test_problem("player_design", null, "還沒有設定玩家生物")
	await _test_problem("tank_scene", "res://my_creature/不存在的場景.tscn", "找不到生態缸場景")
	await _test_problem("tank_scene", "res://lesson/card_draw/data/card_deck.tres", "找不到生態缸場景")
	await _test_settings_panel()
	await _test_title_music()
	await _test_sound_settings()
	await _test_pause_menu()
	await _test_background_creature()
	await _test_choose()
	await _test_full_flow()
	await _test_battle_flow()

	if _failures == 0:
		print("[標題畫面測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[標題畫面測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_problem(property: String, value: Variant, expected_text: String) -> void:
	print("--- %s 設成「%s」 ---" % [property, value])
	var title: Control = TITLE_SCENE.instantiate()
	title.set(property, value)
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
	game.name = "FakeGame"
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


func _test_background_creature() -> void:
	print("--- 背景的生物 ---")
	get_tree().paused = false
	var title: Control = TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	var creature: Creature = title.get_node_or_null("BackgroundCreature") as Creature
	_expect(creature != null, "背景有一隻生物（玩家生物）")
	_expect(creature != null and creature.design != null and creature.design.resource_path == SNAKE_DESIGN, "是標題畫面設定的蛇（設計檔）")
	_expect(creature != null and creature.control_mode == Creature.Mode.WANDER and not creature.is_in_group("player"), "用「漫遊」游，不算玩家")
	_expect(creature != null and creature.get_index() < (title.get_node("Margin") as Control).get_index(), "在按鈕的下面")
	var start: Vector2 = creature.global_position if creature != null else Vector2.ZERO
	for i: int in 30:
		await get_tree().process_frame
	_expect(creature != null and creature.global_position != start, "會游來游去")
	title.queue_free()
	await get_tree().process_frame

	title = TITLE_SCENE.instantiate()
	title.set("player_design", null)
	add_child(title)
	await get_tree().process_frame
	_expect(title.get_node_or_null("BackgroundCreature") == null, "沒設定玩家生物：不顯示背景生物、不會當掉")
	title.queue_free()
	await get_tree().process_frame


## 用真正的換場景流程跑：把標題畫面設成目前的場景，這個測試節點留在旁邊不會被換掉
func _test_full_flow() -> void:
	print("--- 標題 → 生態缸 → 回標題，跑兩輪 ---")
	get_tree().paused = false
	var title: Control = TITLE_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(title)
	await get_tree().process_frame
	get_tree().current_scene = title

	for round_number: int in [1, 2]:
		(get_tree().current_scene.get_node("%StartButton") as Button).pressed.emit()
		_expect(await _wait_until(func() -> bool: return _current_scene_path() == TANK_PATH), "第 %d 輪：按開始換到生態缸" % round_number)
		var tank: Tank = get_tree().current_scene as Tank
		await get_tree().process_frame
		_expect(tank.player != null and tank.player.design != null and tank.player.design.resource_path == SNAKE_DESIGN, "第 %d 輪：生態缸裡是標題畫面設定的蛇" % round_number)
		# 吃滿一級
		var cost: int = tank.player.get_stats().level_cost
		for i: int in cost:
			tank.drop_food(tank.player.global_position)
		for i: int in 3:
			await get_tree().process_frame
		_expect(tank.player.level == 1, "第 %d 輪：吃 %d 個升到 1 級" % [round_number, cost])
		(tank.get_node("PauseMenu/%MenuButton") as Button).pressed.emit()
		(tank.get_node("PauseMenu/%TitleButton") as Button).pressed.emit()
		_expect(await _wait_until(func() -> bool: return _current_scene_path() == TITLE_PATH), "第 %d 輪：從暫停選單回到標題畫面" % round_number)
		_expect(not get_tree().paused and WaterFlow.strength == 0.0, "第 %d 輪：回到標題時已解除暫停、水流歸零" % round_number)


## 在標題畫面按「＞」，換到名稱是 creature_name 的生物（找不到的話測試失敗）
func _choose_by_name(title: Node, creature_name: String) -> void:
	for i: int in 30:
		if (title.get_node("%ChoiceName") as Label).text == creature_name:
			return
		(title.get_node("%NextButton") as Button).pressed.emit()
	_expect(false, "標題畫面選得到「%s」" % creature_name)


## 換生物：「＜」「＞」換生物、背景跟著換、會繞一圈、記得上次選的、可以關掉
func _test_choose() -> void:
	print("--- 標題畫面換生物 ---")
	var script: GDScript = load("res://game/title_screen/scripts/title_screen.gd")
	script.set("chosen_path", "")
	var snake: CreatureDesign = load(SNAKE_DESIGN)
	var spider_name: String = (load("res://example/creatures/spider/design.tres") as CreatureDesign).creature_name
	var title: Control = TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	var row: Control = title.get_node("%ChooseRow")
	var choice_name: Label = title.get_node("%ChoiceName")
	var choices: Array = title.get("_choices")
	_expect(row.visible and choices.size() >= 8, "看得到「＜　生物名稱　＞」，可以選 %d 隻" % choices.size())
	_expect(title.get("player_design") == snake and choice_name.text == snake.creature_name and "範例生物" in (title.get_node("%ChoiceGroup") as Label).text, "一開始選的是檢查器設定的蛇")
	(title.get_node("%NextButton") as Button).pressed.emit()
	var background: Creature = title.get_node("BackgroundCreature")
	_expect(title.get("player_design") != snake and choice_name.text != snake.creature_name, "按「＞」換成下一隻")
	_expect(background.design == title.get("player_design"), "背景的生物跟著換")
	for i: int in choices.size() - 1:
		(title.get_node("%NextButton") as Button).pressed.emit()
	_expect(title.get("player_design") == snake, "按一圈回到蛇")
	(title.get_node("%PrevButton") as Button).pressed.emit()
	(title.get_node("%NextButton") as Button).pressed.emit()
	_expect(title.get("player_design") == snake, "「＜」再「＞」回到原本那隻（第一隻往前會繞到最後一隻）")
	await _choose_by_name(title, spider_name)
	title.queue_free()
	await get_tree().process_frame

	title = TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	_expect((title.get_node("%ChoiceName") as Label).text == spider_name and (title.get("player_design") as CreatureDesign).creature_name == spider_name, "回到標題畫面：還記得上次選的蜘蛛")
	title.queue_free()
	await get_tree().process_frame

	title = TITLE_SCENE.instantiate()
	title.set("allow_choose", false)
	add_child(title)
	await get_tree().process_frame
	_expect(not (title.get_node("%ChooseRow") as Control).visible and title.get("player_design") == snake, "關掉「讓玩家換生物」：看不到選擇那排，主角固定是檢查器設定的蛇")
	title.queue_free()
	await get_tree().process_frame

	title = TITLE_SCENE.instantiate()
	title.set("player_design", null)
	add_child(title)
	await get_tree().process_frame
	_expect(not (title.get_node("%ChooseRow") as Control).visible, "沒設定玩家生物：看不到選擇那排（照原本的提示設定）")
	title.queue_free()
	await get_tree().process_frame
	script.set("chosen_path", "")  # 後面的測試用回蛇


## 連線對戰的換場景流程（接在 _test_full_flow 後面，目前的場景是標題畫面）：
## 標題 → 連線畫面（帶著標題的生物）→ 沒填 IP 不能加入 → 返回標題；
## 標題 → 連線畫面 → 開主機 → 對戰的「離開」回連線畫面 → 開主機 → 暫停選單回標題
func _test_battle_flow() -> void:
	print("--- 連線對戰：換場景 ---")
	var title: Node = get_tree().current_scene
	var doodle_name: String = (load("res://example/creatures/doodle/design.tres") as CreatureDesign).creature_name
	await _choose_by_name(title, doodle_name)
	var battle_button: Button = title.get_node("%BattleButton")
	_expect(battle_button.visible, "電腦版看得到「連線對戰」")
	battle_button.pressed.emit()
	_expect(await _wait_until(func() -> bool: return _current_scene_path() == LOBBY_PATH), "按「連線對戰」換到連線畫面")
	var lobby: Node = get_tree().current_scene
	var lobby_design: CreatureDesign = lobby.get("player_design")
	_expect(lobby_design != null and lobby_design.creature_name == doodle_name, "帶著標題畫面選的塗鴉蛇")
	var preview: Creature = lobby.get("_preview")
	_expect(preview != null and preview.design == lobby_design and (lobby.get_node("%CreatureName") as Label).text == doodle_name, "預覽框裡游的、寫的名稱都是選好的生物")
	_expect("自己的圖" in (lobby.get_node("%CreatureInfo") as Label).text and not BattlePacket.read_images(lobby_design).is_empty(), "有自己的圖：說明寫圖有多大，也讀得到圖")
	(lobby.get_node("%AddressEdit") as LineEdit).text = ""
	(lobby.get_node("%JoinButton") as Button).pressed.emit()
	_expect("請填主機的 IP" in (lobby.get_node("%MessageLabel") as Label).text and _current_scene_path() == LOBBY_PATH, "沒填 IP：顯示提示，不換場景")
	(lobby.get_node("%BackButton") as Button).pressed.emit()
	_expect(await _wait_until(func() -> bool: return _current_scene_path() == TITLE_PATH), "按「返回」回到標題")

	(get_tree().current_scene.get_node("%BattleButton") as Button).pressed.emit()
	await _wait_until(func() -> bool: return _current_scene_path() == LOBBY_PATH)
	(get_tree().current_scene.get_node("%HostButton") as Button).pressed.emit()
	_expect(await _wait_until(func() -> bool: return _current_scene_path() == BATTLE_PATH), "按「開主機」換到對戰")
	await get_tree().process_frame
	var battle: Node = get_tree().current_scene
	var host_bar: Control = battle.get_node("BattleHud/%HostBar")
	_expect(host_bar.visible and (battle.get("tank") as Tank).player != null, "主機：自己的生物在缸裡，看得到「開始對戰」那一排")
	(battle.get_node("BattleHud/%LeaveButton") as Button).pressed.emit()
	_expect(await _wait_until(func() -> bool: return _current_scene_path() == LOBBY_PATH), "按「離開」回到連線畫面")
	_expect(get_tree().current_scene.get("player_design") != null and (get_tree().current_scene.get("player_design") as CreatureDesign).creature_name == doodle_name, "回到連線畫面：還是選好的塗鴉蛇")
	(get_tree().current_scene.get_node("%HostButton") as Button).pressed.emit()
	await _wait_until(func() -> bool: return _current_scene_path() == BATTLE_PATH)
	await get_tree().process_frame
	battle = get_tree().current_scene
	var tank: Tank = battle.get("tank")
	(tank.get_node("PauseMenu/%MenuButton") as Button).pressed.emit()
	(tank.get_node("PauseMenu/%TitleButton") as Button).pressed.emit()
	_expect(await _wait_until(func() -> bool: return _current_scene_path() == TITLE_PATH), "對戰中從暫停選單回到標題")
	_expect(not get_tree().paused and WaterFlow.strength == 0.0, "回到標題時已解除暫停、水流歸零")
