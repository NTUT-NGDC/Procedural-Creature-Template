extends Control
## 教學關：列出 10 個步驟，按「檢查」檢查 my_creature 資料夾裡的生物和池塘有沒有做對。
##
## 第 1～5、7～10 步：讀檔檢查（邏輯會放在 creature_checker.gd）。
## 第 6 步：按「試玩」實際玩自己的池塘，玩到贏或輸才算過。
## 第 7～10 步是額外題，不算在「已完成幾步」裡，另外計算。
## 步驟的文字在 lesson/tutorial/data/tutorial_steps.tres，要改文字改那裡就好。
##
## （開發中：檢查邏輯和試玩在 T5 才接上，目前每一步都顯示「還沒做好」）

const STEP_ROW_SCENE: PackedScene = preload("res://lesson/tutorial/step_row.tscn")
## 額外題在列表裡是第幾個（從 0 開始）
const EXTRA_STEP_INDEXES: Array[int] = [6, 7, 8, 9]
## 檢查邏輯還沒接上時顯示的文字
const NOT_READY_MESSAGE: String = "這一步的檢查還沒做好。"

## 要檢查的資料夾，社員的生物和池塘放這裡
@export_dir var creature_folder: String = "res://my_creature"
## 步驟的文字。預設是 lesson/tutorial/data/tutorial_steps.tres
@export var steps: TutorialSteps

@onready var _progress_label: Label = %ProgressLabel
@onready var _check_button: Button = %CheckButton
@onready var _play_button: Button = %PlayButton
@onready var _step_list: VBoxContainer = %StepList
@onready var _stop_layer: CanvasLayer = %StopLayer

var _rows: Array[StepRow] = []


func _ready() -> void:
	if steps == null:
		push_warning("教學關沒有設定步驟文字（steps），會顯示空白的步驟。")
		steps = TutorialSteps.new()
	for step: TutorialStep in steps.steps:
		var row: StepRow = STEP_ROW_SCENE.instantiate()
		_step_list.add_child(row)
		row.set_step(step if step != null else TutorialStep.new())
		_rows.append(row)

	_stop_layer.hide()
	_play_button.disabled = true
	_check_button.pressed.connect(run_checks)
	run_checks()


## 重新檢查所有步驟，更新畫面
func run_checks() -> void:
	var done_count: int = 0
	var extra_done_count: int = 0
	for index: int in _rows.size():
		var passed: bool = false
		_rows[index].show_result(passed, NOT_READY_MESSAGE)
		if not passed:
			continue
		if index in EXTRA_STEP_INDEXES:
			extra_done_count += 1
		else:
			done_count += 1
	var required_count: int = _rows.size() - EXTRA_STEP_INDEXES.size()
	_progress_label.text = "已完成 %d／%d 步　額外：%d／%d" % [done_count, required_count, extra_done_count, EXTRA_STEP_INDEXES.size()]
