class_name OnlineBattle
extends Node
## 連線對戰：全班在對戰地圖（game/tank/battle_tank.tscn）用同一套規則玩。社課工具，只在編輯器按 F5 用。
##
## 主機（社長的筆電）照常跑生態缸：移動、吃飼料、撞死、重生都由主機算（裁判是 TankRules，跟單人版同一份）。
## 學員的電腦只做兩件事：把「滑鼠往哪、有沒有在加速」傳給主機，再照主機傳回來的頭的位置擺生物。
## 身體、腳、觸手在每台電腦自己算（只傳頭的座標，網路才跑得動）。
##
## 加入時傳一次「名稱＋設計檔＋圖」（BattlePacket，主機檢查過才讓你進來）；之後每秒傳 SEND_RATE 次。
## 撞死就回 0 級重生；主機按「開始對戰」開始計時，時間到顯示最終排名。
## 協定、上限、檢查項目見外層 repo 的 docs/network_format.md。
##
## 由連線畫面（battle_lobby.tscn）設定好下面的「設定」再換過來，不要直接執行這個場景。

## 主機的埠（學員輸入的 IP 後面會自動加上）
const PORT: int = 8910
## WebSocket 收發緩衝區（位元組）：預設只有 64 KB，一份設計檔＋圖會送不出去
const BUFFER_SIZE: int = 4 * 1024 * 1024
## 每秒傳幾次頭的位置、操作
const SEND_RATE: float = 20.0
## 每隔幾秒把所有飼料的位置對一次（飼料會被水流帶著飄，每台電腦算的會慢慢偏掉）
const FOOD_SYNC_INTERVAL: float = 1.0
## 一次排隊送出的資料，對方還沒收完的超過這麼多（位元組）就等下一幀再送
const OUTBOX_LIMIT: int = 1024 * 1024
## 連不上主機時，等幾秒放棄
const CONNECT_TIMEOUT: float = 8.0
## 學員電腦上的生物追上主機位置的速度（越大越快）
const FOLLOW_SMOOTH: float = 15.0
## 排行榜顯示前幾名
const RANK_SHOWN: int = 5
const TANK_SCENE: PackedScene = preload("res://game/tank/battle_tank.tscn")
const LOBBY_SCENE: String = "res://lesson/battle/battle_lobby.tscn"
const TITLE_SCENE: String = "res://game/title_screen/title_screen.tscn"

## 對戰的階段：熱身（還沒開始，可以先游）、對戰中、結束（顯示最終排名）
enum Phase { WARMUP, PLAYING, ENDED }

## 一個玩家：主機、學員的電腦都有一份所有人的資料
class Player:
	var id: int = 0
	var name: String = ""
	## 加入時的資料（主機轉發給之後加入的人）
	var packet: Dictionary = {}
	var creature: Creature
	## 等級、升到這個等級時「對戰開始後幾秒」（同等級先升到的排前面）
	var level: int = 0
	var reached_at: float = 0.0
	## 重生過幾次：學員的電腦看到變了，就把生物瞬間移過去
	var spawns: int = 0
	## 主機：這個玩家的操作（方向、加速）
	var input_angle: float = 0.0
	var input_boost: bool = false
	## 學員的電腦：主機最後傳來的位置、速度、朝向，和那是幾秒前收到的
	var target: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var heading: float = 0.0
	var age: float = 0.0
	var has_state: bool = false

# ---------------------------------------------------------------- 設定（連線畫面設定）

## 是不是主機
var is_host: bool = false
## 主機的位址（學員用），例如 ws://10.101.6.72:8910
var address: String = ""
## 埠（測試時用別的，避免跟正在跑的主機衝突）
var port: int = PORT
## 自己的設計檔（主機自己的生物直接用它，圖是原畫質）
var my_design: CreatureDesign
## 自己要傳出去的資料（BattlePacket.build() 的結果）
var my_packet: Dictionary = {}
## 一場幾分鐘（主機）
var minutes: float = 5.0

## 生態缸（執行時建立）
var tank: Tank
## 所有玩家：id → Player
var players: Dictionary = {}
## 現在的階段、剩下幾秒
var phase: int = Phase.WARMUP
var time_left: float = 0.0
## 自己的 id（主機是 1）
var my_id: int = 0

@onready var _hud: BattleHud = %BattleHud

var _send_timer: float = 0.0
var _food_sync_timer: float = 0.0
## 對戰開始後幾秒（記錄誰先升到某個等級）
var _match_time: float = 0.0
## 主機：飼料的編號 → 飼料、下一個編號、這一輪新增和吃掉的
var _foods: Dictionary = {}
var _next_food_id: int = 1
var _added_foods: Array[Food] = []
var _removed_foods: PackedInt32Array = PackedInt32Array()
## 主機：每個學員排隊要送的大資料（設計檔＋圖）：id → [[方法名稱, 參數...], ...]
var _outbox: Dictionary = {}
## 學員：水流的時間跟主機差多少（秒），對齊後水流、飼料才會一樣
var _flow_offset: float = 0.0
var _flow_synced: bool = false
## 學員：還在等主機回應、已經結束（被拒絕、斷線）
var _connecting: float = 0.0
var _closed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暫停選單打開時對戰照常進行（大家都在玩）
	tank = TANK_SCENE.instantiate()
	tank.process_mode = Node.PROCESS_MODE_ALWAYS
	tank.remote_view = not is_host
	tank.game_name = "連線對戰"
	tank.player_design = my_design if is_host else null
	add_child(tank)
	move_child(tank, 0)  # 對戰的介面在生態缸上面
	tank.get_node("PauseMenu").connect("title_requested", leave.bind(TITLE_SCENE))  # 暫停選單的「回到標題」
	_hud.start_pressed.connect(start_match)
	_hud.leave_pressed.connect(leave.bind(LOBBY_SCENE))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_fail.bind("連不上主機：請確認 IP 對不對、主機開了沒有、跟主機在同一個網路"))
	multiplayer.server_disconnected.connect(_fail.bind("跟主機斷線了"))
	if is_host:
		_start_host()
	else:
		_start_join()


func _exit_tree() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()  # 回到不連線的狀態


func _process(delta: float) -> void:
	if _closed:
		return
	if is_host:
		_host_process(delta)
	else:
		_client_process(delta)
	_update_hud()


# ---------------------------------------------------------------- 開主機、加入


func _start_host() -> void:
	var peer := _new_peer()
	var error: Error = peer.create_server(port)
	if error != OK:
		_fail("開主機失敗（%s）：port %d 可能被別的程式用了" % [error_string(error), port])
		return
	multiplayer.multiplayer_peer = peer
	my_id = 1
	if tank.player == null:
		_fail("主機沒有自己的生物：請在標題畫面設定玩家生物")
		return
	_add_player(1, _player_name(my_packet, 1), my_packet, tank.player)
	tank.food_added.connect(_on_food_added)
	tank.food_eaten.connect(_on_food_eaten)
	tank.creature_died.connect(_on_creature_died)
	_hud.show_host(local_ips(), minutes)


func _start_join() -> void:
	var peer := _new_peer()
	var error: Error = peer.create_client(address)
	if error != OK:
		_fail("連不上 %s（%s）" % [address, error_string(error)])
		return
	multiplayer.multiplayer_peer = peer
	_connecting = CONNECT_TIMEOUT
	tank.show_message("連線中：%s" % address)


func _new_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = BUFFER_SIZE
	peer.outbound_buffer_size = BUFFER_SIZE
	return peer


## 這台電腦的 IP（給學員輸入用）：只列 IPv4，不列本機（127.x）和沒連上網路的（169.254.x）
static func local_ips() -> PackedStringArray:
	var result := PackedStringArray()
	for ip: String in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append(ip)
	return result


## 學員輸入的位址 → ws://IP:埠（只打 IP 也可以）
static func normalize_address(text: String, default_port: int = PORT) -> String:
	var url: String = text.strip_edges()
	if url == "":
		return ""
	if not url.begins_with("ws://"):
		url = "ws://" + url
	if url.substr(5).find(":") < 0:
		url += ":%d" % default_port
	return url


## 學員：連上了，把自己的資料傳給主機
func _on_connected() -> void:
	_connecting = CONNECT_TIMEOUT  # 再等主機檢查完
	tank.show_message("連上了，主機正在檢查你的生物……")
	_request_join.rpc_id(1, my_packet)


## 連不上、被拒絕、斷線：停下來顯示原因和「離開」按鈕
func _fail(reason: String) -> void:
	if _closed:
		return
	_closed = true
	_connecting = 0.0
	tank.show_message("")
	_hud.show_notice("沒辦法對戰", reason)
	tank.process_mode = Node.PROCESS_MODE_DISABLED


## 離開對戰：關掉連線，換到 scene_path（連線畫面或標題畫面）
func leave(scene_path: String) -> void:
	_closed = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	if scene_path == LOBBY_SCENE:
		var lobby: Node = (load(LOBBY_SCENE) as PackedScene).instantiate()
		lobby.set("player_design", my_design)
		get_tree().change_scene_to_node(lobby)
	else:
		get_tree().change_scene_to_file(scene_path)


## 名稱：沒填的話用「玩家 N」（N 是第幾個加入的）
func _player_name(packet: Dictionary, order: int) -> String:
	var text: String = BattlePacket.clean_name(str(packet.get("player_name", "")))
	return text if text != "" else "玩家 %d" % order


func _add_player(id: int, player_name: String, packet: Dictionary, creature: Creature) -> Player:
	var player := Player.new()
	player.id = id
	player.name = player_name
	player.packet = packet
	player.creature = creature
	player.level = creature.level
	players[id] = player
	return player


# ---------------------------------------------------------------- 主機


func _host_process(delta: float) -> void:
	_send_outbox()
	if phase == Phase.PLAYING:
		_match_time += delta
		time_left -= delta
		if time_left <= 0.0:
			_end_match()
			return
	for player: Player in players.values():
		if player.creature.level != player.level:
			player.level = player.creature.level
			player.reached_at = _match_time
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = 1.0 / SEND_RATE
		_broadcast_state()
	_food_sync_timer -= delta
	if _food_sync_timer <= 0.0:
		_food_sync_timer = FOOD_SYNC_INTERVAL
		for id: int in _joined_peers():
			_food_snapshot.rpc_id(id, _food_ids(), _food_positions(), _food_values())


## 有人離開：把他的生物拿掉，告訴其他人
func _on_peer_disconnected(id: int) -> void:
	_outbox.erase(id)
	if not is_host or not players.has(id):
		return
	var player: Player = players[id]
	tank.show_message("%s 離開了" % player.name, 2.0)
	player.creature.queue_free()
	players.erase(id)
	for peer: int in _joined_peers():
		_player_left.rpc_id(peer, id)


## 已經加入的學員（不含主機自己）
func _joined_peers() -> Array[int]:
	var result: Array[int] = []
	for id: int in players:
		if id != 1:
			result.append(id)
	return result


## 學員傳來名稱＋設計檔＋圖：檢查，合格就放一隻生物進缸、告訴大家；不合格就告訴他原因、斷線
@rpc("any_peer", "reliable")
func _request_join(packet: Variant) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if not is_host or players.has(id):
		return
	var reason: String = BattlePacket.check(packet, tank.get_balance())
	if reason != "":
		_join_rejected.rpc_id(id, reason)
		get_tree().create_timer(1.0).timeout.connect(func() -> void:  # 等原因送到再斷線
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	var player: Player = _add_player(id, _player_name(packet, players.size() + 1), packet, _spawn_remote(packet))
	tank.show_message("%s 加入了" % player.name, 2.0)
	_welcome.rpc_id(id, id, phase, time_left)
	_queue(id, ["_player_joined", _entry(player)])  # 自己的先送，畫面才早點出現
	for other: Player in players.values():
		if other.id != id:
			_queue(id, ["_player_joined", _entry(other)])
			if other.id != 1:
				_queue(other.id, ["_player_joined", _entry(player)])
	_food_snapshot.rpc_id(id, _food_ids(), _food_positions(), _food_values())


## 主機上代表學員的生物：照學員傳來的方向游（用 Creature 的「大腦」），撞死會重生
func _spawn_remote(packet: Dictionary) -> Creature:
	var creature := Creature.new()
	creature.design = BattlePacket.unpack_design(packet)
	creature.control_mode = Creature.Mode.WANDER
	creature.position = tank.safe_spot()
	creature.heading = randf() * TAU
	creature.add_to_group("respawn")
	tank.add_creature(creature)
	creature.invincible_time = tank.get_balance().respawn_invincible
	var id: int = multiplayer.get_remote_sender_id()
	creature.brain = func() -> Dictionary:
		var player: Player = players.get(id)
		if player == null:
			return {}
		return {"angle": player.input_angle, "speed": creature.speed, "boost": player.input_boost}
	return creature


## 傳給學員的一個玩家資料（id、名稱、加入時的資料）
func _entry(player: Player) -> Dictionary:
	return {"id": player.id, "name": player.name, "packet": player.packet}


## 大資料排隊送：對方還沒收完的太多就先等，不然 WebSocket 的緩衝區會滿
func _queue(id: int, call_args: Array) -> void:
	if not _outbox.has(id):
		_outbox[id] = []
	(_outbox[id] as Array).append(call_args)


func _send_outbox() -> void:
	var peer: WebSocketMultiplayerPeer = multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if peer == null:
		return
	for id: int in _outbox.keys():
		var queue: Array = _outbox[id]
		while not queue.is_empty():
			var socket: WebSocketPeer = peer.get_peer(id)
			if socket == null or socket.get_current_outbound_buffered_amount() > OUTBOX_LIMIT:
				break
			var call_args: Array = queue.pop_front()  # [方法名稱, 參數...]
			callv("rpc_id", [id] + call_args)
		if queue.is_empty():
			_outbox.erase(id)


## 學員的操作：方向（弧度）、要不要加速
@rpc("any_peer", "unreliable_ordered")
func _send_input(angle: Variant, boost: Variant) -> void:
	var player: Player = players.get(multiplayer.get_remote_sender_id())
	if not is_host or player == null or not (angle is float) or not (boost is bool) or not is_finite(angle):
		return
	player.input_angle = angle
	player.input_boost = boost


## 每秒 SEND_RATE 次：每隻的頭、速度、朝向、等級、這一級吃了幾個、重生次數、升到這級的時間；水流時間、剩下的時間
func _broadcast_state() -> void:
	var ids := PackedInt32Array()
	var positions := PackedVector2Array()
	var velocities := PackedVector2Array()
	var headings := PackedFloat32Array()
	var levels := PackedInt32Array()
	var progress := PackedInt32Array()
	var spawns := PackedInt32Array()
	var reached := PackedFloat32Array()
	for player: Player in players.values():
		var creature: Creature = player.creature
		ids.append(player.id)
		positions.append(creature.global_position)
		velocities.append(creature.velocity)
		headings.append(creature.heading)
		levels.append(creature.level)
		progress.append(creature.food_progress)
		spawns.append(player.spawns)
		reached.append(player.reached_at)
	var foods_added: Array = _food_changes()
	for id: int in _joined_peers():
		if not foods_added.is_empty():
			_foods_changed.rpc_id(id, foods_added[0], foods_added[1], foods_added[2], foods_added[3], foods_added[4])
		_state.rpc_id(id, [ids, positions, velocities, headings, levels, progress, spawns, reached, WaterFlow.now(), time_left])


## 這一輪新增、吃掉的飼料（沒有就是空的）：[新增的編號, 位置, 算幾個, 還要等幾秒, 吃掉的編號]
func _food_changes() -> Array:
	if _added_foods.is_empty() and _removed_foods.is_empty():
		return []
	var ids := PackedInt32Array()
	var positions := PackedVector2Array()
	var values := PackedInt32Array()
	var waits := PackedFloat32Array()
	for food: Food in _added_foods:
		if is_instance_valid(food) and food.has_meta("net_id"):
			ids.append(food.get_meta("net_id"))
			positions.append(food.global_position)
			values.append(food.value)
			waits.append(food.wait)
	var result: Array = [ids, positions, values, waits, _removed_foods]
	_added_foods.clear()
	_removed_foods = PackedInt32Array()
	return result


func _on_food_added(food: Food) -> void:
	food.set_meta("net_id", _next_food_id)
	_foods[_next_food_id] = food
	_next_food_id += 1
	_added_foods.append(food)


func _on_food_eaten(food: Node) -> void:
	var id: int = food.get_meta("net_id", -1)
	if _foods.erase(id):
		_removed_foods.append(id)


func _food_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	for id: int in _foods:
		if is_instance_valid(_foods[id]):
			result.append(id)
	return result


func _food_positions() -> PackedVector2Array:
	var result := PackedVector2Array()
	for id: int in _foods:
		if is_instance_valid(_foods[id]):
			result.append((_foods[id] as Food).global_position)
	return result


func _food_values() -> PackedInt32Array:
	var result := PackedInt32Array()
	for id: int in _foods:
		if is_instance_valid(_foods[id]):
			result.append((_foods[id] as Food).value)
	return result


## 主機的裁判判定有生物撞死了：記下誰撞倒誰、重生次數，告訴大家
func _on_creature_died(victim: Creature, blocker: Creature) -> void:
	var victim_id: int = _id_of(victim)
	var blocker_id: int = _id_of(blocker)
	if players.has(victim_id):
		(players[victim_id] as Player).spawns += 1
	for id: int in _joined_peers():
		_died.rpc_id(id, victim_id, blocker_id)


func _id_of(creature: Creature) -> int:
	for player: Player in players.values():
		if player.creature == creature:
			return player.id
	return 0


## 主機按「開始對戰」（或「再一場」）：大家回到 0 級、重新找位置，開始倒數
func start_match() -> void:
	if not is_host:
		return
	phase = Phase.PLAYING
	time_left = _hud.get_minutes() * 60.0 if _hud.get_minutes() > 0.0 else minutes * 60.0
	_match_time = 0.0
	tank.process_mode = Node.PROCESS_MODE_ALWAYS
	tank.kills = 0
	tank.best_level = 0
	for player: Player in players.values():
		tank.respawn(player.creature, "")
		player.spawns += 1
		player.level = 0
		player.reached_at = 0.0
	tank.show_message("開始！", 1.5)
	_hud.set_started()
	_hud.hide_notice()
	for id: int in _joined_peers():
		_phase_changed.rpc_id(id, phase, time_left, [])


## 時間到：停下來，顯示最終排名
func _end_match() -> void:
	phase = Phase.ENDED
	time_left = 0.0
	_broadcast_state()  # 最後的等級先送出去
	var ranking: Array = []
	for player: Player in ranking_order():
		ranking.append([player.name, player.level])
	for id: int in _joined_peers():
		_phase_changed.rpc_id(id, phase, 0.0, ranking)
	_show_result(ranking)


# ---------------------------------------------------------------- 學員


func _client_process(delta: float) -> void:
	if _connecting > 0.0:
		_connecting -= delta
		if _connecting <= 0.0:
			_fail("連不上主機（等了 %d 秒）：請確認 IP 對不對、主機開了沒有、跟主機在同一個網路" % CONNECT_TIMEOUT)
			return
	if _flow_synced:
		WaterFlow.fixed_time = Time.get_ticks_msec() / 1000.0 + _flow_offset  # 水流跟主機對齊
	_move_puppets(delta)
	_send_timer -= delta
	if _send_timer <= 0.0 and my_id != 0 and tank.player != null and multiplayer.multiplayer_peer != null:
		_send_timer = 1.0 / SEND_RATE
		var wanted: Dictionary = tank.player.wanted
		if wanted.has("angle"):
			_send_input.rpc_id(1, float(wanted.angle), bool(wanted.get("boost", false)))


## 照主機傳來的位置擺生物：往「最後的位置＋速度 × 過了多久」慢慢靠過去，網路有延遲也不會一頓一頓的
func _move_puppets(delta: float) -> void:
	var smooth: float = 1.0 - exp(-FOLLOW_SMOOTH * delta)
	for player: Player in players.values():
		if not player.has_state:
			continue
		player.age += delta
		var creature: Creature = player.creature
		var target: Vector2 = player.target + player.velocity * minf(player.age, 0.2)
		creature.global_position = creature.global_position.lerp(target, smooth)
		creature.heading = lerp_angle(creature.heading, player.heading, smooth)
		creature.velocity = player.velocity


## 主機拒絕加入
@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	_fail("主機沒讓你加入：%s" % reason)


## 主機讓你加入了：記下自己的 id、現在的階段
@rpc("authority", "reliable")
func _welcome(id: int, now_phase: int, now_time_left: float) -> void:
	my_id = id
	_connecting = 0.0
	tank.show_message("加入了！", 1.5)
	_set_phase(now_phase, now_time_left)


## 有一個玩家（可能是自己）：照他的設計檔建一隻生物（只照主機給的位置擺，不自己動）
@rpc("authority", "reliable")
func _player_joined(entry: Dictionary) -> void:
	var id: int = entry.get("id", 0)
	if players.has(id) or id == 0:
		return
	var creature := Creature.new()
	creature.design = BattlePacket.unpack_design(entry.get("packet", {}))
	creature.puppet = true
	var mine: bool = id == my_id
	creature.control_mode = Creature.Mode.MOUSE if mine else Creature.Mode.WANDER
	creature.tank_controls = mine  # 自己的：讀滑鼠、按鍵（傳給主機）
	creature.position = tank.world_size / 2.0
	tank.add_creature(creature)
	if mine:
		tank.player = creature
	_add_player(id, str(entry.get("name", "?")), {}, creature)


@rpc("authority", "reliable")
func _player_left(id: int) -> void:
	if players.has(id):
		(players[id] as Player).creature.queue_free()
		players.erase(id)


## 主機每秒傳 SEND_RATE 次的狀態
@rpc("authority", "unreliable_ordered")
func _state(data: Array) -> void:
	var ids: PackedInt32Array = data[0]
	var positions: PackedVector2Array = data[1]
	var velocities: PackedVector2Array = data[2]
	var headings: PackedFloat32Array = data[3]
	var levels: PackedInt32Array = data[4]
	var progress: PackedInt32Array = data[5]
	var spawns: PackedInt32Array = data[6]
	var reached: PackedFloat32Array = data[7]
	_sync_flow(data[8])
	time_left = data[9]
	for i: int in ids.size():
		var player: Player = players.get(ids[i])
		if player == null:
			continue  # 這個玩家的設計檔還沒收到
		var creature: Creature = player.creature
		player.target = positions[i]
		player.velocity = velocities[i]
		player.heading = headings[i]
		player.age = 0.0
		player.reached_at = reached[i]
		if creature.level != levels[i]:
			creature.set_level(levels[i])
		player.level = levels[i]
		creature.food_progress = progress[i]
		if not player.has_state or player.spawns != spawns[i]:  # 第一次、重生：直接移過去
			var respawned: bool = player.has_state
			player.has_state = true
			player.spawns = spawns[i]
			creature.global_position = positions[i]
			creature.heading = headings[i]
			creature.reset_pose()
			if respawned:
				creature.invincible_time = tank.get_balance().respawn_invincible
			if creature == tank.player:
				tank.camera.global_position = creature.global_position
				tank.camera.reset_smoothing()


## 水流的時間跟主機對齊（慢慢修正，不會一下跳太多）
func _sync_flow(host_time: float) -> void:
	var offset: float = host_time - Time.get_ticks_msec() / 1000.0
	_flow_offset = offset if not _flow_synced else lerpf(_flow_offset, offset, 0.05)
	_flow_synced = true


@rpc("authority", "reliable")
func _foods_changed(ids: PackedInt32Array, positions: PackedVector2Array, values: PackedInt32Array, waits: PackedFloat32Array, removed: PackedInt32Array) -> void:
	for i: int in ids.size():
		if not _foods.has(ids[i]):
			_foods[ids[i]] = tank.add_food(positions[i], values[i], waits[i])
	for id: int in removed:
		_remove_client_food(id)


## 每 FOOD_SYNC_INTERVAL 秒：所有飼料對一次（少的補上、多的拿掉、位置拉回主機的位置）
@rpc("authority", "reliable")
func _food_snapshot(ids: PackedInt32Array, positions: PackedVector2Array, values: PackedInt32Array) -> void:
	var alive: Dictionary = {}
	for i: int in ids.size():
		alive[ids[i]] = true
		var food: Food = _foods.get(ids[i])
		if food == null or not is_instance_valid(food):
			_foods[ids[i]] = tank.add_food(positions[i], values[i])
		else:
			food.global_position = positions[i]
	for id: int in _foods.keys():
		if not alive.has(id):
			_remove_client_food(id)


func _remove_client_food(id: int) -> void:
	var food: Food = _foods.get(id)
	_foods.erase(id)
	if food != null and is_instance_valid(food):
		food.queue_free()


## 有生物撞死了：是自己撞倒別人、或自己撞死的，顯示提示
@rpc("authority", "reliable")
func _died(victim_id: int, blocker_id: int) -> void:
	if blocker_id == my_id and victim_id != my_id:
		tank.kills += 1
		tank.show_message("撞倒一隻！", 1.5)
	if victim_id == my_id:
		tank.show_message("撞到別人了！從 0 級重新開始", 2.5)


@rpc("authority", "reliable")
func _phase_changed(new_phase: int, new_time_left: float, ranking: Array) -> void:
	_set_phase(new_phase, new_time_left)
	if new_phase == Phase.PLAYING:
		tank.kills = 0
		tank.best_level = 0
		tank.show_message("開始！", 1.5)
	elif new_phase == Phase.ENDED:
		_show_result(ranking)


func _set_phase(new_phase: int, new_time_left: float) -> void:
	phase = new_phase
	time_left = new_time_left
	tank.process_mode = Node.PROCESS_MODE_DISABLED if phase == Phase.ENDED else Node.PROCESS_MODE_ALWAYS
	if phase != Phase.ENDED:
		_hud.hide_notice()


# ---------------------------------------------------------------- 排行榜、時間


## 排名：等級高的在前面；同等級的，先升到這個等級的在前面
func ranking_order() -> Array[Player]:
	var order: Array[Player] = []
	for player: Player in players.values():
		order.append(player)
	order.sort_custom(func(a: Player, b: Player) -> bool:
		if a.level != b.level:
			return a.level > b.level
		if a.reached_at != b.reached_at:
			return a.reached_at < b.reached_at
		return a.id < b.id)
	return order


func _update_hud() -> void:
	var order: Array[Player] = ranking_order()
	var lines: PackedStringArray = PackedStringArray(["排行榜"])
	var mine: int = -1
	for i: int in order.size():
		if order[i].id == my_id:
			mine = i
		if i < RANK_SHOWN:
			lines.append(_rank_line(i, order[i]))
	if mine >= RANK_SHOWN:
		lines.append("……")
		lines.append(_rank_line(mine, order[mine]))
	_hud.show_ranking("\n".join(lines))
	match phase:
		Phase.WARMUP:
			_hud.show_time("熱身中：等主機按「開始對戰」" if not is_host else "熱身中：大家都進來了就按「開始對戰」")
		Phase.PLAYING:
			var seconds: int = ceili(maxf(time_left, 0.0))
			_hud.show_time("剩下 %d:%02d" % [floori(seconds / 60.0), seconds % 60])
		Phase.ENDED:
			_hud.show_time("時間到！")


func _rank_line(index: int, player: Player) -> String:
	return "%s%d. %s　%d 級" % ["> " if player.id == my_id else "", index + 1, player.name, player.level]


## 最終排名：ranking 是 [[名稱, 等級], ...]
func _show_result(ranking: Array) -> void:
	tank.process_mode = Node.PROCESS_MODE_DISABLED
	var lines := PackedStringArray()
	for i: int in ranking.size():
		var row: Array = ranking[i]
		lines.append("%d. %s　%d 級" % [i + 1, str(row[0]), int(row[1])])
	_hud.show_notice("最終排名", "\n".join(lines) if not lines.is_empty() else "（沒有人）")
