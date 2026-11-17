extends Control
## 連線畫面：填名稱、主機 IP，按「加入」；社長按「開主機」。從標題畫面的「連線對戰」進來。
##
## 生物在標題畫面選（「＜　生物名稱　＞」），這裡只顯示預覽、複雜度、圖有多大。
##
## 圖加起來超過上限（BattlePacket.MAX_IMAGE_BYTES）時，先跳出視窗說明原因、問要不要縮小，
## 同意才縮小（只縮傳出去的那一份，硬碟上的圖不動）。

const BATTLE_SCENE: PackedScene = preload("res://lesson/battle/online_battle.tscn")
const TITLE_SCENE: String = "res://game/title_screen/title_screen.tscn"

## 這次開遊戲填過的名稱、位址（回到這個畫面時不用重打）
static var last_name: String = ""
static var last_address: String = ""

## 要帶進對戰的生物（標題畫面交過來）
var player_design: CreatureDesign

@onready var _creature_name: Label = %CreatureName
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
## 預覽框裡游的生物
var _preview: Creature


func _ready() -> void:
	_message_label.hide()
	_name_edit.max_length = BattlePacket.MAX_NAME
	_name_edit.text = last_name
	_address_edit.text = last_address
	_show_creature()
	_join_button.pressed.connect(_on_go.bind(false))
	_host_button.pressed.connect(_on_go.bind(true))
	_back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	_shrink_dialog.confirmed.connect(_go)


# ---------------------------------------------------------------- 你的生物


## 預覽框：一隻在框裡慢慢漫遊的生物（鏡頭拉遠，長的生物也放得下）；旁邊寫名稱和說明
func _show_creature() -> void:
	if player_design == null:
		_creature_name.text = "（還沒有生物）"
		_creature_info.text = "請回標題畫面設定玩家生物"
		return
	_preview = Creature.new()
	_preview.control_mode = Creature.Mode.WANDER
	_preview.design = player_design
	_preview_viewport.add_child(_preview)
	_creature_name.text = player_design.creature_name
	_creature_info.text = creature_info(player_design)


## 名稱下面的說明：複雜度、自己的圖有多大（超過上限的話先講）
static func creature_info(design: CreatureDesign) -> String:
	var balance: CreatureBalance = CreatureBalance.get_default()
	var complexity: int = CreatureStats.complexity_of(design, balance)
	var lines: PackedStringArray = ["複雜度 %d／%d%s" % [complexity, balance.max_complexity, "（太複雜，不能加入）" if complexity > balance.max_complexity else ""]]
	var images: Dictionary = BattlePacket.read_images(design)
	if not images.is_empty():
		var total: int = BattlePacket.total_bytes(images)
		lines.append("自己的圖 %d 張，共 %d KB%s" % [images.size(), BattlePacket.kb(total),
			"（超過 %d KB，加入時會問你要不要縮小）" % BattlePacket.kb(BattlePacket.MAX_IMAGE_BYTES) if total > BattlePacket.MAX_IMAGE_BYTES else ""])
	lines.append("想換生物：回標題畫面按「＜」「＞」")
	return "
".join(lines)


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
		return "還沒有生物：請回標題畫面設定玩家生物"
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
