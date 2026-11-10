extends Control
## 教學關：列出 10 個步驟，按「檢查」檢查 my_creature 資料夾裡的生物和池塘有沒有做對。
##
## 第 1～5、7～10 步：讀檔檢查（邏輯在 creature_checker.gd）。
## 第 6 步：按「試玩」在教學關裡玩標題畫面接上的池塘，玩到贏或輸才算過（中途結束不算）。
## 第 7～10 步是額外題，不算在「已完成幾步」裡，另外計算。
## 步驟的文字在 lesson/tutorial/data/tutorial_steps.tres，要改文字改那裡就好。

const STEP_ROW_SCENE: PackedScene = preload("res://lesson/tutorial/step_row.tscn")
## 額外題在列表裡是第幾個（從 0 開始）
const EXTRA_STEP_INDEXES: Array[int] = [6, 7, 8, 9]

## 要檢查的資料夾，社員的生物和池塘放這裡
@export_dir var creature_folder: String = "res://my_creature"
## 標題畫面：第 6 步檢查它的 Pond Scene 有沒有接上自己的池塘，試玩也是玩這個池塘
@export_file("*.tscn") var title_scene: String = CreatureChecker.DEFAULT_TITLE_SCENE
## 步驟的文字。預設是 lesson/tutorial/data/tutorial_steps.tres
@export var steps: TutorialSteps

@onready var _main_panel: Control = %MainPanel
@onready var _progress_label: Label = %ProgressLabel
@onready var _check_button: Button = %CheckButton
@onready var _play_label: Label = %PlayLabel
@onready var _play_button: Button = %PlayButton
@onready var _step_list: VBoxContainer = %StepList
@onready var _stop_layer: CanvasLayer = %StopLayer
@onready var _stop_button: Button = %StopButton

var _rows: Array[StepRow] = []
## 正在試玩的池塘（沒在試玩就是 null）
var _pond: Pond
## 第 6 步（試玩）有沒有過、玩到結算的是哪個池塘
var _play_succeeded: bool = false
var _played_pond: String = ""
## 試玩要玩的池塘（標題畫面接上的那個）
var _play_path: String = ""


func _ready() -> void:
	if steps == null:
		push_warning("教學關沒有設定步驟文字（steps），會顯示空白的步驟。")
		steps = TutorialSteps.new()
	for step: TutorialStep in steps.steps:
		var row: StepRow = STEP_ROW_SCENE.instantiate()
		_step_list.add_child(row)
		row.set_step(step if step != null else TutorialStep.new())
		_rows.append(row)

	# 試玩時遊戲可能暫停（結算、暫停選單），「結束試玩」還是要能按
	_stop_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_stop_layer.hide()
	_check_button.pressed.connect(run_checks)
	_play_button.pressed.connect(start_play)
	_stop_button.pressed.connect(stop_play)
	run_checks()


## 重新檢查所有步驟，更新畫面
func run_checks() -> void:
	var checker := CreatureChecker.new(creature_folder, title_scene)
	# 順序跟 tutorial_steps.tres 一樣：1～6 步，第 7～10 步是額外題
	var results: Array[CreatureChecker.Result] = [
		checker.check_copy(),
		checker.check_body(),
		checker.check_legs(),
		checker.check_tentacles(),
		checker.check_pond(),
		checker.check_title_and_play(_play_succeeded, _played_pond),
		checker.check_predator(),
		checker.check_grab(),
		checker.check_script(),
		checker.check_ornament(),
	]

	var done_count: int = 0
	var extra_done_count: int = 0
	for index: int in results.size():
		if index < _rows.size():
			_rows[index].show_result(results[index].passed, results[index].message)
		if not results[index].passed:
			continue
		if index in EXTRA_STEP_INDEXES:
			extra_done_count += 1
		else:
			done_count += 1
	var required_count: int = results.size() - EXTRA_STEP_INDEXES.size()
	_progress_label.text = "已完成 %d／%d 步　額外：%d／%d" % [done_count, required_count, extra_done_count, EXTRA_STEP_INDEXES.size()]

	_play_path = checker.get_title_pond()
	_play_button.disabled = _play_path == "" or not ResourceLoader.exists(_play_path)
	_play_label.text = "試玩：%s" % (_play_path.trim_prefix("res://") if _play_path != "" else "（標題畫面沒有接上池塘）")


## 在教學關裡開始玩標題畫面接上的池塘
func start_play() -> void:
	if _pond != null or _play_path == "":
		return
	var scene: PackedScene = ResourceLoader.load(_play_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var node: Node = scene.instantiate() if scene != null else null
	if not node is Pond:
		if node != null:
			node.queue_free()
		run_checks()
		return
	_pond = node
	_pond.game_over.connect(_on_game_over)
	_pond.exit_requested.connect(stop_play)
	_main_panel.hide()
	_stop_layer.show()
	add_child(_pond)


## 結束試玩，回到步驟列表
func stop_play() -> void:
	if _pond == null:
		return
	_pond.queue_free()
	_pond = null
	get_tree().paused = false
	_stop_layer.hide()
	_main_panel.show()
	run_checks()


## 玩到結算（贏或輸都算）
func _on_game_over(_won: bool) -> void:
	_play_succeeded = true
	_played_pond = _play_path


func _exit_tree() -> void:
	# 試玩到一半就離開教學關（例如關掉視窗）時，記得解除暫停
	if _pond != null:
		get_tree().paused = false
