extends CanvasLayer
## 池塘的 HUD：左上角顯示遊戲名稱、目前進度（長度、時間、吃了幾個）。
## 右上角的「選單」按鈕是暫停選單（PauseMenu）的，不在這裡。
##
## 想改字的大小、顏色：點場景裡 HUD 底下的 Label，在檢查器的 Theme Overrides 改。

@onready var _name_label: Label = %NameLabel
@onready var _status_label: Label = %StatusLabel
@onready var _message_label: Label = %MessageLabel


func _ready() -> void:
	_message_label.hide()


## 更新左上角的文字
func show_status(game_name: String, status: String) -> void:
	_name_label.text = game_name
	_status_label.text = status


## 在畫面中間顯示一段提示（例如池塘設定有問題）
func show_message(text: String) -> void:
	_message_label.text = text
	_message_label.show()
