extends Node2D
## 主題課投影片用的動圖：幾隻範例生物在水裡游（1280 × 720 橫式，沒有字幕）。
## 匯出時不會帶進去。錄影（在內層專案資料夾執行，Godot 換成自己的路徑）：
##   Godot --path . --write-movie <資料夾>/frame.png --fixed-fps 20 res://_system/showcase/slide_swim.tscn
## 前 WARMUP 秒讓生物先游起來，轉 GIF 時剪掉。

## 畫面大小
const SCREEN: Vector2i = Vector2i(1280, 720)
## 開頭前先游幾秒
const WARMUP: float = 2.0
## 正式錄幾秒
const DURATION: float = 8.0
## 鏡頭放大倍率（越大生物看起來越大）
const ZOOM: float = 1.25
## 沿著橢圓游時，瞄準前面多遠的角度（弧度）
const LANE_LEAD: float = 0.6
## 離別隻多近就開始閃開
const PERSONAL_SPACE: float = 140.0

## 每隻生物：設計檔、橢圓中心（畫面比例）、橢圓半徑、反方向繞、起點（0～1）、速度倍率
const ACTORS: Array = [
	["res://example/creatures/dragon/design.tres", Vector2(0.5, 0.5), Vector2(0.38, 0.3), false, 0.0, 0.7],
	["res://example/creatures/snake/design.tres", Vector2(0.3, 0.38), Vector2(0.2, 0.18), true, 0.25, 0.7],
	["res://example/creatures/centipede/design.tres", Vector2(0.7, 0.58), Vector2(0.2, 0.2), false, 0.5, 0.6],
	["res://example/creatures/octopus/design.tres", Vector2(0.5, 0.62), Vector2(0.25, 0.14), true, 0.8, 0.6],
	["res://example/creatures/spider/design.tres", Vector2(0.24, 0.66), Vector2(0.13, 0.12), false, 0.6, 0.5],
	["res://example/creatures/jellyfish/design.tres", Vector2(0.76, 0.32), Vector2(0.14, 0.12), true, 0.1, 0.6],
]

var _time: float = -WARMUP
var _world: Vector2
var _creatures: Array[Creature] = []

@onready var _water: Node2D = %Water
@onready var _plants: Node2D = %Plants
@onready var _creature_layer: Node2D = %Creatures
@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	get_window().size = SCREEN
	get_window().content_scale_size = SCREEN
	_world = Vector2(SCREEN) / ZOOM
	WaterFlow.strength = 25.0
	WaterFlow.fixed_time = 0.0
	_water.set("world_size", _world)
	_camera.zoom = Vector2.ONE * ZOOM
	_camera.position = _world / 2.0
	_add_plants()
	for i: int in ACTORS.size():
		_spawn(i)


func _exit_tree() -> void:
	WaterFlow.reset()


func _process(delta: float) -> void:
	_time += delta
	WaterFlow.fixed_time = _time + 100.0  # 固定時間，錄出來每次都一樣
	if _time >= DURATION:
		get_tree().quit()


## 放第 i 隻：放在自己的橢圓上，頭朝前進方向
func _spawn(i: int) -> void:
	var data: Array = ACTORS[i]
	var creature := Creature.new()
	creature.design = load(data[0])
	creature.control_mode = Creature.Mode.WANDER
	creature.bounds = Rect2(-_world.x, -_world.y, _world.x * 3.0, _world.y * 3.0)
	_creature_layer.add_child(creature)
	creature.brain = _brain.bind(i)
	_creatures.append(creature)
	var angle: float = data[4] * TAU
	var at: Vector2 = _lane_point(data, angle)
	creature.global_position = at
	creature.heading = (_lane_point(data, angle + _lane_dir(data) * 0.1) - at).angle()
	creature.reset_pose()


## 大腦：沿著自己的橢圓游，碰到別隻就閃開
func _brain(index: int) -> Dictionary:
	var data: Array = ACTORS[index]
	var creature: Creature = _creatures[index]
	var here: Vector2 = creature.global_position
	var offset: Vector2 = (here - data[1] * _world) / (data[2] * _world)
	var target: Vector2 = _lane_point(data, offset.angle() + _lane_dir(data) * LANE_LEAD)
	var direction: Vector2 = (target - here).normalized() + _avoid(index) * 2.5
	return {"angle": direction.angle(), "speed": creature.speed * data[5]}


## 附近別隻的每一節都把自己往外推
func _avoid(index: int) -> Vector2:
	var here: Vector2 = _creatures[index].global_position
	var push: Vector2 = Vector2.ZERO
	for j: int in _creatures.size():
		if j == index:
			continue
		var body: ChainBody = _creatures[j].get_body()
		var points: PackedVector2Array = body.get_points() if body != null else PackedVector2Array([_creatures[j].global_position])
		for point: Vector2 in points:
			var distance: float = here.distance_to(point)
			if distance < PERSONAL_SPACE and distance > 0.01:
				push += (here - point) / distance * (1.0 - distance / PERSONAL_SPACE)
	return push.limit_length(3.0)


func _lane_point(data: Array, angle: float) -> Vector2:
	return data[1] * _world + Vector2(cos(angle), sin(angle)) * data[2] * _world


func _lane_dir(data: Array) -> float:
	return -1.0 if data[3] else 1.0


## 底下的水草和海葵（跟展示場景一樣）
func _add_plants() -> void:
	var bottom: float = _world.y - 26.0
	var weeds: Array = [[0.04, 140.0, -0.1], [0.15, 90.0, 0.15], [0.33, 170.0, -0.2], [0.62, 120.0, 0.12], [0.85, 190.0, -0.15], [0.96, 100.0, 0.2]]
	for item: Array in weeds:
		var weed := Weed.new()
		weed.position = Vector2(_world.x * item[0], bottom)
		weed.height = item[1]
		weed.segment_count = maxi(4, roundi(item[1] / 20.0))
		weed.lean = item[2]
		_plants.add_child(weed)
	var anemones: Array = [[0.24, Color("#c2185b"), Color("#ec407a"), Color("#ffd1e0")], [0.73, Color("#d9730d"), Color("#fa9a33"), Color("#ffe69a")]]
	for item: Array in anemones:
		var anemone := Anemone.new()
		anemone.position = Vector2(_world.x * item[0], bottom + 4.0)
		anemone.fan_angle = deg_to_rad(200.0)
		anemone.body_color = item[1]
		anemone.arm_base_color = item[2]
		anemone.arm_tip_color = item[3]
		_plants.add_child(anemone)
