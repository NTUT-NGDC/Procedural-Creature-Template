extends Node2D
## 開發用沙盒：放一隻生物，看它的動作對不對。匯出時不會帶進去。
##
## 左上角可以換生物、換控制方式、讓牠長大或變短。按 F1 顯示骨架。
## 按滑鼠右鍵放食物（測試觸手「抓最近的食物」），頭碰到食物也會吃掉。
## 生物清單會列出下面幾個資料夾裡的 .tscn（根節點要是 Creature），以及設計檔（<名字>/design.tres）。

const CREATURE_FOLDERS: PackedStringArray = ["res://example/creatures/", "res://_system/sandbox/creatures/"]
## 設計檔放在這些資料夾的子資料夾裡（<名字>/design.tres）
const DESIGN_FOLDERS: PackedStringArray = ["res://example/creatures/", "res://my_creature/"]
## 控制方式選單的文字，順序跟 Creature 的「控制方式」一樣
const MODE_NAMES: PackedStringArray = ["玩家（滑鼠）", "玩家（WASD）", "漫遊", "追玩家", "躲玩家"]
const FOOD_SCRIPT: GDScript = preload("res://_system/sandbox/scripts/sandbox_food.gd")
## 一開始放幾個食物
const START_FOOD: int = 6

@onready var _creature_option: OptionButton = %CreatureOption
@onready var _mode_option: OptionButton = %ModeOption
@onready var _grow_button: Button = %GrowButton
@onready var _shrink_button: Button = %ShrinkButton
@onready var _info_label: Label = %InfoLabel

var _paths: PackedStringArray = []
var _creature: Creature


func _ready() -> void:
	for folder: String in CREATURE_FOLDERS:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file: String in DirAccess.get_files_at(folder):
			if file.get_extension() == "tscn":
				_paths.append(folder + file)
				_creature_option.add_item(file.get_basename())
	# 設計檔：資料夾裡每個子資料夾的 design.tres（範例和社員自己的生物）
	for folder: String in DESIGN_FOLDERS:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for sub: String in DirAccess.get_directories_at(folder):
			var path: String = folder + sub + "/design.tres"
			if ResourceLoader.exists(path):
				_paths.append(path)
				_creature_option.add_item("%s（設計檔）" % sub)
	for mode_name: String in MODE_NAMES:
		_mode_option.add_item(mode_name)

	_creature_option.item_selected.connect(_spawn)
	_mode_option.item_selected.connect(_on_mode_selected)
	_grow_button.pressed.connect(_on_grow_pressed)
	_shrink_button.pressed.connect(_on_shrink_pressed)
	if not _paths.is_empty():
		_spawn(0)
	for _i: int in START_FOOD:
		_add_food(Vector2(randf_range(100, 1180), randf_range(100, 620)))


func _process(_delta: float) -> void:
	if _creature == null:
		_info_label.text = "沒有找到生物場景"
		return
	_info_label.text = "長度 %d　等級 %d　FPS %d\nF1：顯示骨架" % [_creature.get_length(), _creature.level, Engine.get_frames_per_second()]


## 換成清單裡第 index 隻生物，放在畫面中央
func _spawn(index: int) -> void:
	if _creature != null:
		_creature.queue_free()
		_creature = null
	var node: Node = _load_creature(_paths[index])
	if not node is Creature:
		push_warning("%s 的根節點不是 Creature" % _paths[index])
		if node != null:
			node.queue_free()
		return
	_creature = node
	_creature.control_mode = _mode_option.selected
	_creature.position = get_viewport_rect().get_center()
	add_child(_creature)


## .tscn 就實例化；設計檔就新增一個 Creature、把設計檔放進去
func _load_creature(path: String) -> Node:
	var resource: Resource = load(path)
	if resource is CreatureDesign:
		var creature := Creature.new()
		creature.design = resource
		return creature
	return (resource as PackedScene).instantiate() if resource is PackedScene else null


func _on_mode_selected(index: int) -> void:
	if _creature != null:
		_creature.control_mode = index


func _on_grow_pressed() -> void:
	if _creature != null:
		_creature.grow(1)


func _on_shrink_pressed() -> void:
	if _creature != null:
		_creature.shrink(1)


func _unhandled_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		_add_food(get_global_mouse_position())


func _add_food(at: Vector2) -> void:
	var food: Node2D = FOOD_SCRIPT.new()
	food.position = at
	add_child(food)


## 頭碰到食物就吃掉（沙盒簡單算距離）
func _eat_with_head() -> void:
	for node: Node in get_tree().get_nodes_in_group("food"):
		var food: Node2D = node as Node2D
		if food.global_position.distance_to(_creature.global_position) < _creature.head_radius + 6.0:
			food.remove_from_group("food")
			_creature.eat(food)
