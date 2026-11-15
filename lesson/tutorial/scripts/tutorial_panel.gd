class_name TutorialPanel
extends PanelContainer
## 工坊水族箱左上角的教學步驟卡：一次顯示一步，可以切上一步／下一步、收起來，按住最上面那一行可以拖到別的地方。
## 字的大小跟著工坊的設定（工坊的 Theme），卡片寬度跟著字變。
##
## 工坊用 signal 通知這裡（讀了生物、改了設計檔、拉了預覽等級、存檔），
## 這裡記實驗紀錄（TutorialRecord）、用 TutorialChecker 檢查每一步，不會去抓工坊的節點。
## 步驟文字在 data/tutorial_steps.tres。

const STEPS: TutorialSteps = preload("res://lesson/tutorial/data/tutorial_steps.tres")
## 卡片寬度：固定的一段＋字的大小 × 倍數（11 號字 260、22 號字 440）
const WIDTH_FIXED: float = 80.0
const WIDTH_PER_FONT: float = 180.0 / 11.0

@onready var _header: Control = %Header
@onready var _progress_label: Label = %ProgressLabel
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _fold_button: Button = %FoldButton
@onready var _step_row: StepRow = %StepRow

var record := TutorialRecord.new()
## 每一步過了沒（除了「存檔」，過了就一直算過）
var passed: Array[bool] = []
## 每一步沒過的原因
var _reasons: PackedStringArray = []
## 現在顯示第幾步
var current: int = 0
var _design: CreatureDesign
var _dragging: bool = false


func _ready() -> void:
	passed.resize(STEPS.steps.size())
	passed.fill(false)
	_reasons.resize(STEPS.steps.size())
	_prev_button.pressed.connect(func() -> void: show_step(current - 1))
	_next_button.pressed.connect(func() -> void: show_step(current + 1))
	_fold_button.pressed.connect(_toggle_fold)
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_input)
	var area: Control = get_parent_control()
	if area != null:
		area.resized.connect(_keep_inside)  # 視窗變小時，卡片不會跑出水族箱
	_fit_to_font()
	show_step(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_fit_to_font()


# ---------------------------------------------------------------- 工坊傳來的事件


## 讀了一隻生物（或按「新的」）
func on_design_opened(design: CreatureDesign) -> void:
	_design = design
	record.open(design)
	_recheck()


## 設計檔改了（滑桿、按鈕、復原、改名字）
func on_design_edited(design: CreatureDesign) -> void:
	_design = design
	record.observe(design)
	_recheck()


func on_preview_level_changed(level: int) -> void:
	record.observe_level(level)
	_recheck()


func on_design_saved(design: CreatureDesign) -> void:
	record.mark_saved(design)
	_recheck()


# ---------------------------------------------------------------- 檢查、顯示


## 全部重新檢查一次，更新進度和目前這一步
func _recheck() -> void:
	for i: int in passed.size():
		var reason: String = TutorialChecker.check(i, _design, record)
		_reasons[i] = reason
		passed[i] = reason == "" or (passed[i] and TutorialChecker.is_sticky(i))
	_update_progress()
	show_step(current)


func show_step(index: int) -> void:
	current = clampi(index, 0, STEPS.steps.size() - 1)
	_step_row.set_step(STEPS.steps[current])
	_step_row.show_result(passed[current], STEPS.steps[current].done_text if passed[current] else _reasons[current])
	_prev_button.disabled = current == 0
	_next_button.disabled = current == STEPS.steps.size() - 1


func _update_progress() -> void:
	var required: int = 0
	var extra: int = 0
	for i: int in passed.size():
		if passed[i]:
			if i < TutorialChecker.REQUIRED_COUNT:
				required += 1
			else:
				extra += 1
	_progress_label.text = "已完成 %d／%d 步　額外：%d／%d" % [required, TutorialChecker.REQUIRED_COUNT, extra, passed.size() - TutorialChecker.REQUIRED_COUNT]


func _toggle_fold() -> void:
	_step_row.visible = not _step_row.visible
	_fold_button.text = "收起" if _step_row.visible else "展開"
	_shrink()


# ---------------------------------------------------------------- 大小、拖動


## 字變大變小：卡片寬度跟著變
func _fit_to_font() -> void:
	custom_minimum_size.x = WIDTH_FIXED + WIDTH_PER_FONT * get_theme_default_font_size()
	_shrink()


## 縮回剛好包住內容的大小（收起來、字變小時），再確認沒跑出水族箱。
## 等一幀：裡面的文字要先照新的大小重排，量出來的大小才對
func _shrink() -> void:
	await get_tree().process_frame
	reset_size()
	_keep_inside()


## 按住最上面那一行拖動
func _on_header_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		accept_event()
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging:
		position += motion.relative
		_keep_inside()
		accept_event()


## 卡片整個留在水族箱裡面
func _keep_inside() -> void:
	var area: Control = get_parent_control()
	if area == null or area.size.x < size.x or area.size.y < size.y:
		return  # 水族箱還沒排好版（比卡片還小）
	position = position.clamp(Vector2.ZERO, (area.size - size).max(Vector2.ZERO))
