extends Node
## 生物工坊的自動測試：
## 1. 打開：6 個分頁、生物長出來、能力有星星、骨架一直開著
## 2. 拉「節數」滑桿：設計檔和生物都變了，身體不重長（只更新）
## 3. 復原、重做
## 4. 腳分頁「＋」：多一組腳，速度變快
## 5. 預覽等級：生物照長大方式變大，能力跟著變
## 6. 存檔：資料夾名稱不合格不存；合格就存到 my_creature/<資料夾>/design.tres，讀回來一樣；蓋掉別的資料夾要先確認
## 7. 讀範例（塗鴉蛇）再存檔：用到的圖一起複製過去
## 8. 匯入圖片：太大的縮到 512，放進生物的資料夾，掛件顯示這張圖
## 9. 顏色、粗細形狀的編輯器：簡單模式、加顏色、選內建形狀
## 10. 離開工坊：骨架開關回到原本的樣子
##
## 測試會在 my_creature/ 建立 zz_workshop_test 開頭的資料夾，結束時刪掉。
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/workshop_test.tscn

const WORKSHOP_SCENE: PackedScene = preload("res://lesson/workshop/workshop.tscn")
const TEST_FOLDERS: PackedStringArray = ["zz_workshop_test", "zz_workshop_test2"]

var _failures: int = 0
var _workshop: Control


func _ready() -> void:
	_cleanup()
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
	_test_color_and_curve()

	_workshop.queue_free()
	await _frames(2)
	_expect(debug.get("show_bones") == false, "離開工坊：骨架開關回到原本的樣子（關）")
	_cleanup()
	if _failures == 0:
		print("[工坊測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[工坊測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_open(debug: Node) -> void:
	print("--- 打開工坊 ---")
	var tabs: TabContainer = _workshop.get("_tabs")
	_expect(tabs.get_tab_count() == 6, "6 個分頁（%d）" % tabs.get_tab_count())
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


# ---------------------------------------------------------------- 工具


func _design() -> CreatureDesign:
	return _workshop.get("design")


func _creature() -> Creature:
	return _workshop.get("_creature")


## 零件編輯區裡某個名稱那一列的滑桿
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
