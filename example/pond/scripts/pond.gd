class_name Pond
extends Node2D
## 池塘小遊戲：你的生物跟著滑鼠在池塘裡游，吃食物變長，被天敵咬到變短。
## 長到目標長度（或撐過時間、吃滿幾個）就贏，長度短到剩 2 就輸。
## 「長度」每隻生物都從 10 開始：吃一個 +1、被咬 -N，跟身體有幾節無關。
##
## 遊戲規則都是這個節點的屬性：點最上層的 Pond 節點，在右邊的檢查器改數字，就是不同的遊戲。
## 屬性的中文說明：滑鼠移到屬性名稱上就會顯示。
##
## 想做自己的池塘：把 example/pond/pond.tscn 複製到 my_creature 資料夾，
## 把「Player Creature」換成你的生物，再改至少一條規則。

## 遊戲結束時發出，won 是贏了沒
signal game_over(won: bool)

const FOOD_SCRIPT: GDScript = preload("res://example/pond/scripts/food.gd")
## 碰撞層（專案設定裡的名字：1 玩家、2 天敵、3 食物）
const PLAYER_LAYER: int = 1
const PREDATOR_LAYER: int = 2
const FOOD_LAYER: int = 4
## 被咬之後無敵幾秒、天敵退開幾秒（不然會一直連續咬）
const INVINCIBLE_TIME: float = 1.0
const RETREAT_TIME: float = 1.0

## 勝利條件、玩家控制方式的編號，跟選單的順序一樣
enum WinCondition { LENGTH, SURVIVE, EAT }
enum PlayerControl { CREATURE, MOUSE, WASD }

@export_group("遊戲")
## 遊戲名稱：顯示在左上角和結算畫面
@export var game_name: String = "池塘"
## 玩家生物：把生物場景（.tscn）拖進來
@export var player_creature: PackedScene
## 玩家控制方式：生物自己的設定（電腦控制的會改成滑鼠）、滑鼠、WASD
@export_enum("生物自己的設定", "滑鼠", "WASD") var player_control: int = PlayerControl.CREATURE
## 勝利條件：長到目標長度、撐過時間（秒）、吃滿幾個
@export_enum("長到目標長度", "撐過時間", "吃滿幾個") var win_condition: int = WinCondition.LENGTH
## 目標數值：長度幾節、撐過幾秒、吃滿幾個（看上面的勝利條件）
@export_range(1, 999, 1) var target_value: int = 20
## 時間限制（秒）：時間到還沒贏就輸，0 是不限時。勝利條件是「撐過時間」時不用這個
@export_range(0, 600, 1) var time_limit: int = 0
## 按「回標題」時換到的場景
@export_file("*.tscn") var title_scene: String = "res://game/title_screen/title_screen.tscn"

@export_group("食物")
## 食物數量：場上同時有幾個
@export_range(0, 50, 1) var food_count: int = 6
## 食物會逃跑：玩家靠近時會躲開
@export var food_flees: bool = false
## 食物顏色
@export var food_color: Color = Color("#ffd84d")

@export_group("天敵")
## 天敵生物：把生物場景（.tscn）拖進來。不管原本的控制方式，都會改成「追玩家」
@export var predator_creature: PackedScene
## 天敵數量：0 就是和平模式
@export_range(0, 20, 1) var predator_count: int = 1
## 天敵速度倍率：乘在天敵自己的速度上
@export_range(0.1, 3.0, 0.05) var predator_speed_scale: float = 0.8
## 天敵偵測距離（像素）：多近會發現玩家。0 是用天敵自己的設定
@export_range(0, 2000, 10) var predator_detect_range: float = 0.0
## 每次被咬少幾節
@export_range(1, 50, 1) var bite_damage: int = 3
## 被咬少一半：勾了就不看上面的節數，每次被咬直接少一半
@export var bite_halves: bool = false
## 天敵會變多：每長幾節就多一隻天敵，0 是不會變多
@export_range(0, 50, 1) var predator_every: int = 0

@export_group("外觀")
## 水的顏色
@export var water_color: Color = Color("#123c46")
## 背景圖：放了就蓋過水的顏色
@export var background: Texture2D
## 背景音樂（.mp3、.ogg、.wav），空著就沒有。音量跟著設定裡的「音樂」滑桿
@export var music: AudioStream

@onready var _water: Node2D = %Water
@onready var _foods: Node2D = %Foods
@onready var _creatures: Node2D = %Creatures
@onready var _hud: CanvasLayer = %HUD
@onready var _result: CanvasLayer = %Result
@onready var _pause_menu: CanvasLayer = %PauseMenu

var _player: Creature
var _predators: Array[Creature] = []
## 退開中的天敵 → 還要退幾秒
var _retreating: Dictionary = {}
var _running: bool = false
## 經過幾秒、吃了幾個、無敵到第幾秒、長到最大的等級
var _elapsed: float = 0.0
var _eaten: int = 0
var _invincible_until: float = 0.0
var _peak_level: int = 0


func _ready() -> void:
	_water.set("water_color", water_color)
	_water.set("background", background)
	_play_music()
	_result.connect("restart_pressed", start_game)
	_result.connect("title_pressed", _on_title_pressed)
	start_game()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_update_retreats(delta)
	_check_bites()
	_add_predators_if_grown()
	_check_end()
	_update_hud()


# ---------------------------------------------------------------- 開始一場


## 開始（或重新開始）一場：清掉舊的生物和食物，重新放好
func start_game() -> void:
	_clear()
	get_tree().paused = false
	_result.hide()
	_pause_menu.show()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_elapsed = 0.0
	_eaten = 0
	_invincible_until = 0.0
	_peak_level = 0

	_player = _instantiate_creature(player_creature, "玩家生物", "Player Creature")
	if _player == null:
		return
	_setup_player()
	for i: int in food_count:
		_spawn_food()
	for i: int in predator_count:
		_spawn_predator()
	_running = true
	_update_hud()


func _setup_player() -> void:
	match player_control:
		PlayerControl.MOUSE:
			_player.control_mode = Creature.Mode.MOUSE
		PlayerControl.WASD:
			_player.control_mode = Creature.Mode.WASD
		_:
			if _player.control_mode != Creature.Mode.MOUSE and _player.control_mode != Creature.Mode.WASD:
				_player.control_mode = Creature.Mode.MOUSE
	_player.position = get_viewport_rect().get_center()
	_player.heading = 0.0
	_creatures.add_child(_player)
	_player.set_collision(PLAYER_LAYER, FOOD_LAYER)
	_player.ate.connect(_on_player_ate)
	_player.died.connect(_on_player_died)


func _spawn_food() -> void:
	var food: Node2D = FOOD_SCRIPT.new()
	food.set("color", food_color)
	food.set("flees", food_flees)
	food.set("player", _player)
	_foods.add_child(food)
	food.call("respawn")


## 在畫面邊緣放一隻天敵，離玩家遠一點，頭朝畫面中間
func _spawn_predator() -> void:
	var predator: Creature = _instantiate_creature(predator_creature, "天敵生物", "Predator Creature")
	if predator == null:
		return
	predator.control_mode = Creature.Mode.CHASE
	predator.speed *= predator_speed_scale
	if predator_detect_range > 0.0:
		predator.detect_range = predator_detect_range
	var area: Rect2 = get_viewport_rect().grow(-60.0)
	for i: int in 20:
		predator.position = _random_edge_point(area)
		if predator.position.distance_to(_player.global_position) > 300.0:
			break
	predator.heading = (area.get_center() - predator.position).angle()
	predator.add_to_group("predator")
	_creatures.add_child(predator)
	predator.set_collision(PREDATOR_LAYER, PLAYER_LAYER)
	_predators.append(predator)


func _random_edge_point(area: Rect2) -> Vector2:
	match randi() % 4:
		0:
			return Vector2(area.position.x, randf_range(area.position.y, area.end.y))
		1:
			return Vector2(area.end.x, randf_range(area.position.y, area.end.y))
		2:
			return Vector2(randf_range(area.position.x, area.end.x), area.position.y)
	return Vector2(randf_range(area.position.x, area.end.x), area.end.y)


## 產生一隻生物；場景沒設定或根節點不是 Creature 時，在畫面上顯示提示並回傳 null
func _instantiate_creature(scene: PackedScene, label: String, property_name: String) -> Creature:
	if scene == null:
		_hud.call("show_message", "還沒有設定%s。\n請點 Pond 節點，把生物場景拖進檢查器的「%s」。" % [label, property_name])
		return null
	var node: Node = scene.instantiate()
	if not node is Creature:
		node.queue_free()
		_hud.call("show_message", "%s的根節點不是 Creature。\n請確認「%s」拖進來的是生物場景。" % [label, property_name])
		return null
	return node


## 清掉上一場的生物和食物
func _clear() -> void:
	_running = false
	for node: Node in _creatures.get_children() + _foods.get_children():
		# 先移出群組，新的一場才不會找到快要消失的舊生物
		for group: StringName in node.get_groups():
			node.remove_from_group(group)
		node.queue_free()
	_player = null
	_predators.clear()
	_retreating.clear()


# ---------------------------------------------------------------- 遊戲中


## 天敵咬到玩家：玩家變短、閃紅、無敵 1 秒；天敵退開 1 秒
func _check_bites() -> void:
	if _elapsed < _invincible_until:
		return
	for predator: Creature in _predators:
		if _retreating.has(predator) or predator.head_area == null:
			continue
		for area: Area2D in predator.head_area.get_overlapping_areas():
			if area.get_meta("creature", null) == _player:
				_bite(predator)
				return


func _bite(predator: Creature) -> void:
	_invincible_until = _elapsed + INVINCIBLE_TIME
	predator.control_mode = Creature.Mode.FLEE
	_retreating[predator] = RETREAT_TIME
	_flash_hurt()
	var amount: int = maxi(ceili(_player.get_length() / 2.0), 1) if bite_halves else bite_damage
	_player.shrink(amount)


## 退開的時間到了，天敵回去追玩家
func _update_retreats(delta: float) -> void:
	for predator: Creature in _retreating.keys():
		_retreating[predator] -= delta
		if _retreating[predator] <= 0.0:
			_retreating.erase(predator)
			if is_instance_valid(predator):
				predator.control_mode = Creature.Mode.CHASE


## 天敵會變多：每長 predator_every 節多一隻（變短不會變少）
func _add_predators_if_grown() -> void:
	_peak_level = maxi(_peak_level, _player.level)
	if predator_every <= 0:
		return
	var wanted: int = predator_count + floori(float(_peak_level) / predator_every)
	while _predators.size() < wanted:
		var before: int = _predators.size()
		_spawn_predator()
		if _predators.size() == before:
			return


func _check_end() -> void:
	match win_condition:
		WinCondition.LENGTH:
			if _player.get_length() >= target_value:
				_finish(true, "你贏了！")
				return
		WinCondition.SURVIVE:
			if _elapsed >= target_value:
				_finish(true, "撐過去了！")
				return
		WinCondition.EAT:
			if _eaten >= target_value:
				_finish(true, "吃飽了！")
				return
	if time_limit > 0 and win_condition != WinCondition.SURVIVE and _elapsed >= time_limit:
		_finish(false, "時間到了！")


func _update_hud() -> void:
	var status: String = ""
	match win_condition:
		WinCondition.LENGTH:
			status = "長度 %d / %d" % [_player.get_length(), target_value]
		WinCondition.SURVIVE:
			status = "還要撐 %d 秒　長度 %d" % [ceili(target_value - _elapsed), _player.get_length()]
		WinCondition.EAT:
			status = "吃了 %d / %d" % [_eaten, target_value]
	if time_limit > 0 and win_condition != WinCondition.SURVIVE:
		status += "\n剩 %d 秒" % ceili(maxf(time_limit - _elapsed, 0.0))
	_hud.call("show_status", game_name, status)


## 遊戲結束：暫停遊戲、顯示結算
func _finish(won: bool, title: String) -> void:
	if not _running:
		return
	_running = false
	get_tree().paused = true
	# 結算時不能再打開暫停選單（關掉選單會解除暫停）
	_pause_menu.hide()
	_pause_menu.process_mode = Node.PROCESS_MODE_DISABLED
	var detail: String = "長度 %d　吃了 %d 個　%d 秒" % [_player.get_length(), _eaten, int(_elapsed)]
	_result.call("show_result", won, title, detail)
	game_over.emit(won)


# ---------------------------------------------------------------- 效果、訊號


func _on_player_ate(_food: Node) -> void:
	_eaten += 1
	# 吃到東西：身體鼓起來再縮回去（放大彈跳）
	var tween: Tween = _player.create_tween()
	_player.scale = Vector2(1.3, 1.3)
	tween.tween_property(_player, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 被咬：閃紅，無敵的這段時間一直閃爍
func _flash_hurt() -> void:
	var tween: Tween = _player.create_tween()
	_player.modulate = Color(1.0, 0.3, 0.3)
	tween.tween_property(_player, "modulate", Color(1, 1, 1, 0.4), INVINCIBLE_TIME / 4.0)
	tween.tween_property(_player, "modulate", Color.WHITE, INVINCIBLE_TIME / 4.0)
	tween.tween_property(_player, "modulate", Color(1, 1, 1, 0.4), INVINCIBLE_TIME / 4.0)
	tween.tween_property(_player, "modulate", Color.WHITE, INVINCIBLE_TIME / 4.0)


func _on_player_died() -> void:
	_finish(false, "被吃掉了……")


func _on_title_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(title_scene)


func _play_music() -> void:
	if music == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	player.stream = music
	player.bus = &"Music"
	player.process_mode = Node.PROCESS_MODE_ALWAYS  # 結算、暫停時音樂不停
	player.finished.connect(player.play)
	add_child(player)
	player.play()
