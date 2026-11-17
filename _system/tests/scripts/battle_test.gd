extends Node
## 連線對戰的自動測試：
## 1. 打包、檢查（BattlePacket）：該過的會過；版本不對、沒用到的圖、讀不到的圖、太大的圖、太複雜、格式不對都會被拒絕
## 2. 圖太大：算出要縮成多大、縮完放得下、原本的圖沒被改；縮到最小還是太大回傳 -1
## 3. 還原：收到的設計檔照樣長出生物，圖從 image_cache 讀
## 4. 連線（同一個程式裡開一個主機、一個學員，用 127.0.0.1）：
##    加入、雙方都看到兩隻；學員的生物跟著主機的位置；操作傳到主機；
##    飼料新增、被吃掉同步；撞死：學員收到提示、瞬間移到重生的位置；
##    排行榜；開始對戰、時間到顯示最終排名；被拒絕顯示原因；學員離開、主機關掉
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/battle_test.tscn

const SNAKE: String = "res://example/creatures/snake/design.tres"
const DOODLE: String = "res://example/creatures/doodle/design.tres"
const BATTLE_SCENE: PackedScene = preload("res://lesson/battle/online_battle.tscn")
## 測試用的埠（避免跟正在跑的主機衝突）
const TEST_PORT: int = 18917

var _failures: int = 0


func _ready() -> void:
	_test_packet_check()
	_test_shrink()
	await _test_unpack()
	await _test_network()

	if _failures == 0:
		print("[連線對戰測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[連線對戰測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_packet_check() -> void:
	print("--- 打包、檢查 ---")
	var balance: CreatureBalance = CreatureBalance.get_default()
	var doodle: CreatureDesign = load(DOODLE)
	var images: Dictionary = BattlePacket.read_images(doodle)
	_expect(BattlePacket.image_files(doodle) == PackedStringArray(["doodle_head.png"]) and images.has("doodle_head.png"), "塗鴉蟲用到 doodle_head.png，讀得到")
	var good: Dictionary = BattlePacket.build("  小明  ", doodle, images)
	_expect(good.player_name == "小明" and BattlePacket.check(good, balance) == "", "正確的資料會過（名稱去掉空白）")
	_expect(BattlePacket.clean_name("一二三四五六七八九十一二三四五六七八") .length() == BattlePacket.MAX_NAME, "名稱最多 %d 字" % BattlePacket.MAX_NAME)

	var wrong_version: Dictionary = good.duplicate()
	wrong_version.version = 99
	_expect(BattlePacket.check(wrong_version, balance).contains("版本"), "版本不對：拒絕")
	var text_version: Dictionary = good.duplicate()
	text_version.version = "1"
	_expect(BattlePacket.check(text_version, balance).contains("版本"), "版本是文字：拒絕，不會當掉")
	_expect(BattlePacket.check("hello", balance) != "" and BattlePacket.check({}, balance) != "", "不是資料、空的資料：拒絕")
	var no_design: Dictionary = good.duplicate()
	no_design.design = [1, 2, 3]
	_expect(BattlePacket.check(no_design, balance) != "", "設計檔不是 Dictionary：拒絕")

	var extra: Dictionary = good.duplicate(true)
	extra.images["other.png"] = images["doodle_head.png"]
	_expect(BattlePacket.check(extra, balance).contains("沒用到"), "有設計檔沒用到的圖：拒絕")
	var broken: Dictionary = good.duplicate(true)
	broken.images["doodle_head.png"] = PackedByteArray([1, 2, 3, 4])
	_expect(BattlePacket.check(broken, balance).contains("讀不到"), "圖不是 PNG：拒絕")
	var not_bytes: Dictionary = good.duplicate(true)
	not_bytes.images["doodle_head.png"] = "abc"
	_expect(BattlePacket.check(not_bytes, balance).contains("格式"), "圖不是位元組：拒絕")
	var big: Dictionary = good.duplicate(true)
	big.images["doodle_head.png"] = Image.create(600, 100, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	_expect(BattlePacket.check(big, balance).contains("圖太大"), "圖超過 %d 像素：拒絕" % BattlePacket.MAX_IMAGE_SIDE)
	var noisy: Dictionary = good.duplicate(true)
	noisy.images["doodle_head.png"] = _noise_png(512)
	_expect(BattlePacket.check(noisy, balance) == "", "一張 512 的雜訊圖（%d KB）沒超過上限：會過" % BattlePacket.kb((noisy.images["doodle_head.png"] as PackedByteArray).size()))

	var complex: CreatureDesign = (load(SNAKE) as CreatureDesign).duplicate(true)
	for i: int in CreatureDesign.MAX_TENTACLES:
		complex.tentacles.append(TentacleDesign.new())
	for i: int in CreatureDesign.MAX_LEGS:
		complex.legs.append(LegDesign.new())
	var too_complex: Dictionary = BattlePacket.build("", complex, {})
	_expect(BattlePacket.check(too_complex, balance).contains("太複雜"), "太複雜：拒絕（複雜度 %d）" % CreatureStats.complexity_of(complex, balance))


func _test_shrink() -> void:
	print("--- 圖太大 ---")
	var small: Dictionary = {"a.png": Image.create(64, 64, false, Image.FORMAT_RGBA8).save_png_to_buffer()}
	_expect(BattlePacket.shrink_side_needed(small) == 0, "小的圖：不用縮")
	var images: Dictionary = {}
	for i: int in 3:
		images["noise_%d.png" % i] = _noise_png(512)
	var total: int = BattlePacket.total_bytes(images)
	var side: int = BattlePacket.shrink_side_needed(images)
	_expect(total > BattlePacket.MAX_IMAGE_BYTES and side > 0, "三張 512 的雜訊圖（%d KB）超過上限，要縮成 %d" % [BattlePacket.kb(total), side])
	var shrunk: Dictionary = BattlePacket.shrink_images(images, side)
	var image := Image.new()
	image.load_png_from_buffer(shrunk["noise_0.png"])
	_expect(BattlePacket.total_bytes(shrunk) <= BattlePacket.MAX_IMAGE_BYTES and image.get_width() == side, "縮完放得下（%d KB），長邊 %d" % [BattlePacket.kb(BattlePacket.total_bytes(shrunk)), image.get_width()])
	_expect(BattlePacket.total_bytes(images) == total, "原本的圖沒被改")
	var many: Dictionary = {}
	for i: int in 80:
		many["n%d.png" % i] = _noise_png(160)
	_expect(BattlePacket.shrink_side_needed(many) == -1, "圖太多張，縮到最小還是太大：-1")
	var message: String = preload("res://lesson/battle/scripts/battle_lobby.gd").shrink_message(total, side)
	_expect(message.contains("原圖不會被改到") and message.contains("%d 像素" % side), "縮小視窗有說明原因、大小、原圖不會被改")


func _test_unpack() -> void:
	print("--- 還原 ---")
	var doodle: CreatureDesign = load(DOODLE)
	var packet: Dictionary = BattlePacket.build("", doodle, BattlePacket.read_images(doodle))
	var design: CreatureDesign = BattlePacket.unpack_design(packet)
	_expect(design.resource_path == "" and design.image_cache.has("doodle_head.png"), "收到的設計檔不是檔案，圖在 image_cache")
	var creature := Creature.new()
	creature.design = design
	add_child(creature)
	await get_tree().process_frame
	_expect(_has_image(creature), "長得出來，掛件的圖從 image_cache 讀")
	_expect(BattlePacket.unpack_design({"design": "x", "images": 5}) != null, "資料亂掉也不會當掉（用預設值）")
	creature.queue_free()
	await get_tree().process_frame


func _test_network() -> void:
	print("--- 連線 ---")
	var host: OnlineBattle = await _spawn_battle("Host", true, BattlePacket.build("社長", load(SNAKE), {}))
	var doodle: CreatureDesign = load(DOODLE)
	var client: OnlineBattle = await _spawn_battle("Client", false, BattlePacket.build("小明", doodle, BattlePacket.read_images(doodle)))
	_expect(await _wait(func() -> bool: return client.players.size() == 2 and host.players.size() == 2 and client.tank.player != null, 5.0), "加入：主機、學員都有兩隻")
	if client.players.size() != 2:
		return
	var host_side: OnlineBattle.Player = host.players[client.my_id]
	var client_side: OnlineBattle.Player = client.players[client.my_id]
	_expect(host_side.name == "小明" and (client.players[1] as OnlineBattle.Player).name == "社長", "名稱傳到了")
	_expect(client_side.creature.puppet and client.tank.player == client_side.creature and not host_side.creature.puppet, "學員的生物只照主機的位置擺（主機上的才會自己游）")
	_expect(_has_image(client_side.creature) and _has_image(host_side.creature), "學員的圖傳到主機、再傳回學員")
	await _frames(30)
	_expect(client_side.creature.global_position.distance_to(host_side.creature.global_position) < 60.0, "學員的生物跟著主機的位置（差 %.0f）" % client_side.creature.global_position.distance_to(host_side.creature.global_position))
	var wanted: float = float(client.tank.player.wanted.get("angle", -99.0))  # 生物在動，方向一直在變：差一點點沒關係
	_expect(absf(angle_difference(host_side.input_angle, wanted)) < 0.3, "學員的操作傳到主機（主機 %.2f、學員 %.2f）" % [host_side.input_angle, wanted])

	print("--- 飼料 ---")
	host.tank.drop_food(Vector2(500, 500))
	var food_id: int = host._next_food_id - 1  # 剛放的這一顆（缸裡也會自己長，不能拿最後一個）
	await _frames(10)
	var copy: Food = client._foods.get(food_id)
	_expect(copy != null and copy.global_position.distance_to((host._foods[food_id] as Food).global_position) < 5.0, "主機放的飼料，學員也看得到")
	host.tank.player.eat(host._foods[food_id])
	await _frames(10)
	_expect(not client._foods.has(food_id) and (copy == null or not is_instance_valid(copy) or copy.is_queued_for_deletion()), "被吃掉的飼料，學員那邊也不見")
	var drifted: int = client._foods.size()
	_expect(drifted == host._foods.size(), "飼料數量一樣（%d）" % drifted)

	print("--- 撞死 ---")
	host_side.creature.grow(2)
	await _frames(10)
	_expect(client_side.creature.level == 2 and client_side.level == 2, "升級傳到學員")
	_expect(client.ranking_order()[0].id == client.my_id, "排行榜：學員 2 級排第一")
	host.tank.call("_kill", host_side.creature, host.tank.player)
	await _frames(10)
	_expect(client_side.spawns == host_side.spawns and client_side.spawns > 0, "撞死：學員收到重生（第 %d 次）" % client_side.spawns)
	_expect(client_side.creature.level == 0 and client_side.creature.global_position.distance_to(host_side.creature.global_position) < 60.0, "學員回 0 級，移到重生的位置（差 %.0f）" % client_side.creature.global_position.distance_to(host_side.creature.global_position))
	_expect((client.tank.get("_hud") as Node).call("get_message").contains("撞到別人"), "學員看到「撞到別人了」")
	_expect(client_side.creature.is_invincible(), "重生後一閃一閃（無敵）")

	print("--- 開始、時間到 ---")
	host_side.creature.grow(1)
	host.start_match()
	await _frames(10)
	_expect(client.phase == OnlineBattle.Phase.PLAYING and client_side.creature.level == 0 and client.time_left > 200.0, "開始對戰：學員收到、大家回 0 級、開始倒數（%.0f 秒）" % client.time_left)
	host.tank.player.grow(3)
	await _frames(5)
	host.time_left = 0.05
	await _frames(10)
	_expect(host.phase == OnlineBattle.Phase.ENDED and client.phase == OnlineBattle.Phase.ENDED, "時間到：主機、學員都結束")
	var result: String = client._hud.get_notice()
	_expect(result.contains("最終排名") and result.find("社長") < result.find("小明"), "學員看到最終排名（社長 3 級排第一）")
	_expect(client.tank.process_mode == Node.PROCESS_MODE_DISABLED, "時間到：畫面停住")
	host.start_match()
	await _frames(10)
	_expect(client.phase == OnlineBattle.Phase.PLAYING and client._hud.get_notice() == "", "再一場：最終排名關掉")

	print("--- 被拒絕 ---")
	var bad_packet: Dictionary = BattlePacket.build("壞掉", load(SNAKE), {})
	bad_packet.version = 99
	var rejected: OnlineBattle = await _spawn_battle("Rejected", false, bad_packet)
	_expect(await _wait(func() -> bool: return rejected._hud.get_notice().contains("主機沒讓你加入"), 5.0), "版本不對：顯示主機拒絕的原因")
	await _frames(70)
	_expect(host.players.size() == 2 and rejected._hud.get_notice().contains("版本"), "被拒絕的沒有加進缸裡，斷線後原因還在")
	await _free(rejected)

	print("--- 離開 ---")
	await _free(client)
	_expect(await _wait(func() -> bool: return host.players.size() == 1, 5.0), "學員離開：主機把他的生物拿掉")
	var client2: OnlineBattle = await _spawn_battle("Client2", false, BattlePacket.build("", load(SNAKE), {}))
	_expect(await _wait(func() -> bool: return client2.players.size() == 2, 5.0), "再加入一個人")
	_expect((host.players[client2.my_id] as OnlineBattle.Player).name.begins_with("玩家"), "沒填名稱：用「玩家 N」")
	await _free(host)
	_expect(await _wait(func() -> bool: return client2._hud.get_notice().contains("斷線"), 5.0), "主機關掉：學員看到「跟主機斷線了」")
	await _free(client2)

	var nobody: OnlineBattle = await _spawn_battle("Nobody", false, BattlePacket.build("", load(SNAKE), {}), "ws://127.0.0.1:18999")
	_expect(await _wait(func() -> bool: return nobody._hud.get_notice().contains("連不上"), OnlineBattle.CONNECT_TIMEOUT + 3.0), "主機沒開：顯示連不上")
	await _free(nobody)


## 開一個對戰：每個都在自己的分支、用自己的 SceneMultiplayer（同一個程式裡模擬好幾台電腦）
func _spawn_battle(label: String, host: bool, packet: Dictionary, address: String = "ws://127.0.0.1:%d" % TEST_PORT) -> OnlineBattle:
	var branch := Node.new()
	branch.name = label
	add_child(branch)
	get_tree().set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var battle: OnlineBattle = BATTLE_SCENE.instantiate()
	battle.is_host = host
	battle.port = TEST_PORT
	battle.address = address
	battle.my_design = load(SNAKE) if host else null
	battle.my_packet = packet
	branch.add_child(battle)
	await _frames(2)
	return battle


func _free(battle: OnlineBattle) -> void:
	var branch: Node = battle.get_parent()
	branch.queue_free()
	await _frames(3)


## 一直等到 condition 成立（最多 seconds 秒），回傳有沒有成立
func _wait(condition: Callable, seconds: float) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


## 生物的掛件有沒有讀到圖
func _has_image(creature: Creature) -> bool:
	for node: Node in creature.find_children("Image", "Sprite2D", true, false):
		var texture: Texture2D = (node as Sprite2D).texture
		if texture != null and texture.get_width() > 0:
			return true
	return false


## 一張雜訊圖（PNG 壓不小，用來測「圖太大」）
func _noise_png(side: int) -> PackedByteArray:
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	for y: int in side:
		for x: int in side:
			image.set_pixel(x, y, Color(randf(), randf(), randf(), 1.0))
	return image.save_png_to_buffer()


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
