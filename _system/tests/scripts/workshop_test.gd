extends Node
## 生物工坊的自動測試：
## 1. 打開：6 個分頁、生物長出來、能力有星星、骨架一直開著
## 2. 拉「節數」滑桿：設計檔和生物都變了，身體不重長（只更新）
## 3. 復原、重做
## 4. 腳分頁「＋」：多一組腳，速度變快
## 5. 預覽等級：生物照長大方式變大，能力跟著變
## 6. 存檔：資料夾名稱不合格不存；合格就存到 my_creature/<資料夾>/design.tres，讀回來一樣；蓋掉別的資料夾要先確認
## 7. 讀範例（塗鴉蛇）再存檔：用到的圖一起複製過去
## 8. 匯入圖片：太大的縮到 512，放進生物的資料夾，掛件顯示這張圖；身體的每一節也可以放圖、存讀檔還在、奇怪的檔名擋掉
##    圖加起來超過連線的上限：存檔時多一句「連線對戰時會問你要不要縮小」
## 9. 顏色、粗細形狀的編輯器：簡單模式、加顏色、選內建形狀
## 10. 複雜度上限：顯示「複雜度 x / 上限」；超過上限的滑桿、新增被擋下來，按鈕變灰；本來就超過的只能往下減
## 11. 字的大小：換成中字、大字，字、右邊分頁、名稱欄跟著變；存進設定檔，重開工坊還記得；設定檔亂掉用小字；大字時很長的提示會換行
## 12. 離開工坊：骨架開關回到原本的樣子
##
## 測試會在 my_creature/ 建立 zz_workshop_test 開頭的資料夾，結束時刪掉。
## 工坊的設定檔（user://workshop_settings.cfg）測試前先備份、結束時放回去。
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/workshop_test.tscn

const WORKSHOP_SCENE: PackedScene = preload("res://lesson/workshop/workshop.tscn")
const TEST_FOLDERS: PackedStringArray = ["zz_workshop_test", "zz_workshop_test2"]

var _failures: int = 0
var _workshop: Control
## 測試前的工坊設定檔內容（沒有是空的）
var _old_settings: String = ""


func _ready() -> void:
	_cleanup()
	_backup_settings()
	var debug: Node = get_node("/root/Debug")
	debug.set("show_bones", false)
	_workshop = WORKSHOP_SCENE.instantiate()
	add_child(_workshop)
	await _frames(5)

	_test_open(debug)
	await _test_slider()
	await _test_undo()
	await _test_add_leg()
	await _test_level_preview()
	await _test_save()
	await _test_copy_images()
	await _test_import_image()
	_test_image_size_hint()
	_test_color_and_curve()
	await _test_feed_tab()
	await _test_hide_eyes()
	await _test_complexity()
	await _test_font_size()

	_workshop.queue_free()
	await _frames(2)
	_expect(debug.get("show_bones") == false, "離開工坊：骨架開關回到原本的樣子（關）")
	_cleanup()
	_restore_settings()
	if _failures == 0:
		print("[工坊測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[工坊測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_open(debug: Node) -> void:
	print("--- 打開工坊 ---")
	var tabs: TabContainer = _workshop.get("_tabs")
	_expect(tabs.get_tab_count() == 7, "7 個分頁（%d）" % tabs.get_tab_count())
	_expect(_creature().get_body() != null, "生物長出來了")
	_expect("★" in (_workshop.get("_stats_label") as Label).text, "能力有星星")
	_expect(debug.get("show_bones") == true, "骨架一直開著")


func _test_slider() -> void:
	print("--- 拉滑桿 ---")
	var body: ChainBody = _creature().get_body()
	var slider: HSlider = _slider_of(_workshop.get("_body_editor"), "節數")
	_expect(slider != null, "身體分頁有「節數」滑桿")
	slider.value = 30
	await _frames(2)
	_expect(_design().body.segment_count == 30, "設計檔的節數變成 30")
	_expect(_creature().get_body() == body and body.joint_count() == 30, "生物的身體變成 30 節，沒有重長")


func _test_undo() -> void:
	print("--- 復原、重做 ---")
	_workshop.call("_commit_history")
	_workshop.call("undo")
	await _frames(2)
	_expect(_design().body.segment_count == 24 and _creature().get_body().joint_count() == 24, "復原：回到 24 節")
	_workshop.call("redo")
	await _frames(2)
	_expect(_design().body.segment_count == 30 and _creature().get_body().joint_count() == 30, "重做：又變成 30 節")


func _test_add_leg() -> void:
	print("--- 加腳 ---")
	var speed_before: float = _creature().get_stats().speed
	_workshop.call("_change_list", "legs", "add")
	await _frames(2)
	_expect(_design().legs.size() == 1 and _creature().find_children("*", "IKLeg", true, false).size() == 1, "多一組腳")
	_expect(_creature().get_stats().speed > speed_before and is_equal_approx(_creature().speed, _creature().get_stats().speed), "速度變快，生物用的就是算出來的速度")
	var list: Dictionary = _workshop.get("_lists")["legs"]
	_expect((list.selector as OptionButton).item_count == 1, "腳的選單有 1 項")


func _test_level_preview() -> void:
	print("--- 預覽等級 ---")
	var size_before: float = _creature().get_stats().size
	(_workshop.get("_level_slider") as HSlider).value = 5
	await _frames(2)
	_expect(_creature().level == 5 and _creature().get_stats().size > size_before, "預覽 5 級：體型 %.0f → %.0f" % [size_before, _creature().get_stats().size])
	(_workshop.get("_level_slider") as HSlider).value = 0
	await _frames(1)


func _test_save() -> void:
	print("--- 存檔 ---")
	var folder_edit: LineEdit = _workshop.get("_folder_edit")
	folder_edit.text = "壞 名字"
	_workshop.call("_on_save_pressed")
	_expect(not DirAccess.dir_exists_absolute("res://my_creature/壞 名字") and "只能" in (_workshop.get("_message") as Label).text, "資料夾名稱有空白、中文：不存，顯示提示")

	folder_edit.text = TEST_FOLDERS[0]
	(_workshop.get("_name_edit") as LineEdit).text = "測試蛇"
	_workshop.call("_on_save_pressed")
	var path: String = "res://my_creature/%s/design.tres" % TEST_FOLDERS[0]
	_expect(FileAccess.file_exists(path), "存到 %s" % path)
	var loaded: CreatureDesign = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(loaded != null and loaded.creature_name == "測試蛇" and loaded.to_dict() == _design().to_dict(), "讀回來跟工坊裡的一樣")
	var paths: PackedStringArray = _workshop.get("_load_paths")
	_expect(path in paths, "讀取選單多了這隻")

	# 讀一隻範例，存到已經有生物的資料夾：要先確認
	_workshop.call("_load_design", "res://example/creatures/spider/design.tres")
	folder_edit.text = TEST_FOLDERS[0]
	_workshop.call("_on_save_pressed")
	var confirm: ConfirmationDialog = _workshop.get("_confirm")
	_expect(confirm.visible, "資料夾已經有別的生物：跳出確認")
	_expect((ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CreatureDesign).creature_name == "測試蛇", "還沒確認：檔案沒被蓋掉")
	confirm.hide()
	await _frames(1)


func _test_copy_images() -> void:
	print("--- 範例的圖跟著複製 ---")
	_workshop.call("_load_design", "res://example/creatures/doodle/design.tres")
	(_workshop.get("_folder_edit") as LineEdit).text = TEST_FOLDERS[1]
	_workshop.call("_on_save_pressed")
	var folder: String = "res://my_creature/%s/" % TEST_FOLDERS[1]
	_expect(FileAccess.file_exists(folder + "doodle_head.png"), "doodle_head.png 複製到 %s" % folder)
	var loaded: CreatureDesign = ResourceLoader.load(folder + "design.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(loaded != null and loaded.load_image("doodle_head.png") != null, "新的設計檔讀得到自己資料夾裡的圖")


func _test_import_image() -> void:
	print("--- 匯入圖片 ---")
	var source: String = ProjectSettings.globalize_path("user://workshop_test_big.png")
	var image := Image.create(800, 400, false, Image.FORMAT_RGBA8)
	image.fill(Color.ORANGE)
	image.save_png(source)
	_workshop.call("_change_list", "ornaments", "add")
	var part: OrnamentDesign = _design().ornaments[-1]
	_workshop.call("import_image", source, part)
	await _frames(2)
	var saved: String = "res://my_creature/%s/workshop_test_big.png" % TEST_FOLDERS[1]
	_expect(FileAccess.file_exists(saved), "圖放進生物的資料夾")
	var saved_image: Image = Image.load_from_file(saved)
	_expect(saved_image != null and saved_image.get_width() == 512 and saved_image.get_height() == 256, "800×400 縮成 512×256")
	_expect(part.image_file == "workshop_test_big.png" and part.shape == Ornament.Shape.NONE, "掛件改成顯示這張圖")
	var sprites: Array[Node] = _creature().find_children("Image", "Sprite2D", true, false)
	var has_texture: bool = false
	for sprite: Node in sprites:
		has_texture = has_texture or ((sprite as Sprite2D).texture != null and (sprite as Sprite2D).texture.get_width() == 512)
	_expect(has_texture, "生物身上看得到這張圖")
	_expect(_workshop.call("_safe_image_name", "我的 頭.PNG").begins_with("image_") and _workshop.call("_safe_image_name", "Head-1.png") == "head-1.png", "中文、空白的檔名換成英文名字")
	DirAccess.remove_absolute(source)

	print("--- 身體的圖 ---")
	var bead: String = ProjectSettings.globalize_path("user://workshop_test_bead_with_a_very_long_file_name_1234567890.png")
	var bead_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	bead_image.fill(Color.SKY_BLUE)
	bead_image.save_png(bead)
	_workshop.call("import_image", bead, _design().body, "segment_image")
	await _frames(2)
	var body: ChainBody = _creature().get_body()
	var bead_name: String = _design().body.segment_image
	_expect(bead_name.begins_with("workshop_test_bead") and bead_name.length() <= 36, "身體的「每一節的圖」改成這張；檔名太長剪短（%s）" % bead_name)
	_expect(FileAccess.file_exists("res://my_creature/%s/%s" % [TEST_FOLDERS[1], bead_name]), "圖放進生物的資料夾")
	_expect(body.segment_texture != null and body.segment_texture.get_width() == 32 and body.head_texture == null, "身體讀到每一節的圖（頭沒有另外放圖）")
	var row_has_file: bool = false
	for label: Node in (_workshop.get("_body_editor") as Node).find_children("*", "Label", true, false):
		row_has_file = row_has_file or (label as Label).text == bead_name
	_expect(row_has_file, "身體分頁顯示圖的檔名")
	_design().body.head_image_scale = 2.0
	_design().body.segment_image_scale = 0.5
	_workshop.call("_on_design_changed")
	body = _creature().get_body()
	_expect(body.head_image_scale == 2.0 and body.segment_image_scale == 0.5 and body.tail_image_scale == 1.0, "頭、每一節、尾巴的圖大小各調各的")
	var size_rows: int = 0
	for label: Node in (_workshop.get("_body_editor") as Node).find_children("*", "Label", true, false):
		if (label as Label).text in ["頭的圖大小", "每一節的圖大小", "尾巴的圖大小"]:
			size_rows += 1
	_expect(size_rows == 3, "身體分頁有三個「圖大小」的滑桿（%d 個）" % size_rows)
	_design().body.draw_body = false
	_workshop.call("_on_design_changed")
	_expect(not _creature().get_body().draw_body, "取消「也畫身體」：只畫圖")
	_workshop.call("_on_save_pressed")
	var reloaded: CreatureDesign = ResourceLoader.load("res://my_creature/%s/design.tres" % TEST_FOLDERS[1], "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(reloaded != null and reloaded.body.segment_image == bead_name and reloaded.load_image(bead_name) != null, "存檔再讀回來：身體的圖還在")
	_workshop.call("_load_design", "res://my_creature/%s/design.tres" % TEST_FOLDERS[1])
	await _frames(2)
	_expect(_creature().get_body().segment_texture != null, "用工坊的「讀取」重開：身上還看得到圖")
	var hacked: CreatureDesign = CreatureDesign.from_data({"body": {"head_image": "../../secret.png", "tail_image": "evil.exe"}})
	_expect(hacked.body.head_image == "secret.png" and hacked.body.tail_image == "", "收到奇怪的檔名：只留檔名本身、不是 PNG 就不要")
	_design().body.segment_image = ""
	_design().body.draw_body = true
	_workshop.call("_on_design_changed")
	_expect(_creature().get_body().segment_texture == null, "拿掉圖：身體也不畫圖了")
	DirAccess.remove_absolute(bead)


func _test_image_size_hint() -> void:
	print("--- 圖比較大的提醒 ---")
	var label: Label = _workshop.get("_message") as Label
	_workshop.call("_on_save_pressed")
	_expect(not "連線對戰" in label.text, "圖不大：存檔時不提醒")
	var folder: String = "res://my_creature/%s/" % TEST_FOLDERS[1]
	var noise := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y: int in 512:
		for x: int in 512:
			noise.set_pixel(x, y, Color(randf(), randf(), randf(), 1.0))  # 雜訊 PNG 壓不小，一張快 1 MB
	noise.save_png(folder + "zz_noise_a.png")
	noise.save_png(folder + "zz_noise_b.png")
	_design().ornaments[-1].image_file = "zz_noise_a.png"
	_design().body.tail_image = "zz_noise_b.png"
	_workshop.call("_on_save_pressed")
	_expect("連線對戰時會問你要不要縮小" in label.text and "原圖不會被改到" in label.text, "圖加起來超過 1 MB：存檔時提醒")
	_design().ornaments[-1].image_file = "workshop_test_big.png"
	_design().body.tail_image = ""
	_workshop.call("_on_design_changed")


func _test_color_and_curve() -> void:
	print("--- 顏色、粗細形狀 ---")
	var gradient := Gradient.new()
	var colors := GradientEditor.new()
	add_child(colors)
	colors.edit(gradient, "頭", "尾巴")
	colors.call("_set_simple", Color.RED, Color.BLUE)
	_expect(gradient.get_point_count() == 2 and gradient.sample(0.0).is_equal_approx(Color.RED) and gradient.sample(1.0).is_equal_approx(Color.BLUE), "簡單模式：頭紅、尾巴藍")
	var offsets: PackedFloat32Array = colors.get("_offsets")
	offsets.append(0.5)
	var color_list: PackedColorArray = colors.get("_colors")
	color_list.append(Color.GREEN)
	colors.set("_offsets", offsets)
	colors.set("_colors", color_list)
	colors.call("_apply")
	_expect(gradient.get_point_count() == 3 and gradient.sample(0.5).is_equal_approx(Color.GREEN), "進階：中間加一個綠色")
	colors.queue_free()

	var curve := Curve.new()
	var shapes := CurveEditor.new()
	add_child(shapes)
	shapes.edit(curve)
	var preset: OptionButton = shapes.get("_preset")
	for i: int in preset.item_count:
		if preset.get_item_text(i) == "平均":
			preset.select(i)
			preset.item_selected.emit(i)
	_expect(curve.point_count == 2 and is_equal_approx(curve.sample(0.5), 1.0), "選「平均」：粗細全部一樣")
	shapes.queue_free()


func _test_complexity() -> void:
	print("--- 複雜度上限 ---")
	_workshop.call("_load_design", "res://example/creatures/octopus/design.tres")
	await _frames(2)
	var limit: int = _workshop.call("max_complexity")
	var start: int = _workshop.call("design_complexity")
	var label: Label = _workshop.get("_stats_label")
	_expect(("複雜度 %d / %d" % [start, limit]) in label.text, "顯示「複雜度 %d / %d」" % [start, limit])
	var slider: HSlider = _slider_of(_workshop.get("_body_editor"), "節數")
	var segments: int = _design().body.segment_count
	slider.value = segments + (limit - start) + 5
	await _frames(1)
	_expect(_design().body.segment_count == segments and int(slider.value) == segments, "節數拉到超過上限：擋下來，滑桿退回 %d" % segments)
	_expect("超過上限" in (_workshop.get("_message") as Label).text, "說明為什麼不能改")
	slider.value = segments + 2
	await _frames(1)
	_expect(_design().body.segment_count == segments + 2, "沒超過上限的改動照常（%d 節）" % (segments + 2))
	var tentacles: Dictionary = _workshop.get("_lists")["tentacles"]
	var tentacle_count: int = _design().tentacles.size()
	_expect((tentacles.add as Button).disabled and "超過上限" in (tentacles.add as Button).tooltip_text, "觸手「＋」加了會超過上限：變灰、說明原因")
	_expect(not ((_workshop.get("_lists")["eyes"].add) as Button).disabled, "眼睛「＋」加了還在上限內：可以按")
	_workshop.call("_change_list", "tentacles", "add")
	await _frames(1)
	_expect(_design().tentacles.size() == tentacle_count and _workshop.call("design_complexity") <= limit, "硬按觸手「＋」也加不進去")

	var heavy: CreatureDesign = CreatureDesign.from_data(_design().to_dict())
	heavy.body.segment_count = 60
	_workshop.call("use_design", heavy, "", "")
	await _frames(2)
	_expect("超過上限" in (_workshop.get("_message") as Label).text, "讀到超過上限的設計檔：提示要減少零件")
	slider = _slider_of(_workshop.get("_body_editor"), "節數")
	slider.value = 50
	await _frames(1)
	_expect(_design().body.segment_count == 50, "本來就超過上限：往下減可以（60 → 50 節）")
	slider.value = 55
	await _frames(1)
	_expect(_design().body.segment_count == 50, "本來就超過上限：再加回去不行")


# ---------------------------------------------------------------- 工具


func _test_font_size() -> void:
	print("--- 字的大小 ---")
	var panel: PanelContainer = _workshop.get("_side_panel")
	var body_editor: PartEditor = _workshop.get("_body_editor")
	_expect(_workshop.theme.default_font_size == 11 and is_equal_approx(panel.custom_minimum_size.x, 320.0), "一開始是小字，右邊分頁 320（%d）" % panel.custom_minimum_size.x)
	var small_name: float = _name_width(body_editor)
	_workshop.call("set_font_size", 16)
	await _frames(2)
	_expect(_workshop.theme.default_font_size == 16 and panel.custom_minimum_size.x > 320.0 and panel.custom_minimum_size.x < 500.0, "換成中字：字是 16，右邊分頁在中間（%d）" % panel.custom_minimum_size.x)
	_workshop.call("set_font_size", 22)
	await _frames(2)
	body_editor = _workshop.get("_body_editor")
	_expect(_workshop.theme.default_font_size == 22, "換成大字：字是 22")
	_expect(is_equal_approx(panel.custom_minimum_size.x, 500.0), "右邊分頁變成 500（%d）" % panel.custom_minimum_size.x)
	_expect(_name_width(body_editor) > small_name, "名稱欄變寬（%d → %d）" % [small_name, _name_width(body_editor)])
	_workshop.call("set_font_size", 15)
	_expect(_workshop.theme.default_font_size == 22, "不在選項裡（15）：不理它")
	var message: Label = _workshop.get("_message")
	message.text = "這是一段很長很長的提示文字，大字的時候一行放不下，要換到下一行才看得完，不能被截掉"
	await _frames(2)
	_expect(message.get_line_count() >= 2 and message.size.x <= (_workshop.get_parent_area_size().x as float), "大字時很長的提示會換行（%d 行）" % message.get_line_count())
	var config := ConfigFile.new()
	_expect(config.load(WorkshopSettings.SAVE_PATH) == OK and config.get_value("workshop", "font_size") == 22, "存進設定檔")

	# 重開工坊：還是大字
	_workshop.queue_free()
	await _frames(2)
	WorkshopSettings.font_size = 11
	_workshop = WORKSHOP_SCENE.instantiate()
	add_child(_workshop)
	await _frames(3)
	_expect(_workshop.theme.default_font_size == 22, "重開工坊還記得大字")

	# 設定檔被亂改：用小字
	config.set_value("workshop", "font_size", "很大")
	config.save(WorkshopSettings.SAVE_PATH)
	WorkshopSettings.load_settings()
	_expect(WorkshopSettings.font_size == 11, "設定檔亂掉：用小字")
	_workshop.call("set_font_size", 11)


func _name_width(editor: PartEditor) -> float:
	for row: Node in editor.get_children():
		if row is HBoxContainer and row.get_child(0) is Label:
			return (row.get_child(0) as Label).custom_minimum_size.x
	return 0.0


func _backup_settings() -> void:
	if FileAccess.file_exists(WorkshopSettings.SAVE_PATH):
		_old_settings = FileAccess.get_file_as_string(WorkshopSettings.SAVE_PATH)
	DirAccess.remove_absolute(WorkshopSettings.SAVE_PATH)
	WorkshopSettings.font_size = WorkshopSettings.BASE_FONT_SIZE


func _restore_settings() -> void:
	DirAccess.remove_absolute(WorkshopSettings.SAVE_PATH)
	if _old_settings != "":
		var file := FileAccess.open(WorkshopSettings.SAVE_PATH, FileAccess.WRITE)
		file.store_string(_old_settings)


func _design() -> CreatureDesign:
	return _workshop.get("design")


func _creature() -> Creature:
	return _workshop.get("_creature")


## 零件編輯區裡某個名稱那一列的滑桿
## 「飼料」分頁：只有飼料的三個欄位（「長大」分頁沒有），改了設計檔跟著改
func _test_feed_tab() -> void:
	print("--- 飼料分頁 ---")
	var tabs: TabContainer = _workshop.get("_tabs")
	_expect(tabs.get_tab_title(tabs.get_tab_count() - 1) == "飼料", "最後一個分頁是「飼料」")
	var feed: Node = _workshop.get("_feed_editor")
	var growth: Node = _workshop.get("_growth_editor")
	var missing: PackedStringArray = []
	for label: String in ["飼料顏色", "飼料形狀", "飼料大小", "飼料角度", "星星角數", "星星胖瘦", "外框", "外框顏色", "外框寬度", "光暈", "光暈顏色", "光暈大小", "光暈呼吸", "亮點", "亮點顏色"]:
		if _row_of(feed, label) == null:
			missing.append(label)
	_expect(missing.is_empty(), "飼料分頁每個欄位都有中文名稱和控制項（缺 %s）" % ", ".join(missing))
	_expect(_row_of(feed, "長大方式") == null and _row_of(growth, "飼料形狀") == null and _row_of(growth, "長大方式") != null, "飼料、長大各管各的欄位")
	var design: CreatureDesign = _workshop.get("design")
	var option: OptionButton = _row_of(feed, "飼料形狀").find_children("*", "OptionButton", true, false)[0]
	option.select(Food.Shape.HEART)
	option.item_selected.emit(Food.Shape.HEART)
	var check: CheckBox = _row_of(feed, "光暈").find_children("*", "CheckBox", true, false)[0]
	check.button_pressed = false
	await _frames(1)
	_expect(design.spray_shape == Food.Shape.HEART and not design.spray_glow, "選愛心、關掉光暈：設計檔跟著改")
	var spray_button: Button = null
	for button: Node in feed.get_parent().find_children("*", "Button", false, false):
		if (button as Button).text == "噴一下看看":
			spray_button = button
	_expect(spray_button != null, "有「噴一下看看」按鈕")
	var stage: SubViewport = _workshop.get("_stage")
	spray_button.pressed.emit()
	await get_tree().create_timer(1.0).timeout
	var sprayed: Array[Node] = stage.find_children("*", "Food", false, false)
	_expect(sprayed.size() == _workshop.SPRAY_BURST, "按一下：從尾巴噴出 %d 顆（%d）" % [_workshop.SPRAY_BURST, sprayed.size()])
	_expect(sprayed.all(func(food: Node) -> bool: return (food as Food).look == design and not (food as Food).edible and not food.is_in_group("food")), "噴出來的照設計檔畫，只給人看、不能吃")
	await get_tree().create_timer(_workshop.SPRAY_LIFE).timeout
	_expect(stage.find_children("*", "Food", false, false).is_empty(), "過幾秒就消失")


## 眼睛的「顯示」：關掉時選單上寫「藏起來」，沒有自己的圖就提醒
func _test_hide_eyes() -> void:
	print("--- 藏眼睛 ---")
	var design: CreatureDesign = _workshop.get("design")
	if design.eyes.is_empty():
		design.eyes.append(EyesDesign.new())
		_workshop.call("_rebuild_editors")
	var list: Dictionary = (_workshop.get("_lists") as Dictionary)["eyes"]
	var editor: Node = list.editor
	var row: Node = _row_of(editor, "顯示")
	_expect(row != null, "眼睛的設定有「顯示」")
	var check: CheckBox = row.find_children("*", "CheckBox", true, false)[0]
	check.button_pressed = false
	await _frames(1)
	_expect(not design.eyes[list.selected].visible, "取消勾選：設計檔的眼睛藏起來")
	_expect("藏起來" in (list.selector as OptionButton).get_item_text(list.selected), "選單上寫「藏起來」")
	var message: Label = _workshop.get("_message")
	_expect(design.has_own_image() or "沒有自己畫的圖" in message.text, "沒有自己的圖：提醒看起來會沒有眼睛")
	check.button_pressed = true
	await _frames(1)
	_expect(design.eyes[list.selected].visible and not "藏起來" in (list.selector as OptionButton).get_item_text(list.selected), "再勾回來：顯示")
	_expect(not "沒有自己畫的圖" in message.text, "再勾回來：提醒收掉")


## 編輯區裡名稱是 label_text 的那一排（找不到是 null）
func _row_of(editor: Node, label_text: String) -> Node:
	for row: Node in editor.get_children():
		if row is HBoxContainer and row.get_child_count() >= 2 and row.get_child(0) is Label and (row.get_child(0) as Label).text == label_text:
			return row
	return null


func _slider_of(editor: Node, label_text: String) -> HSlider:
	for row: Node in editor.get_children():
		if row is HBoxContainer and row.get_child_count() >= 2 and row.get_child(0) is Label and (row.get_child(0) as Label).text == label_text:
			var sliders: Array[Node] = row.find_children("*", "HSlider", true, false)
			return sliders[0] as HSlider if not sliders.is_empty() else null
	return null


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


## 刪掉測試建立的資料夾
func _cleanup() -> void:
	for folder: String in TEST_FOLDERS:
		var path: String = "res://my_creature/" + folder
		if not DirAccess.dir_exists_absolute(path):
			continue
		for file: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file))
		DirAccess.remove_absolute(path)


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
