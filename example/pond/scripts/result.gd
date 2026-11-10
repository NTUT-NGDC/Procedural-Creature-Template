extends CanvasLayer
## 結算畫面：顯示贏了還是輸了，有「再來一場」和「回標題」兩個按鈕。
## 按了按鈕只發出訊號，要做什麼由池塘（pond.gd）決定。
##
## 想改文字、顏色：點場景裡 Result 底下的節點，在檢查器改。贏、輸的標題文字在 pond.gd 裡。

## 按了「再來一場」
signal restart_pressed()
## 按了「回標題」
signal title_pressed()

@onready var _title_label: Label = %ResultTitle
@onready var _detail_label: Label = %ResultDetail
@onready var _restart_button: Button = %RestartButton
@onready var _title_button: Button = %TitleButton


func _ready() -> void:
	# 結算時遊戲是暫停的，結算畫面自己要能按
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_restart_button.pressed.connect(restart_pressed.emit)
	_title_button.pressed.connect(title_pressed.emit)


## 顯示結算。won 是贏了沒，title 是大標題，detail 是下面的小字
func show_result(won: bool, title: String, detail: String) -> void:
	_title_label.text = title
	_title_label.add_theme_color_override("font_color", Color("#ffd84d") if won else Color("#ff8f8f"))
	_detail_label.text = detail
	show()
	_restart_button.grab_focus()
