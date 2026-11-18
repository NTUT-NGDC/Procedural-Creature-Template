extends CanvasLayer
## 生態缸的 HUD：左上角顯示遊戲名稱、等級、還要吃幾個才升級、四種能力的星星。
## 右上角的「選單」按鈕是暫停選單（PauseMenu）的，不在這裡。
##
## 能力的星星、加速的說明（DetailLabel）一開始顯示 DETAIL_SECONDS 秒就淡掉，不然擋畫面；
## 打開暫停選單（遊戲暫停）時再顯示，關掉又藏起來。
##
## 想改字的大小、顏色：點場景裡 HUD 底下的 Label，在檢查器的 Theme Overrides 改。

## 能力、加速說明顯示幾秒才淡掉；淡掉要幾秒
const DETAIL_SECONDS: float = 5.0
const FADE_SECONDS: float = 1.0

@onready var _name_label: Label = %NameLabel
@onready var _status_label: Label = %StatusLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _message_label: Label = %MessageLabel


func _ready() -> void:
	_message_label.hide()
	var fade: Tween = create_tween()
	fade.tween_interval(DETAIL_SECONDS)
	fade.tween_property(_detail_label, "modulate:a", 0.0, FADE_SECONDS)


## 更新左上角的文字：status 一直顯示（等級、還要吃幾個），detail 是能力和加速的說明（一開始顯示一下）
func show_status(game_name: String, status: String, detail: String = "") -> void:
	_name_label.text = game_name
	_status_label.text = status
	_detail_label.text = detail


## 能力、加速說明現在看不看得到（測試用）
func is_detail_shown() -> bool:
	return _detail_label.modulate.a > 0.5


## 暫停（打開暫停選單）時把能力、加速說明叫回來；繼續遊戲時再藏起來（還沒淡掉的話照原本的時間淡掉）
func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_PAUSED:
		_detail_label.set_meta("before_pause", _detail_label.modulate.a)
		_detail_label.modulate.a = 1.0
	elif what == NOTIFICATION_UNPAUSED:
		_detail_label.modulate.a = _detail_label.get_meta("before_pause", 1.0)


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
