extends Control
## 連線畫面：選生物、填名稱、主機 IP，按「加入」；社長按「開主機」。從標題畫面的「連線對戰」進來。
##
## 生物可以從 my_creature（我的）和 example/creatures（範例）裡選，預設是標題畫面設定的那隻。
##
## 圖加起來超過上限（BattlePacket.MAX_IMAGE_BYTES）時，先跳出視窗說明原因、問要不要縮小，
## 同意才縮小（只縮傳出去的那一份，硬碟上的圖不動）。

const BATTLE_SCENE: PackedScene = preload("res://lesson/battle/online_battle.tscn")
const TITLE_SCENE: String = "res://game/title_screen/title_screen.tscn"
## 可以選的生物：資料夾 → 選單上的前綴（照順序列，自己的在前面）
const DESIGN_FOLDERS: Dictionary = {"res://my_creature/": "我的", "res://example/creatures/": "範例"}

## 這次開遊戲填過的名稱、位址（回到這個畫面時不用重打）
static var last_name: String = ""
static var last_address: String = ""
## 這次開遊戲選過的生物（設計檔路徑）
static var last_design_path: String = ""

## 要帶進對戰的生物：一開始是標題畫面交過來的，在選單換生物就換掉
var player_design: CreatureDesign

@onready var _creature_option: OptionButton = %CreatureOption
@onready var _creature_info: Label = %CreatureInfo
@onready var _preview_viewport: SubViewport = %PreviewViewport
@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _join_button: Button = %JoinButton
@onready var _host_button: Button = %HostButton
@onready var _back_button: Button = %BackButton
@onready var _message_label: Label = %MessageLabel
@onready var _shrink_dialog: ConfirmationDialog = %ShrinkDialog

## 按了「加入」還是「開主機」（等縮小的視窗回答時用）
var _hosting: bool = false
## 要傳出去的圖（檔名 → PNG 位元組）
var _images: Dictionary = {}
## 圖要縮成多大（0 是不用縮）
var _shrink_side: int = 0
## 選單每一項對應的設計檔路徑（空字串是「標題畫面設定的」那隻）
var _design_paths: PackedStringArray = []
## 標題畫面交過來的生物（選單裡找不到它的時候，放在第一項）
var _title_design: CreatureDesign
## 預覽框裡游的生物
var _preview: Creature


func _ready() -> void:
	_message_label.hide()
	_name_edit.max_length = BattlePacket.MAX_NAME
	_name_edit.text = last_name
	_address_edit.text = last_address
	_title_design = player_design
	_build_preview()
	_fill_creature_option()
	_creature_option.item_selected.connect(_on_creature_selected)
	_join_button.pressed.connect(_on_go.bind(false))
	_host_button.pressed.connect(_on_go.bind(true))
	_back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	_shrink_dialog.confirmed.connect(_go)


# ---------------------------------------------------------------- 選生物


## 把「我的」和「範例」的生物列進選單，選好上次選的（沒有的話選標題畫面設定的）
func _fill_creature_option() -> void:
	_creature_option.clear()
	_design_paths = PackedStringArray()
	var title_path: String = _title_design.resource_path if _title_design != null else ""
	var designs: Array[Dictionary] = CreatureDesign.list_designs(DESIGN_FOLDERS)
	var title_in_list: bool = designs.any(func(item: Dictionary) -> bool: return item.path == title_path)
	if _title_design != null and not title_in_list:
		_creature_option.add_item("標題畫面設定的：%s" % _title_design.creature_name)
		_design_paths.append("")
	for item: Dictionary in designs:
		_creature_option.add_item(item.label)
		_design_paths.append(item.path)
	if _design_paths.is_empty():
		_creature_info.text = "找不到生物：請先到生物工坊存一隻"
		return
	var want: String = last_design_path if last_design_path in _design_paths else (title_path if title_in_list else "")
	var index: int = maxi(_design_paths.find(want), 0)
	_creature_option.select(index)
	_on_creature_selected(index)


func _on_creature_selected(index: int) -> void:
	var path: String = _design_paths[index]
	var from_title: bool = _title_design != null and (path == "" or path == _title_design.resource_path)
	var design: CreatureDesign = _title_design if from_title else CreatureDesign.load_fresh(path)
	if design == null:
		_creature_info.text = "讀不到 %s：檔案可能壞掉了，選別隻吧" % path
		player_design = null
		_preview.hide()
		return
	last_design_path = path
	player_design = design
	_preview.design = design
	_preview.show()
	_creature_info.text = creature_info(design)


## 選單下面的說明：複雜度、自己的圖有多大（超過上限的話先講）
static func creature_info(design: CreatureDesign) -> String:
	var balance: CreatureBalance = CreatureBalance.get_default()
	var complexity: int = CreatureStats.complexity_of(design, balance)
	var lines: PackedStringArray = ["複雜度 %d／%d%s" % [complexity, balance.max_complexity, "（太複雜，不能加入）" if complexity > balance.max_complexity else ""]]
	var images: Dictionary = BattlePacket.read_images(design)
	if not images.is_empty():
		var total: int = BattlePacket.total_bytes(images)
		lines.append("自己的圖 %d 張，共 %d KB%s" % [images.size(), BattlePacket.kb(total),
			"（超過 %d KB，加入時會問你要不要縮小）" % BattlePacket.kb(BattlePacket.MAX_IMAGE_BYTES) if total > BattlePacket.MAX_IMAGE_BYTES else ""])
	lines.append("在生物工坊存的生物會出現在「我的」")
	return "
".join(lines)


## 預覽框：一隻在框裡慢慢漫遊的生物（鏡頭拉遠，長的生物也放得下）
func _build_preview() -> void:
	_preview = Creature.new()
	_preview.control_mode = Creature.Mode.WANDER
	_preview_viewport.add_child(_preview)
	_preview.hide()


# ---------------------------------------------------------------- 加入、開主機


## 按了「加入」或「開主機」：檢查生物、名稱、位址，圖太大就先問
func _on_go(hosting: bool) -> void:
	_hosting = hosting
	var problem: String = check_input(hosting)
	if problem != "":
		_show_message(problem)
		return
	last_name = _name_edit.text
	last_address = _address_edit.text
	_images = BattlePacket.read_images(player_design)
	_shrink_side = BattlePacket.shrink_side_needed(_images)
	if _shrink_side < 0:
		_show_message("你的圖加起來 %d KB，縮到最小還是超過連線的上限 %d KB：請回生物工坊減少圖片" % [
			BattlePacket.kb(BattlePacket.total_bytes(_images)), BattlePacket.kb(BattlePacket.MAX_IMAGE_BYTES)])
		return
	if _shrink_side > 0:
		_shrink_dialog.dialog_text = shrink_message(BattlePacket.total_bytes(_images), _shrink_side)
		_shrink_dialog.popup_centered()
		return
	_go()


## 回傳空字串是沒問題，不然回傳要顯示的說明
func check_input(hosting: bool) -> String:
	if player_design == null:
		return "還沒有選生物：請在上面的選單選一隻"
	var balance: CreatureBalance = CreatureBalance.get_default()
	var complexity: int = CreatureStats.complexity_of(player_design, balance)
	if complexity > balance.max_complexity:
		return "這隻生物太複雜了（複雜度 %d，上限 %d）：請回生物工坊減少腳、觸手、節數或掛件" % [complexity, balance.max_complexity]
	if not hosting and OnlineBattle.normalize_address(_address_edit.text) == "":
		return "請填主機的 IP（社長會投影在畫面上，例如 10.101.6.72）"
	return ""


## 縮小視窗的說明：為什麼要縮、會縮成多大、原圖不會被改到
static func shrink_message(total_bytes: int, side: int) -> String:
	return "你的圖加起來 %.1f MB，超過連線的上限 %.0f MB。\n全班每個人都要下載每一隻生物的圖，圖太大的話大家會等很久，甚至連不上。\n\n要把圖縮小成 %d 像素再加入嗎？\n你的原圖不會被改到，單人生態缸還是原本的畫質。" % [
		total_bytes / 1048576.0, BattlePacket.MAX_IMAGE_BYTES / 1048576.0, side]


## 打包，換到對戰
func _go() -> void:
	var images: Dictionary = BattlePacket.shrink_images(_images, _shrink_side) if _shrink_side > 0 else _images
	var battle: OnlineBattle = BATTLE_SCENE.instantiate()
	battle.is_host = _hosting
	battle.address = OnlineBattle.normalize_address(_address_edit.text)
	battle.my_design = player_design
	battle.my_packet = BattlePacket.build(_name_edit.text, player_design, images)
	get_tree().change_scene_to_node(battle)


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_label.show()
