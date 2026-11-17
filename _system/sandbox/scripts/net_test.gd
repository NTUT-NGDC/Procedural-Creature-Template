extends Node
## 連線測試（開發用，匯出時排除）：測 WebSocket 能不能連、延遲多少、傳設計檔要多久。
##
## 用畫面測：
##   主機：F6 執行這個場景，按「當主機」，畫面會顯示本機 IP
##         （第一次執行 Windows 防火牆會跳視窗，要勾允許，學校 Wi-Fi 算「公用網路」）
##   加入：連同一個網路，輸入 ws://主機IP:8910，按「加入」
##
## 用命令列測（不開畫面）：
##   godot --headless --path . res://_system/sandbox/net_test.tscn -- host
##   godot --headless --path . res://_system/sandbox/net_test.tscn -- join ws://10.101.6.72:8910 30
##   （30 是測幾秒，時間到印出結果並結束；連不上 exit code 是 1）

const PORT: int = 8910
const SEND_RATE: float = 20.0          # 每秒傳幾次頭的座標（跟之後的遊戲差不多）
const BIG_SIZE: int = 100 * 1024       # 模擬一份設計檔＋PNG 的大小（位元組）
const BUFFER_SIZE: int = 4 * 1024 * 1024  # WebSocket 收發緩衝區：預設只有 64 KB，設計檔＋PNG 會送不出去

var _status_label: Label
var _log_label: Label
var _url_edit: LineEdit

var _is_host: bool = false
var _connected: bool = false
var _auto_seconds: float = -1.0        # 命令列模式：測幾秒後結束（-1 表示不自動結束）
var _elapsed: float = 0.0
var _send_timer: float = 0.0
var _ping_timer: float = 0.0
var _report_timer: float = 0.0
var _ping_samples: Array[float] = []   # 每次 ping 的來回時間（毫秒）
var _pings_sent: int = 0
var _world_received: int = 0           # 客戶端收到主機廣播的次數
var _big_start_ms: int = 0
var _big_result: String = "還沒測"
var _heads: Dictionary[int, Vector2] = {}  # 主機記錄每個人的頭座標


func _ready() -> void:
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0] == "host":
		_start_host()
	elif args.size() >= 2 and args[0] == "join":
		_auto_seconds = float(args[2]) if args.size() >= 3 else 20.0
		_url_edit.text = args[1]
		_start_join(args[1])


# ---------- 開主機、加入 ----------

func _start_host() -> void:
	var peer: WebSocketMultiplayerPeer = _new_peer()
	var err: Error = peer.create_server(PORT)
	if err != OK:
		_log("開主機失敗：%s（port %d 可能被占用）" % [error_string(err), PORT])
		return
	multiplayer.multiplayer_peer = peer
	_is_host = true
	_log("主機開好了，port %d。本機 IP：%s" % [PORT, ", ".join(_local_ips())])


func _start_join(url: String) -> void:
	var peer: WebSocketMultiplayerPeer = _new_peer()
	var err: Error = peer.create_client(url)
	if err != OK:
		_log("加入失敗：%s" % error_string(err))
		_finish_auto()
		return
	multiplayer.multiplayer_peer = peer
	_log("連線中：%s" % url)


func _new_peer() -> WebSocketMultiplayerPeer:
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = BUFFER_SIZE
	peer.outbound_buffer_size = BUFFER_SIZE
	return peer


func _local_ips() -> PackedStringArray:
	var result: PackedStringArray = []
	for ip: String in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append(ip)
	return result


# ---------- 連線事件 ----------

func _on_peer_connected(id: int) -> void:
	if _is_host:
		_log("有人加入：%d（現在 %d 人）" % [id, multiplayer.get_peers().size()])


func _on_peer_disconnected(id: int) -> void:
	if _is_host:
		_heads.erase(id)
		_log("有人離開：%d（現在 %d 人）" % [id, multiplayer.get_peers().size()])


func _on_connected_to_server() -> void:
	_connected = true
	_log("連上了！我的編號：%d" % multiplayer.get_unique_id())
	# 模擬加入時上傳設計檔：傳 100 KB 給主機，主機再傳回來，量來回時間
	var data: PackedByteArray = PackedByteArray()
	data.resize(BIG_SIZE)
	_big_start_ms = Time.get_ticks_msec()
	_big_result = "傳送中…"
	_upload_big.rpc_id(1, data)


func _on_connection_failed() -> void:
	_log("連不上")
	_finish_auto()


func _on_server_disconnected() -> void:
	_connected = false
	_log("主機斷線了")
	_finish_auto()


# ---------- RPC（主機和客戶端用同一個場景，節點路徑一樣） ----------

## 客戶端 → 主機：ping，主機馬上回傳
@rpc("any_peer", "unreliable")
func _ping(sent_ms: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), sent_ms)


## 主機 → 客戶端：回傳 ping，算來回時間
@rpc("authority", "unreliable")
func _pong(sent_ms: int) -> void:
	_ping_samples.append(float(Time.get_ticks_msec() - sent_ms))


## 客戶端 → 主機：大包資料（模擬設計檔），主機原封不動傳回去
@rpc("any_peer", "reliable")
func _upload_big(data: PackedByteArray) -> void:
	_download_big.rpc_id(multiplayer.get_remote_sender_id(), data)


## 主機 → 客戶端：大包資料傳回來了
@rpc("authority", "reliable")
func _download_big(data: PackedByteArray) -> void:
	var ms: int = Time.get_ticks_msec() - _big_start_ms
	_big_result = "%d KB 上傳＋下載共 %d ms" % [data.size() / 1024, ms]
	_log("大包資料：" + _big_result)


## 客戶端 → 主機：我的頭在哪
@rpc("any_peer", "unreliable_ordered")
func _send_head(pos: Vector2) -> void:
	_heads[multiplayer.get_remote_sender_id()] = pos


## 主機 → 所有人：每個人的頭在哪
@rpc("authority", "unreliable_ordered")
func _send_world(heads: Dictionary) -> void:
	_world_received += 1


# ---------- 每一幀 ----------

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_elapsed += delta
	_send_timer += delta
	_ping_timer += delta
	_report_timer += delta

	if _send_timer >= 1.0 / SEND_RATE:
		_send_timer = 0.0
		if _is_host and not _heads.is_empty():
			_send_world.rpc(_heads)
		elif _connected:
			_send_head.rpc_id(1, Vector2(randf() * 1000.0, randf() * 1000.0))

	if _connected and _ping_timer >= 0.5:
		_ping_timer = 0.0
		_pings_sent += 1
		_ping.rpc_id(1, Time.get_ticks_msec())

	if _report_timer >= 1.0:
		_report_timer = 0.0
		_status_label.text = _status_text()
		if DisplayServer.get_name() == "headless" and _is_host:
			print(_status_text())

	if _auto_seconds > 0.0 and _elapsed >= _auto_seconds:
		_finish_auto()


func _status_text() -> String:
	if _is_host:
		return "主機｜%d 人連線中" % multiplayer.get_peers().size()
	if not _connected:
		return "沒有連線"
	return "延遲 %s｜掉包 %d / %d｜收到廣播 %.1f 次/秒｜%s" % [
		_ping_summary(), _pings_sent - _ping_samples.size(), _pings_sent,
		_world_received / maxf(_elapsed, 0.001), _big_result]


func _ping_summary() -> String:
	if _ping_samples.is_empty():
		return "—"
	var sorted: Array[float] = _ping_samples.duplicate()
	sorted.sort()
	var total: float = 0.0
	for ms: float in sorted:
		total += ms
	var p95: float = sorted[int(sorted.size() * 0.95) - 1] if sorted.size() >= 20 else sorted[-1]
	return "平均 %d ms、95%% %d ms、最高 %d ms" % [int(total / sorted.size()), int(p95), int(sorted[-1])]


## 命令列模式：印出結果並結束
func _finish_auto() -> void:
	if _auto_seconds < 0.0:
		return
	_auto_seconds = -1.0
	print("結果｜" + _status_text())
	get_tree().quit(0 if not _ping_samples.is_empty() else 1)


# ---------- 畫面 ----------

func _build_ui() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.position = Vector2(24, 24)
	box.custom_minimum_size = Vector2(1232, 0)
	add_child(box)

	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var host_button: Button = Button.new()
	host_button.text = "當主機"
	host_button.pressed.connect(_start_host)
	row.add_child(host_button)
	_url_edit = LineEdit.new()
	_url_edit.placeholder_text = "ws://主機IP:%d" % PORT
	_url_edit.custom_minimum_size = Vector2(600, 0)
	row.add_child(_url_edit)
	var join_button: Button = Button.new()
	join_button.text = "加入"
	join_button.pressed.connect(func() -> void: _start_join(_url_edit.text.strip_edges()))
	row.add_child(join_button)

	_status_label = Label.new()
	_status_label.text = "沒有連線"
	box.add_child(_status_label)
	_log_label = Label.new()
	box.add_child(_log_label)


func _log(text: String) -> void:
	print(text)
	_log_label.text += text + "\n"
