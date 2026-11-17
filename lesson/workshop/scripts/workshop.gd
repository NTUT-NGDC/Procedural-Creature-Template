extends Control
## 生物工坊：用滑桿、按鈕、選色器組一隻自己的生物，存成設計檔（my_creature/<資料夾>/design.tres）。
## 同時是「實驗室」：骨架一直開著，滑桿可以拉到極端值把生物弄壞，看規則在做什麼，再按「復原」拉回來。
##
## 左邊是水族箱（生物跟著滑鼠游）、左下是能力和代價、右邊是各零件的分頁。
## 複雜度（零件越多越高）有上限（平衡資料的 max_complexity）：超過上限的改動會被擋下來。
## 右邊的控制項是照設計檔的欄位自動長出來的（part_editor.gd），中文名稱在 data/workshop_labels.tres。
## 這是社課工具，用 F6 執行，不會匯出。
##
## 水族箱左上角是教學步驟卡（lesson/tutorial/tutorial_panel.tscn），用下面的 signal 告訴它發生了什麼。

## 讀了一隻生物、或按了「新的」
signal design_opened(design: CreatureDesign)
## 設計檔改了（控制項、復原重做、改名字）
signal design_edited(design: CreatureDesign)
## 拉了「預覽等級」
signal preview_level_changed(level: int)
## 存好檔了
signal design_saved(design: CreatureDesign)

const LABELS: WorkshopLabels = preload("res://lesson/workshop/data/workshop_labels.tres")
const TUTORIAL_PANEL: PackedScene = preload("res://lesson/tutorial/tutorial_panel.tscn")
## 讀取選單列出這些資料夾裡的設計檔（<資料夾>/design.tres）→ 選單上的前綴
const DESIGN_FOLDERS: Dictionary = {"res://example/creatures/": "範例", "res://my_creature/": "我的"}
const MY_FOLDER: String = "res://my_creature/"
## 停下來多久（秒）才記一筆「復原」，拖滑桿時才不會每一格都記
const HISTORY_DELAY: float = 0.4
const MAX_HISTORY: int = 100
## 匯入的圖最大幾像素（太大會縮小）
const MAX_IMAGE_SIZE: int = 512
## 匯入的圖的檔名最多幾個字（不含 .png），太長的剪掉（設計檔讀檔名最多 PartDesign.MAX_FILE_NAME 個字）
const MAX_IMAGE_NAME: int = 32
const MAX_PREVIEW_LEVEL: int = 10
## 右邊分頁的寬度：固定的一段＋跟著字變的一段（小字 320、中字約 400、大字 500）
const PANEL_WIDTH_FIXED: float = 140.0
const PANEL_WIDTH: float = 180.0
const MOVE_MODES: PackedStringArray = ["跟著滑鼠", "自己游", "停住"]
## 工坊裡的水流強度（像素／秒）
const WORKSHOP_FLOW: float = 12.0
## 複雜度超過上限時，能力那幾行的顏色
const COMPLEXITY_OVER_COLOR: Color = Color("#ff6b5e")

## 打開工坊時先讀哪一隻
@export_file("*.tres") var start_design: String = "res://example/creatures/snake/design.tres"

## 正在編輯的設計檔
var design: CreatureDesign
var _creature: Creature
## 這隻生物是從 my_creature 的哪個資料夾讀來的（範例或新的是空的）
var _loaded_folder: String = ""
## 復原用：每一步的設計檔資料、現在在第幾步
var _history: Array[Dictionary] = []
var _history_index: int = 0
var _history_timer: Timer
var _old_show_bones: bool = false
## 「匯入圖片」選好檔案之後，圖要放進哪個零件的哪一欄
var _pending_image_part: PartDesign
var _pending_image_field: String = "image_file"

var _name_edit: LineEdit
var _folder_edit: LineEdit
var _load_option: OptionButton
var _load_paths: PackedStringArray = []
var _undo_button: Button
var _redo_button: Button
var _message: Label
var _stage: SubViewport
var _stats_label: Label
var _level_slider: HSlider
var _level_label: Label
var _tabs: TabContainer
var _side_panel: PanelContainer
var _body_editor: PartEditor
var _growth_editor: PartEditor
var _growth_help: Label
## 零件清單的分頁：欄位名稱 → {"selector", "editor", "selected", "remove", "duplicate", "add"}
var _lists: Dictionary = {}
var _file_dialog: FileDialog
var _confirm: ConfirmationDialog
var _confirm_folder: String = ""
## 設計檔現在的複雜度（0 級的樣子）：改動之後超過上限、又比這個多，就擋下來
var _complexity: int = 0


func _ready() -> void:
	WorkshopSettings.load_settings()
	_apply_font_size()
	var debug: Node = get_node_or_null("/root/Debug")
	if debug != null:
		_old_show_bones = debug.get("show_bones")
		debug.set("show_bones", true)  # 實驗室：骨架一直開著
	WaterFlow.strength = WORKSHOP_FLOW  # 一點點水流，看得到觸手、掛件晃
	_history_timer = Timer.new()
	_history_timer.one_shot = true
	_history_timer.wait_time = HISTORY_DELAY
	_history_timer.timeout.connect(_commit_history)
	add_child(_history_timer)
	_build_ui()
	_refresh_load_list()
	_load_design(start_design)


func _exit_tree() -> void:
	WaterFlow.reset()
	var debug: Node = get_node_or_null("/root/Debug")
	if debug != null:
		debug.set("show_bones", _old_show_bones)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or not key.ctrl_pressed:
		return
	if key.keycode == KEY_Z and not key.shift_pressed:
		undo()
	elif key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed):
		redo()


# ---------------------------------------------------------------- 讀取、新的、存檔


## 換成一份新的設計檔來編輯。image_folder 是它的圖放在哪，loaded_folder 是 my_creature 底下的資料夾名
func use_design(new_design: CreatureDesign, image_folder: String, loaded_folder: String) -> void:
	design = new_design
	design.image_folder = image_folder
	_loaded_folder = loaded_folder
	_folder_edit.text = loaded_folder
	_name_edit.text = design.creature_name
	_level_slider.set_value_no_signal(0)
	_level_label.text = "預覽等級 0"
	_creature.level = 0
	_creature.design = design
	_complexity = design_complexity()
	_rebuild_editors()
	_reset_history()
	_update_stats()
	design_opened.emit(design)
	if _complexity > max_complexity():
		_show_message("這隻生物的複雜度 %d 超過上限 %d，放不進生態缸：請減少腳、觸手、節數或掛件" % [_complexity, max_complexity()])


## 讀一份設計檔（複製一份來改，不會動到原本的檔案）
func _load_design(path: String) -> void:
	var loaded: CreatureDesign = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CreatureDesign if ResourceLoader.exists(path) else null
	if loaded == null:
		_show_message("讀不到 %s" % path)
		return
	var folder: String = path.get_base_dir()
	use_design(CreatureDesign.from_data(loaded.to_dict()), folder, folder.get_file() if path.begins_with(MY_FOLDER) else "")
	_show_message("讀取了「%s」%s" % [design.creature_name, "" if _loaded_folder != "" else "（範例：存檔會存成你自己的一份）"])


func _new_design() -> void:
	var fresh := CreatureDesign.new()
	fresh.eyes.append(EyesDesign.new())
	use_design(fresh, "", "")
	_show_message("新的生物：先在右邊調身體，再加腳、觸手、掛件")


func _refresh_load_list() -> void:
	_load_option.clear()
	_load_option.add_item("讀取……")
	_load_paths = PackedStringArray([""])
	for folder: String in DESIGN_FOLDERS:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for sub: String in DirAccess.get_directories_at(folder):
			var path: String = folder + sub + "/design.tres"
			if not FileAccess.file_exists(path):
				continue
			var loaded: CreatureDesign = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CreatureDesign
			_load_option.add_item("%s：%s（%s）" % [DESIGN_FOLDERS[folder], loaded.creature_name if loaded != null else "?", sub])
			_load_paths.append(path)


func _on_save_pressed() -> void:
	var folder: String = _folder_edit.text.strip_edges()
	if not _is_valid_folder(folder):
		_show_message("「資料夾」只能用英文字母、數字、底線，例如 my_dragon")
		return
	if FileAccess.file_exists(MY_FOLDER + folder + "/design.tres") and folder != _loaded_folder:
		_confirm_folder = folder
		_confirm.dialog_text = "my_creature/%s 已經有一隻生物了，要蓋掉嗎？" % folder
		_confirm.popup_centered()
		return
	save_to(folder)


## 圖加起來超過連線的上限時，存檔後多一句提醒（先知道，連線那天才不會被嚇到）。沒超過是空字串
func image_size_hint() -> String:
	var total: int = BattlePacket.total_bytes(BattlePacket.read_images(design))
	if total <= BattlePacket.MAX_IMAGE_BYTES:
		return ""
	return "\n這隻的圖加起來 %.1f MB，比較大：連線對戰時會問你要不要縮小（原圖不會被改到）" % (total / 1048576.0)


## 存到 my_creature/<folder>/design.tres，用到的圖也複製過去
func save_to(folder: String) -> Error:
	var path: String = MY_FOLDER + folder + "/design.tres"
	DirAccess.make_dir_recursive_absolute(MY_FOLDER + folder)
	_gather_images(MY_FOLDER + folder)
	design.creature_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "我的生物"
	var error: Error = ResourceSaver.save(design, path)
	if error != OK:
		_show_message("存檔失敗（錯誤 %d）" % error)
		return error
	_loaded_folder = folder
	_refresh_load_list()
	_show_message("存好了：my_creature/%s/design.tres%s" % [folder, image_size_hint()])
	design_saved.emit(design)
	return OK


## 把設計檔用到的圖都複製到 folder（例如讀了範例再存檔、或第一次匯入圖片）
func _gather_images(folder: String) -> void:
	var files: PackedStringArray = []
	for part: OrnamentDesign in design.ornaments:
		files.append(part.image_file)
	for field: String in BodyDesign.image_fields():
		files.append(design.body.get(field))
	for file: String in files:
		if file == "":
			continue
		var source: String = design.image_path(file)
		var target: String = folder.path_join(file)
		if source != target and FileAccess.file_exists(source):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))
	design.image_folder = folder


static func _is_valid_folder(folder: String) -> bool:
	var regex := RegEx.create_from_string("^[A-Za-z0-9_]+$")
	return regex.search(folder) != null


# ---------------------------------------------------------------- 匯入圖片


func _on_import_requested(part: PartDesign, field: String) -> void:
	if not _is_valid_folder(_folder_edit.text.strip_edges()):
		_show_message("先在上面填「資料夾」（英文、數字、底線），圖片才知道要放哪裡")
		return
	_pending_image_part = part
	_pending_image_field = field
	_file_dialog.popup_centered_ratio(0.7)


## 選好圖片：太大就縮小，存成 PNG 放進生物的資料夾，part 的 field 這一欄改成這張圖
## （掛件的 image_file，或身體的 head_image、segment_image、tail_image）
func import_image(source_path: String, part: PartDesign, field: String = "image_file") -> bool:
	var image: Image = Image.load_from_file(source_path)
	if image == null or image.is_empty():
		_show_message("讀不到這張圖：%s" % source_path.get_file())
		return false
	var longest: int = maxi(image.get_width(), image.get_height())
	if longest > MAX_IMAGE_SIZE:
		var k: float = float(MAX_IMAGE_SIZE) / longest
		image.resize(maxi(roundi(image.get_width() * k), 1), maxi(roundi(image.get_height() * k), 1), Image.INTERPOLATE_LANCZOS)
	var folder: String = MY_FOLDER + _folder_edit.text.strip_edges()
	DirAccess.make_dir_recursive_absolute(folder)
	_gather_images(folder)
	var file: String = _safe_image_name(source_path.get_file())
	image.save_png(folder.path_join(file))
	part.set(field, file)
	var ornament: OrnamentDesign = part as OrnamentDesign
	if ornament != null and ornament.shape == Ornament.Shape.HORN:
		ornament.shape = Ornament.Shape.NONE  # 預設的「角」換成只顯示圖
	_on_design_changed()
	if ornament != null:
		_rebuild_list("ornaments")
	else:
		_body_editor.edit(design.body, LABELS)  # 顯示新的檔名
	_show_message("匯入了 %s（記得按「存檔」）" % file)
	return true


## 圖的檔名：只用英文、數字、底線、減號，不行的話取一個新名字；太長的剪到 MAX_IMAGE_NAME 個字
static func _safe_image_name(file: String) -> String:
	var base: String = file.get_basename().to_lower()
	if RegEx.create_from_string("^[a-z0-9_\\-]+$").search(base) == null:
		base = "image_%d" % (Time.get_ticks_msec() % 100000)
	return base.left(MAX_IMAGE_NAME) + ".png"


# ---------------------------------------------------------------- 改了設計檔


## 任何控制項改了設計檔：生物馬上變樣子、能力重算，停下來一下就記一筆復原
func _on_design_changed() -> void:
	_complexity = design_complexity()
	_creature.apply_design()
	_update_stats()
	_history_timer.start()
	design_edited.emit(design)


## 能力和代價（生物的速度、轉向本來就用算出來的能力，邊調邊感受得到）
func _update_stats() -> void:
	var stats: CreatureStats = _creature.get_stats()
	if stats == null:
		return
	var balance: CreatureBalance = _creature.get_balance()
	var mode_name: String = ["等比放大", "變長＋長出腳", "只變長"][design.growth_mode]
	_stats_label.text = "速度 %s　轉向 %s\n抓取 %s　視野 %s\n體型 %d　%s　每升一級要吃 %d 個\n複雜度 %d / %d" % [
		_stars(stats, "speed", balance), _stars(stats, "turn", balance), _stars(stats, "grab", balance), _stars(stats, "sight", balance),
		roundi(stats.size), mode_name, stats.level_cost, stats.complexity, balance.max_complexity]
	_stats_label.add_theme_color_override("font_color", COMPLEXITY_OVER_COLOR if _complexity > balance.max_complexity else Color.WHITE)
	_stats_label.tooltip_text = "速度 %d 像素／秒　轉向 %d 度／秒　抓取 %d 像素　視野 %d 像素（眼睛越多越大，生態缸的鏡頭拉得越遠）" % [roundi(stats.speed), roundi(rad_to_deg(stats.turn)), roundi(stats.grab), roundi(stats.sight)]
	for list_field: String in _lists:
		_refresh_list_names(list_field)
		_refresh_list_buttons(list_field)


# ---------------------------------------------------------------- 複雜度


func max_complexity() -> int:
	return _creature.get_balance().max_complexity


## 設計檔（0 級）的複雜度
func design_complexity() -> int:
	return CreatureStats.complexity_of(design, _creature.get_balance())


## 控制項改之前問的：改完沒超過上限（或比原本少）就可以
func _can_change() -> bool:
	var after: int = design_complexity()
	if after <= max_complexity() or after <= _complexity:
		return true
	_show_message("複雜度會變成 %d，超過上限 %d：先減少別的腳、觸手、節數或掛件" % [after, max_complexity()])
	return false


## 多加一個 part 之後的複雜度
func _complexity_with(field: String, part: PartDesign) -> int:
	var parts: Array = design.get(field)
	parts.append(part)
	var result: int = design_complexity()
	parts.pop_back()
	return result


func _stars(stats: CreatureStats, ability: String, balance: CreatureBalance) -> String:
	var count: int = stats.stars(ability, balance.max_stars)
	return "★".repeat(count) + "☆".repeat(balance.max_stars - count)


func _on_level_changed(value: float) -> void:
	_level_label.text = "預覽等級 %d" % int(value)
	_creature.level = int(value)
	_creature.apply_design()
	_update_stats()
	preview_level_changed.emit(int(value))


func _on_move_mode_selected(index: int) -> void:
	_creature.set_process(index != 2)
	_creature.control_mode = Creature.Mode.WANDER if index == 1 else Creature.Mode.MOUSE


# ---------------------------------------------------------------- 復原、重做


func _reset_history() -> void:
	_history_timer.stop()
	_history = [design.to_dict()]
	_history_index = 0
	_update_history_buttons()


## 記一筆（跟上一筆一樣就不記）。復原到一半又改了東西，後面的「重做」就丟掉
func _commit_history() -> void:
	var snapshot: Dictionary = design.to_dict()
	if snapshot == _history[_history_index]:
		return
	_history.resize(_history_index + 1)
	_history.append(snapshot)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_history_index = _history.size() - 1
	_update_history_buttons()


func undo() -> void:
	_history_timer.stop()
	_commit_history()  # 還沒記的改動先記起來，才復原得回來
	if _history_index > 0:
		_history_index -= 1
		_restore(_history[_history_index])


func redo() -> void:
	if _history_index < _history.size() - 1:
		_history_index += 1
		_restore(_history[_history_index])


func _restore(snapshot: Dictionary) -> void:
	var folder: String = design.image_folder
	design.from_dict(snapshot)
	design.image_folder = folder
	_name_edit.text = design.creature_name
	_complexity = design_complexity()
	_creature.apply_design()
	_rebuild_editors()
	_update_stats()
	_update_history_buttons()
	design_edited.emit(design)


func _update_history_buttons() -> void:
	_undo_button.disabled = _history_index <= 0
	_redo_button.disabled = _history_index >= _history.size() - 1


# ---------------------------------------------------------------- 右邊的分頁


## 零件清單分頁的設定：欄位名稱、分頁名稱、新增時用的類別、最多幾個
func _list_infos() -> Array:
	return [
		["legs", "腳", LegDesign, CreatureDesign.MAX_LEGS],
		["tentacles", "觸手", TentacleDesign, CreatureDesign.MAX_TENTACLES],
		["eyes", "眼睛", EyesDesign, CreatureDesign.MAX_EYES],
		["ornaments", "掛件", OrnamentDesign, CreatureDesign.MAX_ORNAMENTS],
	]


func _rebuild_editors() -> void:
	_body_editor.edit(design.body, LABELS)
	_growth_editor.edit(design, LABELS)
	_growth_help.text = "\n\n".join(LABELS.growth_help)
	for info: Array in _list_infos():
		_rebuild_list(info[0])


func _rebuild_list(field: String) -> void:
	var list: Dictionary = _lists[field]
	var parts: Array = design.get(field)
	list.selected = clampi(list.selected, 0, maxi(parts.size() - 1, 0))
	var selector: OptionButton = list.selector
	selector.clear()
	for i: int in parts.size():
		selector.add_item(_part_name(field, i))
	var editor: PartEditor = list.editor
	if parts.is_empty():
		editor.edit(PartDesign.new(), LABELS)  # 沒有零件：清空
		list.empty_label.visible = true
	else:
		selector.select(list.selected)
		editor.edit(parts[list.selected], LABELS)
		list.empty_label.visible = false
	_refresh_list_buttons(field)


## 「新增」「複製」「刪除」能不能按：數量到上限、或加了會超過複雜度上限，就變灰並說明原因
func _refresh_list_buttons(field: String) -> void:
	var list: Dictionary = _lists[field]
	var parts: Array = design.get(field)
	var info: Array = _list_info(field)
	var script: GDScript = info[2]
	var full: bool = parts.size() >= list.max
	var selected: PartDesign = parts[list.selected] if not parts.is_empty() else null
	(list.remove as Button).disabled = parts.is_empty()
	_set_add_button(list.add, full, _complexity_with(field, script.new()), "新增一個%s" % info[1])
	_set_add_button(list.duplicate, full, _complexity_with(field, selected) if selected != null else 0, "複製選到的這個")
	if selected == null:
		(list.duplicate as Button).disabled = true


## 「新增」「複製」：數量到上限、或加了之後超過複雜度上限就變灰，說明寫在滑鼠停上去的提示
func _set_add_button(button: Button, full: bool, after: int, normal_tip: String) -> void:
	var too_complex: bool = after > max_complexity()
	button.disabled = full or too_complex
	if full:
		button.tooltip_text = "最多就這麼多了"
	elif too_complex:
		button.tooltip_text = "再加複雜度會變成 %d，超過上限 %d：先減少別的零件" % [after, max_complexity()]
	else:
		button.tooltip_text = normal_tip


## 零件清單分頁的設定（找 field 那一項）
func _list_info(field: String) -> Array:
	return _list_infos().filter(func(info: Array) -> bool: return info[0] == field)[0]


## 選單上的名字，例如「1. 第 3 節・兩邊」
func _part_name(field: String, index: int) -> String:
	var part: PartDesign = design.get(field)[index]
	var segment: int = part.get("attach_segment")
	var text: String = "%d. %s" % [index + 1, "尾巴" if segment < 0 else "第 %d 節" % segment]
	if "side" in part:
		var sides: PackedStringArray = ["左", "右", "兩邊", "中間"]
		text += "・" + sides[part.get("side")]
	return text


func _refresh_list_names(field: String) -> void:
	var selector: OptionButton = _lists[field].selector
	var parts: Array = design.get(field)
	for i: int in mini(selector.item_count, parts.size()):
		selector.set_item_text(i, _part_name(field, i))


## 新增、複製、刪除零件
func _change_list(field: String, action: String) -> void:
	var list: Dictionary = _lists[field]
	var parts: Array = design.get(field)
	match action:
		"add":
			var script: GDScript = _list_info(field)[2]
			parts.append(script.new())
			list.selected = parts.size() - 1
		"duplicate":
			parts.append((parts[list.selected] as PartDesign).duplicate(true))
			list.selected = parts.size() - 1
		"remove":
			parts.remove_at(list.selected)
	if action != "remove" and not _can_change():  # 按鈕灰掉時按不到；保險起見再檢查一次
		parts.pop_back()
		list.selected = maxi(parts.size() - 1, 0)
	_rebuild_list(field)
	_on_design_changed()


# ---------------------------------------------------------------- 版面


## 換字的大小（WorkshopSettings.FONT_SIZES 其中一個）：記下來，整個工坊跟著變
func set_font_size(size: int) -> void:
	if not size in WorkshopSettings.FONT_SIZES:
		return
	WorkshopSettings.font_size = size
	WorkshopSettings.save_settings()
	_apply_font_size()
	_side_panel.custom_minimum_size.x = _panel_width()
	_level_label.custom_minimum_size.x = WorkshopSettings.ui(80)
	_rebuild_editors()  # 名稱欄、數字欄這些寬度是做控制項時決定的，重做一次


## 字的大小放在工坊的 Theme：底下的控制項、教學步驟卡都跟著變
func _apply_font_size() -> void:
	var new_theme := Theme.new()
	new_theme.default_font_size = WorkshopSettings.font_size
	theme = new_theme


func _panel_width() -> float:
	return PANEL_WIDTH_FIXED + WorkshopSettings.ui(PANEL_WIDTH)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var root := HBoxContainer.new()
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	left.add_child(_build_top_bar())
	left.add_child(_build_file_bar())
	left.add_child(_build_message())
	left.add_child(_build_stage())
	left.add_child(_build_bottom_bar())

	_side_panel = PanelContainer.new()
	_side_panel.custom_minimum_size.x = _panel_width()
	root.add_child(_side_panel)
	_tabs = TabContainer.new()
	_side_panel.add_child(_tabs)
	_body_editor = PartEditor.new()
	_body_editor.can_change = _can_change
	_body_editor.changed.connect(_on_design_changed)
	_body_editor.import_image_requested.connect(_on_import_requested)
	_add_tab("身體", _body_editor)
	for info: Array in _list_infos():
		_add_tab(info[1], _build_list_tab(info[0], info[1], info[3]))
	var growth := VBoxContainer.new()
	_growth_editor = PartEditor.new()
	_growth_editor.changed.connect(_on_design_changed)
	growth.add_child(_growth_editor)
	_growth_help = Label.new()
	_growth_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	growth.add_child(_growth_help)
	_add_tab("長大", growth)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png ; PNG 圖片"])
	_file_dialog.title = "選一張 PNG 圖片"
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(func(path: String) -> void:
		if _pending_image_part != null:
			import_image(path, _pending_image_part, _pending_image_field))
	add_child(_file_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = "蓋掉"
	_confirm.cancel_button_text = "不要"
	_confirm.confirmed.connect(func() -> void: save_to(_confirm_folder))
	add_child(_confirm)


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_child(_text("名字"))
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = PartDesign.MAX_TEXT
	_name_edit.text_changed.connect(func(text: String) -> void:
		design.creature_name = text
		_history_timer.start()
		design_edited.emit(design))
	bar.add_child(_name_edit)
	bar.add_child(_text("資料夾"))
	_folder_edit = LineEdit.new()
	_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_edit.placeholder_text = "英文，例如 my_dragon"
	_folder_edit.tooltip_text = "存在 my_creature/這個名字/design.tres。只能用英文字母、數字、底線"
	bar.add_child(_folder_edit)
	return bar


func _build_file_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_child(_button("新的", _new_design, "從一隻空白的生物開始"))
	_load_option = OptionButton.new()
	_load_option.tooltip_text = "讀範例或自己存過的生物"
	_load_option.item_selected.connect(func(index: int) -> void:
		if index > 0:
			_load_design(_load_paths[index])
		_load_option.select(0))
	bar.add_child(_load_option)
	bar.add_child(_button("存檔", _on_save_pressed, "存到 my_creature/資料夾/design.tres"))
	_undo_button = _button("復原", undo, "回到上一步（Ctrl+Z）")
	bar.add_child(_undo_button)
	_redo_button = _button("重做", redo, "取消復原（Ctrl+Y）")
	bar.add_child(_redo_button)
	var font_option := OptionButton.new()
	for font_name: String in WorkshopSettings.FONT_NAMES:
		font_option.add_item(font_name)
	font_option.select(maxi(WorkshopSettings.FONT_SIZES.find(WorkshopSettings.font_size), 0))
	font_option.tooltip_text = "工坊的字要大一點還是小一點（這台電腦會記住）"
	font_option.item_selected.connect(func(index: int) -> void: set_font_size(WorkshopSettings.FONT_SIZES[index]))
	bar.add_child(font_option)
	return bar


## 提示文字：按鈕列下面獨立一行，太長就換行（大字時才看得完）
func _build_message() -> Control:
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Color("#f2b766"))
	return _message


## 水族箱：獨立的子畫面，生物只會在這裡面游。左上角疊著教學步驟卡
func _build_stage() -> Control:
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_child(container)
	var tutorial: TutorialPanel = TUTORIAL_PANEL.instantiate()
	area.add_child(tutorial)
	design_opened.connect(tutorial.on_design_opened)
	design_edited.connect(tutorial.on_design_edited)
	preview_level_changed.connect(tutorial.on_preview_level_changed)
	design_saved.connect(tutorial.on_design_saved)
	_stage = SubViewport.new()
	container.add_child(_stage)
	var water := ColorRect.new()
	water.color = Color("#123c46")
	water.size = Vector2(4000, 4000)
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(water)
	_creature = Creature.new()
	_creature.position = Vector2(380, 280)
	_stage.add_child(_creature)
	return area


func _build_bottom_bar() -> Control:
	var box := VBoxContainer.new()
	_stats_label = Label.new()
	_stats_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_stats_label)
	var row := HBoxContainer.new()
	_level_label = _text("預覽等級 0")
	_level_label.custom_minimum_size.x = WorkshopSettings.ui(80)
	_level_label.tooltip_text = "拉拉看：升級之後會長成什麼樣子、能力怎麼變"
	row.add_child(_level_label)
	_level_slider = HSlider.new()
	_level_slider.max_value = MAX_PREVIEW_LEVEL
	_level_slider.step = 1
	_level_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_level_slider.value_changed.connect(_on_level_changed)
	row.add_child(_level_slider)
	var move := OptionButton.new()
	for mode_name: String in MOVE_MODES:
		move.add_item(mode_name)
	move.item_selected.connect(_on_move_mode_selected)
	row.add_child(move)
	box.add_child(row)
	return box


## 零件清單的分頁：上面是選單和「新增、複製、刪除」，下面是選到的那個零件的控制項
func _build_list_tab(field: String, title: String, max_count: int) -> Control:
	var box := VBoxContainer.new()
	var bar := HBoxContainer.new()
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.item_selected.connect(func(index: int) -> void:
		_lists[field].selected = index
		_rebuild_list(field))
	bar.add_child(selector)
	var add_button: Button = _button("＋", func() -> void: _change_list(field, "add"), "新增一個%s" % title)
	var duplicate_button: Button = _button("複製", func() -> void: _change_list(field, "duplicate"), "複製選到的這個")
	var remove_button: Button = _button("刪除", func() -> void: _change_list(field, "remove"), "刪掉選到的這個")
	bar.add_child(add_button)
	bar.add_child(duplicate_button)
	bar.add_child(remove_button)
	box.add_child(bar)
	var empty := _text("還沒有%s，按「＋」新增一個" % title)
	box.add_child(empty)
	var editor := PartEditor.new()
	editor.can_change = _can_change
	editor.changed.connect(_on_design_changed)
	editor.import_image_requested.connect(_on_import_requested)
	box.add_child(editor)
	_lists[field] = {"selector": selector, "editor": editor, "selected": 0, "add": add_button, "duplicate": duplicate_button, "remove": remove_button, "max": max_count, "empty_label": empty}
	return box


## 加一個分頁，內容放在可以捲動的區域
func _add_tab(title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, title)


func _button(text: String, on_press: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_press)
	return button


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _show_message(text: String) -> void:
	_message.text = text
	_message.tooltip_text = text
