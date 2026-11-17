class_name BattleHud
extends CanvasLayer
## 連線對戰的介面：上面中間是時間、右邊是排行榜；主機在下面多一排「開始對戰」和分鐘數；
## 時間到、連不上時，中間跳出一個框（最終排名、原因），有「離開」按鈕。
## 只負責顯示，按了按鈕發 signal，由 online_battle.gd 處理。
##
## 想改字的大小、顏色：點場景裡的節點，在檢查器的 Theme Overrides 改。

## 主機按了「開始對戰」（或「再一場」）
signal start_pressed()
## 按了「離開」
signal leave_pressed()

@onready var _time_label: Label = %TimeLabel
@onready var _rank_label: Label = %RankLabel
@onready var _host_bar: Control = %HostBar
@onready var _ip_label: Label = %IpLabel
@onready var _minutes_spin: SpinBox = %MinutesSpin
@onready var _start_button: Button = %StartButton
@onready var _notice_panel: Control = %NoticePanel
@onready var _notice_title: Label = %NoticeTitle
@onready var _notice_text: Label = %NoticeText
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暫停選單打開時也要能按
	_host_bar.hide()
	_notice_panel.hide()
	_start_button.pressed.connect(start_pressed.emit)
	_leave_button.pressed.connect(leave_pressed.emit)


## 開始過一場以後，主機的按鈕變成「再一場」
func set_started() -> void:
	_start_button.text = "再一場"


## 主機才看得到的那一排：本機 IP（學員要輸入的）、一場幾分鐘、開始按鈕
func show_host(ips: PackedStringArray, minutes: float) -> void:
	_ip_label.text = "主機 IP：%s" % ("、".join(ips) if not ips.is_empty() else "（找不到，請確認有連上網路）")
	_minutes_spin.value = minutes
	_host_bar.show()


## 主機設定的一場幾分鐘
func get_minutes() -> float:
	return _minutes_spin.value


func show_time(text: String) -> void:
	_time_label.text = text


func show_ranking(text: String) -> void:
	_rank_label.text = text


## 中間的框：title 是標題（「最終排名」「沒辦法對戰」），text 是內容
func show_notice(title: String, text: String) -> void:
	_notice_title.text = title
	_notice_text.text = text
	_notice_panel.show()


func hide_notice() -> void:
	_notice_panel.hide()


## 中間的框現在顯示的內容（沒有顯示是空字串，測試用）
func get_notice() -> String:
	return (_notice_title.text + "\n" + _notice_text.text) if _notice_panel.visible else ""
