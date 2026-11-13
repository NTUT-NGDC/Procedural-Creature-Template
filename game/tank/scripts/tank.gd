@tool
class_name Tank
extends Node2D
## 生態缸：你的生物跟著滑鼠游，點一下放飼料，吃滿就升級，照長大方式長大。
## 大吃小：咬到比你小的生物的頭就吃掉牠；頭撞到別人的身體會掉級；按住空白鍵或右鍵加速。
## NPC 大大小小：比自己小的追、比自己大的逃（大腦寫在 npc_brain.gd），被吃掉過一下會再生一隻。
## 規則寫在 tank_rules.gd，這裡是「裁判」：每一幀檢查每一對生物，照規則處理。
## 水流推著水草、海葵、觸手、飼料，整缸一起晃。沒有輸贏、沒有時間限制。
##
## 玩家生物由標題畫面交過來（標題畫面的「玩家生物」欄位，拖自己的 design.tres）。
## 直接執行這個場景（F6）時用下面「玩家生物」欄位的設計檔。
## 地圖比畫面大，鏡頭跟著玩家走。編輯器裡看到的那一整片水就是地圖範圍。
## 水草、海葵預先擺在 Plants 節點底下，可以在編輯器裡直接拖、加、刪（數量有上限）。
## 這個場景的設定由社長維護，社員不用改。

## 畫面外多遠以內還是照常畫、照常動（像素），太近的話游進畫面時會看到東西突然出現
const OFFSCREEN_MARGIN: float = 100.0
## 生物的腳、觸手會伸出身體外面多遠（像素），判斷生物在不在畫面裡時加上去
const PART_REACH: float = 150.0
## 生物掉出來的飼料，幾秒之後才能吃
const DROPPED_FOOD_WAIT: float = 0.6
const MAX_PLANTS_WARNING: String = "水草、海葵太多了（%d 個，上限 %d），多的先藏起來，網頁版才跑得動"

@export_group("遊戲")
## 遊戲名稱：顯示在左上角
@export var game_name: String = "生態缸"
## 玩家生物（設計檔）。從標題畫面開始時，會換成標題畫面設定的設計檔
@export var player_design: CreatureDesign
## 平衡資料：能力、升級、大吃小、飼料的所有數字。空的就用預設的 game/creature_parts/data/balance.tres
@export var balance: CreatureBalance
## 地圖大小（像素）：一個畫面是 1280 × 720。鏡頭跟著玩家走，到邊緣就停住
@export var world_size: Vector2 = Vector2(2560, 1440):
	set(value):
		world_size = value.max(TankWater.SCREEN)  # 不能比一個畫面小
		if is_node_ready():
			_water.set("world_size", world_size)

@export_group("NPC")
## NPC 用哪些設計檔（每次隨機挑一份）。放不同長大方式、不同零件的，缸裡才熱鬧
@export var npc_designs: Array[CreatureDesign] = [
	preload("res://example/creatures/centipede/design.tres"),
	preload("res://example/creatures/doodle/design.tres"),
	preload("res://example/creatures/dragon/design.tres"),
	preload("res://example/creatures/jellyfish/design.tres"),
	preload("res://example/creatures/octopus/design.tres"),
	preload("res://example/creatures/predator_eel/design.tres"),
	preload("res://example/creatures/snake/design.tres"),
	preload("res://example/creatures/spider/design.tres"),
]
## 缸裡總共幾隻生物（玩家＋NPC）：NPC 的數量＝這個數字－玩家人數
@export_range(1, 40, 1) var population: int = 10
## 網頁版缸裡最多幾隻（網頁版比較慢，會自動減少到這個數字）
@export_range(1, 40, 1) var web_population: int = 6
## NPC 最高幾級（吃再多也不會再長大），避免整缸越長越大
@export_range(0, 50, 1) var npc_max_level: int = 12
## NPC 一出生的等級：玩家的等級加減這麼多（隨機），缸裡才一直有比你大的和比你小的
@export_range(0, 20, 1) var npc_level_spread: int = 3
## NPC 被吃掉之後，幾秒再生一隻
@export_range(0, 30, 0.5) var npc_respawn_time: float = 3.0

@export_group("食物")
## 飼料的顏色（多久長一個、最多幾個在平衡資料裡）
@export var food_color: Color = Color("#ffd84d")

@export_group("水流")
## 水流強度（像素／秒），0 是靜水
@export_range(0, 200, 1) var flow_strength: float = 25.0
## 波的大小（像素）：越大一大片水往同一邊流，越小越亂
@export_range(50, 2000, 10) var flow_wave_size: float = 300.0
## 水流變化的速度
@export_range(0, 5, 0.05) var flow_speed: float = 0.6

@export_group("水草")
## 水草、海葵最多幾個（網頁版的效能）
@export_range(0, 200, 1) var max_plants: int = 40

@export_group("外觀")
## 水的顏色
@export var water_color: Color = Color("#123c46")
## 背景圖：放了就蓋過水的顏色
@export var background: Texture2D
## 背景音樂（.mp3、.ogg、.wav），空著就沒有。音量跟著設定裡的「音樂」滑桿
@export var music: AudioStream

@onready var _water: Node2D = %Water
@onready var _plants: Node2D = %Plants
@onready var _foods: Node2D = %Foods
@onready var _creatures: Node2D = %Creatures
@onready var _hud: CanvasLayer = %HUD

## 玩家的生物
var player: Creature
## 跟著玩家的鏡頭（執行時才建立）
var camera: Camera2D
## 玩家到過的最高等級、吃掉幾隻生物（顯示在 HUD）
var best_level: int = 0
var kills: int = 0
var _food_timer: float = 0.0
var _respawn_timer: float = 0.0
## 沒有被上限藏起來的水草、海葵（畫面外的會暫停）
var _active_plants: Array[Node2D] = []


func _ready() -> void:
	_water.set("world_size", world_size)
	if Engine.is_editor_hint():
		return  # 編輯器裡只畫水和水草，不開始遊戲
	if OS.has_feature("web"):
		population = mini(population, web_population)
	WaterFlow.strength = flow_strength
	WaterFlow.wave_size = flow_wave_size
	WaterFlow.speed = flow_speed
	_water.set("water_color", water_color)
	_water.set("background", background)
	_play_music()
	_limit_plants()
	_create_camera()
	_spawn_player()
	for i: int in npc_target_count():
		spawn_npc()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		WaterFlow.reset()  # 回到標題、工坊時是靜水


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_grow_food(delta)
	_keep_population(delta)
	_eat_food()
	_judge_creatures()
	_update_marks()
	_follow_player()
	_skip_offscreen()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		drop_food(get_global_mouse_position())


# ---------------------------------------------------------------- 生物


func _spawn_player() -> void:
	if player_design == null:
		_hud.call("show_message", "還沒有設定玩家生物。\n請點標題畫面的 TitleScreen 節點，把你的 design.tres 拖進「Player Design」。")
		return
	player = Creature.new()
	player.name = "Player"
	player.design = player_design
	player.control_mode = Creature.Mode.MOUSE
	player.position = world_size / 2.0
	add_creature(player)
	camera.global_position = player.global_position
	camera.reset_smoothing()


## NPC 該有幾隻：缸裡總數－玩家人數
func npc_target_count() -> int:
	return maxi(population - get_tree().get_node_count_in_group("player"), 0)


## 現在有幾隻 NPC（被吃掉、還沒消失的不算）
func npc_count() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if not node.is_queued_for_deletion():
			count += 1
	return count


## NPC 不夠就倒數，時間到再生一隻（一次一隻）
func _keep_population(delta: float) -> void:
	if npc_count() >= npc_target_count():
		_respawn_timer = npc_respawn_time
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = npc_respawn_time
		spawn_npc()


## 生一隻 NPC：隨機挑一份設計檔，等級在玩家附近，放在離大家遠的地方，用 npc_brain.gd 的大腦
func spawn_npc() -> Creature:
	if npc_designs.is_empty():
		return null
	var npc := Creature.new()
	npc.design = npc_designs.pick_random()
	npc.control_mode = Creature.Mode.WANDER
	npc.max_level = npc_max_level
	var base: int = player.level if player != null else 0
	npc.level = clampi(base + randi_range(-npc_level_spread, npc_level_spread), 0, npc_max_level)
	npc.position = _safe_spot()
	npc.heading = randf() * TAU
	npc.brain = func() -> Dictionary: return NpcBrain.choose_target(npc, get_creatures(), _foods.get_children())
	npc.add_to_group("npc")
	add_creature(npc)
	return npc


## 平衡資料（沒有指定就用預設的）
func get_balance() -> CreatureBalance:
	if balance == null:
		balance = CreatureBalance.get_default()
	return balance


## 把生物放進缸裡：設好範圍，加速消耗的飼料從尾巴掉出來
func add_creature(creature: Creature) -> void:
	creature.bounds = world_rect()
	creature.balance = get_balance()
	creature.boost_spent.connect(func(at: Vector2) -> void: drop_food(at, true))
	_creatures.add_child(creature)


## 缸裡活著的生物
func get_creatures() -> Array[Creature]:
	var result: Array[Creature] = []
	for node: Node in _creatures.get_children():
		var creature: Creature = node as Creature
		if creature != null and not creature.is_queued_for_deletion():
			result.append(creature)
	return result


# ---------------------------------------------------------------- 大吃小（裁判）


## 每一對生物：A 的頭碰到 B 的頭 → 大的吃掉小的、差不多大就彈開；A 的頭撞到 B 的身體 → A 掉級
func _judge_creatures() -> void:
	var creatures: Array[Creature] = get_creatures()
	var rects: Dictionary = {}  # 每隻生物佔的範圍，先算好
	for creature: Creature in creatures:
		rects[creature] = TankRules.body_rect(creature)
	for a: Creature in creatures:
		for b: Creature in creatures:
			if a == b or a.is_invincible() or b.is_invincible() or a.is_queued_for_deletion() or b.is_queued_for_deletion():
				continue
			if not (rects[b] as Rect2).has_point(a.global_position):
				continue  # A 的頭離 B 很遠：不可能碰到
			var balance: CreatureBalance = a.get_balance()
			match TankRules.contact(a, b, balance):
				TankRules.Contact.HEAD:
					if TankRules.can_eat(a, b, balance):
						_kill(b, a)
					elif TankRules.can_eat(b, a, balance):
						_kill(a, b)
					else:
						_bounce(a, b.global_position, balance.bounce_speed)
						_bounce(b, a.global_position, balance.bounce_speed)
				TankRules.Contact.BODY:
					_hit(a, b)


## victim 被 eater 吃掉：沿著身體散成一串飼料，玩家重生、其他生物消失
func _kill(victim: Creature, eater: Creature) -> void:
	var balance: CreatureBalance = victim.get_balance()
	var body: ChainBody = victim.get_body()
	var along: PackedVector2Array = body.get_joints() if body != null else PackedVector2Array([victim.global_position])
	_scatter_food(along, TankRules.dropped_food(victim.level + 1, balance))
	if eater == player:
		kills += 1
		_hud.call("show_message", "吃掉一隻！", 1.5)
	if victim == player:
		_respawn_player()
	else:
		victim.queue_free()


## a 的頭撞到 b 的身體：a 掉「b 的等級」級，掉的變成飼料，彈開、無敵一下
func _hit(a: Creature, b: Creature) -> void:
	var balance: CreatureBalance = a.get_balance()
	var lost: int = a.lose_levels(TankRules.hit_damage(b.level))
	_scatter_food(PackedVector2Array([a.global_position]), TankRules.dropped_food(lost, balance))
	_bounce(a, _nearest_joint(b, a.global_position), balance.bounce_speed)
	a.invincible_time = balance.hit_invincible
	if a == player:
		_hud.call("show_message", "撞到別人的身體，掉了 %d 級" % lost if lost > 0 else "撞到別人的身體！", 1.5)


## 把生物往「離開 from」的方向彈開
func _bounce(creature: Creature, from: Vector2, bounce_speed: float) -> void:
	var away: Vector2 = creature.global_position - from
	creature.knockback = (away.normalized() if away != Vector2.ZERO else Vector2.from_angle(randf() * TAU)) * bounce_speed


func _nearest_joint(creature: Creature, to: Vector2) -> Vector2:
	var body: ChainBody = creature.get_body()
	if body == null:
		return creature.global_position
	var nearest: Vector2 = body.get_joint(0)
	for i: int in body.joint_count():
		if body.get_joint(i).distance_to(to) < nearest.distance_to(to):
			nearest = body.get_joint(i)
	return nearest


## 玩家被吃掉：回到 0 級，在附近沒有大生物的地方重生，無敵一下
func _respawn_player() -> void:
	player.set_level(0)
	player.global_position = _safe_spot(player)
	player.knockback = Vector2.ZERO
	player.reset_pose()
	player.invincible_time = player.get_balance().respawn_invincible
	camera.global_position = player.global_position
	camera.reset_smoothing()
	_hud.call("show_message", "被吃掉了！從 0 級重新開始", 2.5)


## 找一個離其他生物（ignore 以外）遠一點的地方（試幾次，找最遠的）
func _safe_spot(ignore: Creature = null) -> Vector2:
	var best: Vector2 = world_size / 2.0
	var best_distance: float = -1.0
	for i: int in 20:
		var spot := Vector2(randf_range(100.0, world_size.x - 100.0), randf_range(100.0, floor_y() - 100.0))
		var nearest: float = INF
		for creature: Creature in get_creatures():
			if creature != ignore:
				nearest = minf(nearest, creature.global_position.distance_to(spot))
		if nearest > best_distance:
			best = spot
			best_distance = nearest
	return best


## 標記：玩家視野裡，能吃玩家的眼睛變紅、玩家吃得掉的外框變綠
func _update_marks() -> void:
	var sight: float = player.get_stats().sight if player != null and player.get_stats() != null else 0.0
	for creature: Creature in get_creatures():
		var mark: int = Creature.Mark.NONE
		if creature != player and player != null and creature.global_position.distance_to(player.global_position) <= sight:
			if TankRules.can_eat(creature, player, creature.get_balance()):
				mark = Creature.Mark.DANGER
			elif TankRules.can_eat(player, creature, player.get_balance()):
				mark = Creature.Mark.PREY
		creature.mark = mark


# ---------------------------------------------------------------- 地圖、鏡頭


## 整張地圖的範圍（全局座標）
func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, world_size)


## 鏡頭：跟著玩家，到地圖邊緣就停住（看不到地圖外面）
func _create_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world_size.x)
	camera.limit_bottom = int(world_size.y)
	camera.position = world_size / 2.0
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()


func _follow_player() -> void:
	if player != null:
		camera.global_position = player.global_position


# ---------------------------------------------------------------- 食物


## 放一個飼料（場上太多就不放；force 是生物掉出來的，一定放）。回傳放了沒
func drop_food(at: Vector2, force: bool = false) -> bool:
	if _foods.get_child_count() >= get_balance().max_food and not force:
		return false
	var food := Food.new()
	food.color = food_color
	food.floor_y = floor_y()
	food.max_x = world_size.x
	food.wait = DROPPED_FOOD_WAIT if force else 0.0
	food.position = at
	_foods.add_child(food)
	return true


## 沿著 along 這串點平均掉 count 個飼料（生物被吃掉、掉級時），每個稍微散開一點
func _scatter_food(along: PackedVector2Array, count: int) -> void:
	for i: int in count:
		var at: Vector2 = along[floori(float(i) / count * along.size())]
		drop_food((at + Vector2.from_angle(randf() * TAU) * randf_range(4.0, 20.0)).clamp(Vector2.ZERO, Vector2(world_size.x, floor_y())), true)


## 缸裡自己長食物：每隔一段時間，在地圖上隨機的地方冒出一個
func _grow_food(delta: float) -> void:
	var interval: float = get_balance().food_interval
	if interval <= 0.0:
		return
	_food_timer += delta
	while _food_timer >= interval:
		_food_timer -= interval
		drop_food(Vector2(randf_range(40.0, world_size.x - 40.0), randf_range(40.0, floor_y() - 40.0)))


## 頭碰到飼料就吃掉（每隻生物都一樣，之後的 NPC 也用這個）
func _eat_food() -> void:
	# 先把「現在能吃的飼料」和位置整理成一份（飼料很多、生物很多時，比每隻生物都重找一次快）
	var foods: Array[Node] = get_tree().get_nodes_in_group("food")
	var spots := PackedVector2Array()
	for food: Node in foods:
		spots.append((food as Node2D).global_position)
	for creature: Creature in get_creatures():
		var reach: float = creature.head_radius + Food.RADIUS
		for i: int in spots.size():
			if spots[i].distance_to(creature.global_position) <= reach and foods[i].is_in_group("food"):
				creature.eat(foods[i])  # 吃掉之後就不在 "food" 群組了，別隻不會再吃到


## 地板的高度（全局 y）：飼料沉到這裡停
func floor_y() -> float:
	return world_size.y - float(_water.get("sand_height")) - Food.RADIUS


# ---------------------------------------------------------------- 其他


## 畫面外的東西不用畫：生物、飼料藏起來（還是照常游、照常吃，只有腳、觸手、眼睛這些裝飾的動作先停），
## 水草、海葵連動都先停
## （地圖是畫面的好幾倍大，全部都畫、都動，網頁版會跑不動）
func _skip_offscreen() -> void:
	var view := Rect2(camera.get_screen_center_position() - TankWater.SCREEN / 2.0, TankWater.SCREEN).grow(OFFSCREEN_MARGIN)
	for plant: Node2D in _active_plants:
		var on_screen: bool = view.has_point(plant.global_position)
		plant.visible = on_screen
		plant.process_mode = Node.PROCESS_MODE_INHERIT if on_screen else Node.PROCESS_MODE_DISABLED
	for creature: Creature in get_creatures():
		creature.set_on_screen(view.intersects(TankRules.body_rect(creature).grow(PART_REACH)))
	for food: Node in _foods.get_children():
		(food as Node2D).visible = view.has_point((food as Node2D).global_position)


## 水草、海葵太多時，多的藏起來、不動，並顯示提示
func _limit_plants() -> void:
	var plants: Array[Node] = _plants.get_children()
	for i: int in mini(plants.size(), max_plants):
		_active_plants.append(plants[i] as Node2D)
	if plants.size() <= max_plants:
		return
	for i: int in range(max_plants, plants.size()):
		var plant: Node2D = plants[i] as Node2D
		plant.hide()
		plant.process_mode = Node.PROCESS_MODE_DISABLED
	push_warning(MAX_PLANTS_WARNING % [plants.size(), max_plants])
	_hud.call("show_message", MAX_PLANTS_WARNING % [plants.size(), max_plants], 4.0)


func _update_hud() -> void:
	if player == null:
		return
	var stats: CreatureStats = player.get_stats()
	if stats == null:
		return
	var balance: CreatureBalance = player.get_balance()
	var stars: Callable = func(ability: String) -> String:
		var count: int = stats.stars(ability, balance.max_stars)
		return "★".repeat(count) + "☆".repeat(balance.max_stars - count)
	best_level = maxi(best_level, player.level)
	_hud.call("show_status", game_name, "等級 %d　再吃 %d 個升級　最高 %d 級　吃掉 %d 隻\n速度 %s　轉向 %s　抓取 %s　視野 %s\n空白鍵／右鍵：加速（消耗吃到一半的飼料）" % [
		player.level, stats.level_cost - player.food_progress, best_level, kills,
		stars.call("speed"), stars.call("turn"), stars.call("grab"), stars.call("sight")])


func _play_music() -> void:
	if music == null:
		return
	var music_player := AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.stream = music
	music_player.bus = &"Music"
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS  # 暫停時音樂不停
	music_player.finished.connect(music_player.play)
	add_child(music_player)
	music_player.play()
