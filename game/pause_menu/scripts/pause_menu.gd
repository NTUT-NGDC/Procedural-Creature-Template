extends CanvasLayer
## 暫停選單：遊戲中按 Esc 或右上角的「選單」按鈕打開，可以調音量、回到標題。
## 打開時整個遊戲會暫停（生物、食物、水草都停住），選單本身照常運作。
##
## 用法：把 pause_menu.tscn 從檔案系統拖進遊戲場景（放在最上層節點底下）就好。生態缸已經放好了。
##
## 想改文字、字的大小、顏色：直接點場景裡的節點，在右邊的檢查器改，程式不會蓋掉。
##   ・右上角的按鈕：MenuButton　・選單裡的標題、按鈕、「音樂」「音效」：MenuPanel 底下的節點

## 按了「回到標題」，但遊戲是被別的場景包著在玩（例如教學關的試玩）時發出，由外面決定要做什麼
signal title_requested()

## 按「回到標題」後要換到的標題畫面
@export_file("*.tscn") var title_scene: String = "res://game/title_screen/title_screen.tscn"

@onready var _menu_button: Button = %MenuButton
@onready var _menu_panel: Control = %MenuPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _title_button: Button = %TitleButton


func _ready() -> void:
	# 遊戲暫停時，選單自己還要能動（按鈕、Esc 才按得到）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_panel.hide()
	_menu_button.pressed.connect(open_menu)
	_resume_button.pressed.connect(close_menu)
	_title_button.pressed.connect(_on_title_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _menu_panel.visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()


## 打開選單，暫停遊戲
func open_menu() -> void:
	_menu_panel.show()
	_menu_button.hide()
	get_tree().paused = true


## 關掉選單，繼續遊戲
func close_menu() -> void:
	_menu_panel.hide()
	_menu_button.show()
	get_tree().paused = false


func _on_title_pressed() -> void:
	# 換場景前先解除暫停，不然標題畫面也會是暫停的
	get_tree().paused = false
	close_menu()
	# 遊戲是被別的場景包著在玩（不是目前的場景）時，不自己換場景，交給外面處理
	if owner != null and owner != get_tree().current_scene:
		title_requested.emit()
		return
	get_tree().change_scene_to_file(title_scene)


func _exit_tree() -> void:
	# 選單開著就離開這個場景時，記得解除暫停，不然下一個場景會卡住
	if _menu_panel.visible:
		get_tree().paused = false
