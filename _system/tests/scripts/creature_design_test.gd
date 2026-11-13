extends Node
## 設計檔的自動測試：
## 1. 設計資料和零件節點的欄位一致：同名、同型別、同範圍（加新屬性時漏改一邊會在這裡抓到）
## 2. 8 隻範例的設計檔長出來的生物：節數、零件數量跟設計檔一樣；零件依掛的節數排上下
## 3. 存檔再讀回來、to_dict() 再 from_dict()，內容都不變
## 4. from_dict() 收到奇怪的資料：缺欄位、型別錯、超出範圍、NaN、太多零件、怪檔名，都不會當掉，數字夾回範圍內
## 5. 改設計檔後 apply_design()：結構沒變只更新屬性（同一個身體節點）；加了零件就重長
## 6. 長出來的節點不會存進場景檔
## 7. 自己的圖：塗鴉蛇的頭有圖；還沒匯入的 PNG 也讀得到
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/creature_design_test.tscn

const EXAMPLES: String = "res://example/creatures/"
const NAMES: PackedStringArray = ["snake", "centipede", "octopus", "spider", "jellyfish", "dragon", "doodle", "predator_eel"]
## 設計資料 → 對應的零件節點
var _pairs: Array = [
	[BodyDesign, ChainBody],
	[LegDesign, IKLeg],
	[TentacleDesign, Tentacle],
	[EyesDesign, Eyes],
	[OrnamentDesign, Ornament],
]
const TEMP_FOLDER: String = "user://design_test/"

var _failures: int = 0


func _ready() -> void:
	_test_fields_match()
	await _test_examples_match()
	_test_round_trip()
	await _test_garbage()
	await _test_apply_in_place()
	_test_not_saved()
	await _test_images()

	if _failures == 0:
		print("[設計檔測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[設計檔測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_fields_match() -> void:
	print("--- 設計資料和零件節點的欄位一致 ---")
	for pair: Array in _pairs:
		var design: PartDesign = pair[0].new()
		var node: Node = pair[1].new()
		var node_props: Dictionary = {}
		for prop: Dictionary in node.get_property_list():
			node_props[prop.name] = prop
		var problems: PackedStringArray = []
		for prop: Dictionary in design.fields():
			if prop.name in design.design_only_fields():
				continue
			if not node_props.has(prop.name):
				problems.append("%s 節點上沒有" % prop.name)
				continue
			var other: Dictionary = node_props[prop.name]
			if other.type != prop.type:
				problems.append("%s 型別不同" % prop.name)
			elif other.hint_string.replace(",or_greater", "") != prop.hint_string:
				problems.append("%s 範圍不同（節點 %s／設計 %s）" % [prop.name, other.hint_string, prop.hint_string])
			elif not _same(node.get(prop.name), design.get(prop.name)):
				problems.append("%s 預設值不同" % prop.name)
		_expect(problems.is_empty(), "%s ↔ %s：%s" % [design.get_script().get_global_name(), node.get_script().get_global_name(), "一致" if problems.is_empty() else "、".join(problems)])
		node.free()


func _test_examples_match() -> void:
	print("--- 範例：設計檔長出來的生物 ---")
	for example: String in NAMES:
		var design: CreatureDesign = load(EXAMPLES + example + "/design.tres")
		var built: Creature = _spawn(design)
		await get_tree().process_frame
		var counts: Array[int] = [_parts_of(built, IKLeg).size(), _parts_of(built, Tentacle).size(), _parts_of(built, Eyes).size(), _parts_of(built, Ornament).size()]
		var expected: Array[int] = [design.legs.size(), design.tentacles.size(), design.eyes.size(), design.ornaments.size()]
		_expect(counts == expected and built.get_body().joint_count() == design.body.segment_count, "%s：身體 %d 節，腳、觸手、眼睛、掛件 %s 個，跟設計檔一樣" % [example, built.get_body().joint_count(), counts])
		if example in ["dragon", "centipede", "spider"]:
			_expect(_drawn_tail_to_head(built), "%s：零件越靠尾巴越先畫（在下面），眼睛最後畫（在上面）" % example)
		built.queue_free()
	await get_tree().process_frame


func _test_round_trip() -> void:
	print("--- 存檔再讀回來、to_dict 再 from_dict ---")
	DirAccess.make_dir_recursive_absolute(TEMP_FOLDER)
	for example: String in NAMES:
		var design: CreatureDesign = load(EXAMPLES + example + "/design.tres")
		var data: Dictionary = design.to_dict()
		ResourceSaver.save(design, TEMP_FOLDER + "round_trip.tres")
		var reloaded: CreatureDesign = ResourceLoader.load(TEMP_FOLDER + "round_trip.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		_expect(reloaded.to_dict() == data, "%s：存檔再讀回來不變" % example)
		_expect(CreatureDesign.from_data(data).to_dict() == data, "%s：to_dict → from_dict 不變" % example)
		_expect(CreatureDesign.from_data(bytes_to_var(var_to_bytes(data))).to_dict() == data, "%s：轉成位元組（連線傳的格式）再讀回來不變" % example)


func _test_garbage() -> void:
	print("--- 奇怪的資料 ---")
	var empty: CreatureDesign = CreatureDesign.from_data({})
	_expect(empty.body.segment_count == 16 and empty.legs.is_empty(), "空的資料：全部用預設值")

	var wrong: CreatureDesign = CreatureDesign.from_data({"creature_name": 5, "growth_mode": "快", "body": "身體", "legs": "腳", "eyes": [1, "x", null, {}]})
	_expect(wrong.creature_name == "我的生物" and wrong.growth_mode == 0, "型別錯的欄位：維持預設值")
	_expect(wrong.body != null and wrong.legs.is_empty(), "身體、腳不是正確格式：身體用預設、沒有腳")
	_expect(wrong.eyes.size() == 1, "零件清單裡不是 Dictionary 的項目略過（剩 %d 個）" % wrong.eyes.size())

	var extreme: CreatureDesign = CreatureDesign.from_data({
		"creature_name": "長".repeat(500),
		"growth_mode": 99,
		"body": {"segment_count": 99999, "spacing": NAN, "max_bend": 100.0, "thickness": -5, "outline_color": [5, -1, 0.5]},
		"legs": range(100).map(func(_i: int) -> Dictionary: return {"thigh_length": INF}),
		"ornaments": [{"image_file": "../../secret/evil.png", "offset": [1e9, -1e9]}, {"image_file": "virus.gd"}],
	})
	_expect(extreme.creature_name.length() == PartDesign.MAX_TEXT, "名字太長：剪到 %d 字" % PartDesign.MAX_TEXT)
	_expect(extreme.growth_mode == 2, "選單超出範圍：夾在最後一個選項")
	_expect(extreme.body.segment_count == 80, "節數 99999 → 80（實際 %d）" % extreme.body.segment_count)
	_expect(extreme.body.spacing == 14.0, "NaN 不收：維持預設 14")
	_expect(is_equal_approx(extreme.body.max_bend, PI), "彎曲角（弧度）超出範圍：夾在 180 度")
	_expect(extreme.body.thickness == 2.0, "粗細 -5 → 2")
	_expect(extreme.body.outline_color == Color(1, 0, 0.5), "顏色夾在 0～1")
	_expect(extreme.legs.size() == CreatureDesign.MAX_LEGS, "100 組腳 → 最多 %d 組" % CreatureDesign.MAX_LEGS)
	_expect(extreme.legs[0].thigh_length == 30.0, "無限大不收：維持預設")
	_expect(extreme.ornaments[0].image_file == "evil.png", "圖的檔名不能指到別的資料夾：只留檔名")
	_expect(extreme.ornaments[1].image_file == "", "不是 .png 的檔名：當作沒有圖")
	_expect(extreme.ornaments[0].offset == Vector2(PartDesign.MAX_OFFSET, -PartDesign.MAX_OFFSET), "位置偏移夾在範圍內")

	var bad_gradient: CreatureDesign = CreatureDesign.from_data({"body": {
		"body_gradient": {"offsets": [0, 1], "colors": [[1, 0, 0]]},
		"width_curve": {"points": range(100).map(func(i: int) -> Array: return [i / 100.0, 1, 0, 0])},
	}})
	var defaults := BodyDesign.new()
	_expect(_same(bad_gradient.body.body_gradient, defaults.body_gradient), "漸層的點數跟顏色數不合：維持預設")
	_expect(_same(bad_gradient.body.width_curve, defaults.width_curve), "曲線太多點：維持預設")

	var creature: Creature = _spawn(extreme)
	for i: int in 30:
		await get_tree().process_frame
	_expect(is_instance_valid(creature) and creature.get_body().joint_count() == 80, "用這份奇怪的設計長出生物、跑 30 幀不會當掉")
	creature.queue_free()


func _test_apply_in_place() -> void:
	print("--- 改設計檔後 apply_design() ---")
	var design: CreatureDesign = (load(EXAMPLES + "snake/design.tres") as CreatureDesign).duplicate(true)
	var creature: Creature = _spawn(design)
	await get_tree().process_frame
	var body: ChainBody = creature.get_body()
	design.body.segment_count = 30
	design.body.thickness = 25.0
	creature.apply_design()
	_expect(creature.get_body() == body and body.joint_count() == 30 and body.thickness == 25.0, "只改屬性：同一個身體節點，節數、粗細更新")
	design.legs.append(LegDesign.new())
	creature.apply_design()
	await get_tree().process_frame
	_expect(_parts_of(creature, IKLeg).size() == 1 and creature.get_body().joint_count() == 30, "加一組腳：重長，有 1 組腳、節數還是 30")
	_expect(creature.get_children().filter(func(n: Node) -> bool: return n is ChainBody).size() == 1, "重長後只有一個身體（舊的拿掉了）")
	creature.design = null
	_expect(creature.get_body() == null, "拿掉設計檔：身體、零件都拿掉")
	creature.queue_free()


func _test_not_saved() -> void:
	print("--- 長出來的節點不會存進場景檔 ---")
	var root := Node2D.new()
	add_child(root)
	var creature := Creature.new()
	creature.design = load(EXAMPLES + "dragon/design.tres")
	root.add_child(creature)
	creature.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	_expect(creature.get_child_count() > 0 and packed.get_state().get_node_count() == 2, "生物有 %d 個子節點，場景檔只存了 %d 個節點（根＋生物）" % [creature.get_child_count(), packed.get_state().get_node_count()])
	root.queue_free()


func _test_images() -> void:
	print("--- 自己的圖 ---")
	var doodle: Creature = _spawn(load(EXAMPLES + "doodle/design.tres"))
	await get_tree().process_frame
	var ornament: Ornament = _parts_of(doodle, Ornament)[0]
	var sprite: Sprite2D = ornament.get_node_or_null("Image") as Sprite2D
	_expect(sprite != null and sprite.texture != null, "塗鴉蛇的頭有圖")
	_expect(sprite != null and is_equal_approx(sprite.scale.x, 0.32), "圖的大小照設計檔")
	doodle.queue_free()

	# 剛存進來、還沒匯入的 PNG：直接讀檔
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.save_png(TEMP_FOLDER + "fresh.png")
	var design := CreatureDesign.new()
	design.image_folder = TEMP_FOLDER
	var texture: Texture2D = design.load_image("fresh.png")
	_expect(texture != null and texture.get_width() == 8, "還沒匯入的 PNG 也讀得到")
	_expect(design.load_image("not_here.png") == null and design.load_image("../fresh.gd") == null, "找不到的圖、怪檔名：回傳 null，不會當掉")


# ---------------------------------------------------------------- 工具


## 產生一隻生物。平衡資料不限制起始體型，長出來的樣子才會跟設計檔一模一樣（大小限制在 creature_growth_test 測）
func _spawn(design: CreatureDesign) -> Creature:
	var creature := Creature.new()
	var balance := CreatureBalance.new()
	balance.min_start_size = 1.0
	balance.max_start_size = 1e9
	creature.balance = balance
	creature.design = design
	creature.position = Vector2(640, 360)
	creature.control_mode = Creature.Mode.WANDER
	add_child(creature)
	return creature


## 生物身上某種零件，照節點順序
func _parts_of(creature: Creature, type: Variant) -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in creature.find_children("*", "", true, false):
		if is_instance_of(node, type):
			result.append(node)
	return result


## 身體底下零件的節點順序：掛的節數越來越靠頭（不會變大），眼睛都在最後
func _drawn_tail_to_head(creature: Creature) -> bool:
	var body: ChainBody = creature.get_body()
	var previous: int = 1 << 30
	for node: Node in body.get_children():
		if not node is CreaturePart:
			continue
		var layer: int = -1 if node is Eyes else body.resolve_index(node.get("attach_segment"))
		if layer > previous:
			return false
		previous = layer
	return true


## 兩個值一樣嗎（漸層、曲線比內容；小數用約等於）
func _same(a: Variant, b: Variant) -> bool:
	if a is Resource or b is Resource:
		return PartDesign.encode(a) == PartDesign.encode(b)
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _expect(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		_failures += 1
