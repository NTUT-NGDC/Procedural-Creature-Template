extends CanvasLayer
## 生態缸的 HUD：左上角顯示遊戲名稱、等級、還要吃幾個才升級、四種能力的星星。
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


## 在畫面中間顯示一段提示（例如設定有問題）。seconds > 0 時幾秒後自己消失
func show_message(text: String, seconds: float = 0.0) -> void:
	_message_label.text = text
	_message_label.show()
	if seconds > 0.0:
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if _message_label.text == text:
				_message_label.hide())


## 現在顯示的提示（沒有就是空字串，測試用）
func get_message() -> String:
	return _message_label.text if _message_label.visible else ""
