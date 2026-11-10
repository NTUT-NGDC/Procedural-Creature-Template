class_name CreatureChecker
extends RefCounted
## 教學關的檢查邏輯：讀 my_creature 資料夾裡的生物和池塘，判斷每一步有沒有做到。
##
## 每個場景都用 ResourceLoader（不用快取）讀一次、實例化、整理成「摘要」（有哪些零件、屬性是多少），
## 再拿摘要跟「來源範例」比（生物根節點的 metadata/source_example 記著是從哪隻範例複製的）。
## 檔案壞掉、根節點不對、資料夾是空的，都只會讓那一步沒過，不會讓教學關當掉。
##
## 第 1～4 步：my_creature 裡任一隻生物符合就算過。

## 一步的檢查結果：passed 是有沒有過；message 沒過時是原因，過了時是哪個檔案過的
class Result:
	var passed: bool
	var message: String

	func _init(is_passed: bool, text: String) -> void:
		passed = is_passed
		message = text


const DEFAULT_TITLE_SCENE: String = "res://game/title_screen/title_screen.tscn"
const DEFAULT_EXAMPLES_FOLDER: String = "res://example/creatures/"
const DEFAULT_EXAMPLE_POND: String = "res://example/pond/pond.tscn"
## 生物零件的腳本都在這裡，其他腳本才算「自己寫的」
const PARTS_FOLDER: String = "res://game/creature_parts/"

## 要比對的屬性和中文名稱（顯示原因時用）
const BODY_PROPERTIES: Dictionary = {
	"segment_count": "節數", "spacing": "間距", "max_bend": "最大彎曲角", "thickness": "粗細",
	"width_curve": "粗細曲線", "segments_per_growth": "每次成長加幾節", "full_body_collision": "全身碰撞",
	"swim_amplitude": "游動擺幅", "swim_frequency": "游動頻率", "body_gradient": "身體顏色",
	"outline_color": "外框顏色", "outline_width": "外框粗細", "pattern": "花紋", "pattern_color": "花紋顏色",
}
const LEG_PROPERTIES: PackedStringArray = [
	"attach_segment", "side", "thigh_length", "shin_length", "knee_direction", "rest_angle", "rest_distance",
	"step_distance", "step_time", "lead", "lift_height", "group", "leg_width", "leg_color",
]
const TENTACLE_PROPERTIES: PackedStringArray = [
	"attach_segment", "side", "reach_angle", "segment_count", "length", "base_width", "tip_width",
	"behavior", "wave_amplitude", "wave_speed", "iterations", "color_gradient", "suckers", "sucker_color",
]
## 池塘的規則屬性（玩家生物、天敵生物另外檢查）
const POND_PROPERTIES: PackedStringArray = [
	"game_name", "player_control", "win_condition", "target_value", "time_limit", "food_count", "food_flees",
	"food_color", "predator_count", "predator_speed_scale", "predator_detect_range", "bite_damage",
	"bite_halves", "predator_every", "water_color", "background", "music",
]

var _folder: String
var _title_scene: String
var _examples_folder: String
var _example_pond: String
## my_creature 裡的生物、池塘摘要；讀不懂的檔案（路徑 → 原因）
var _creatures: Array[Dictionary] = []
var _ponds: Array[Dictionary] = []
var _broken: Dictionary = {}
## 範例的檔名（不含 .tscn）、讀過的範例摘要（快取）
var _example_names: PackedStringArray = []
var _example_cache: Dictionary = {}


func _init(folder: String, title_scene: String = DEFAULT_TITLE_SCENE, examples_folder: String = DEFAULT_EXAMPLES_FOLDER, example_pond: String = DEFAULT_EXAMPLE_POND) -> void:
	_folder = folder.trim_suffix("/") + "/"
	_title_scene = title_scene
	_examples_folder = examples_folder.trim_suffix("/") + "/"
	_example_pond = example_pond
	for file: String in _list_scenes(_examples_folder):
		_example_names.append(file.get_file().get_basename())
	for path: String in _list_scenes(_folder):
		_read_scene(path)


# ---------------------------------------------------------------- 十個步驟


## 1. 複製一隻範例生物：my_creature 有根節點是 Creature 的場景，而且檔名不跟範例一樣
func check_copy() -> Result:
	for creature: Dictionary in _creatures:
		if not creature.file_name in _example_names:
			return Result.new(true, _short(creature.path))
	if not _creatures.is_empty():
		var first: Dictionary = _creatures[0]
		return Result.new(false, "找到 %s，但檔名跟範例一樣，請改一個自己的名字（在檔案系統對檔案按右鍵 → 重新命名）。" % _short(first.path))
	var misplaced: String = _find_misplaced_copy()
	if misplaced != "":
		return Result.new(false, "在 %s 找到你複製的生物，但它要放在 %s 資料夾裡。" % [_short(misplaced), _short(_folder).trim_suffix("/")])
	if not _broken.is_empty():
		return Result.new(false, "%s 讀不出來：%s" % [_short(_broken.keys()[0]), _broken.values()[0]])
	return Result.new(false, "%s 資料夾裡還沒有生物（根節點是 Creature 的 .tscn）。" % _short(_folder).trim_suffix("/"))


## 2. 改身體：ChainBody 的屬性跟來源範例比，至少 2 項不一樣
func check_body() -> Result:
	if _creatures.is_empty():
		return Result.new(false, "先完成第 1 步。")
	var best_changes: PackedStringArray = []
	var has_body: bool = false
	for creature: Dictionary in _creatures:
		if creature.body == null:
			continue
		has_body = true
		var source: Dictionary = _source_of(creature)
		var changes: PackedStringArray = _changed_properties(creature.body, source.get("body"), BODY_PROPERTIES.keys())
		if changes.size() >= 2:
			return Result.new(true, "%s（改了%s）" % [_short(creature.path), _chinese_names(changes)])
		if changes.size() > best_changes.size():
			best_changes = changes
	if not has_body:
		return Result.new(false, "你的生物沒有身體：在生物底下加一個 ChainBody 節點。")
	if best_changes.is_empty():
		return Result.new(false, "身體（Body）的屬性都跟範例一樣，至少改 2 項（例如節數、粗細、身體顏色）。")
	return Result.new(false, "只改了 1 項（%s），還要再改 1 項。" % _chinese_names(best_changes))


## 3. 加一對腳：IKLeg 比來源範例多；範例本來就有腳的話，至少改了一個腳的屬性也算
func check_legs() -> Result:
	return _check_parts("legs", LEG_PROPERTIES, "腳", "IKLeg")


## 4. 加觸手或尾巴：Tentacle 比來源範例多；範例本來就有的話，至少改了一個觸手的屬性也算
func check_tentacles() -> Result:
	return _check_parts("tentacles", TENTACLE_PROPERTIES, "觸手", "Tentacle")


## 5. 做自己的池塘：my_creature 有池塘；玩家生物指向 my_creature；至少一個規則屬性跟範例池塘不同
func check_pond() -> Result:
	if _ponds.is_empty():
		return Result.new(false, "%s 資料夾裡還沒有池塘：把 example/pond/pond.tscn 複製過來（按右鍵 → 複製）。" % _short(_folder).trim_suffix("/"))
	var reason: String = ""
	var example: Dictionary = _example_pond_summary()
	for pond: Dictionary in _ponds:
		if not _is_mine(pond.player):
			reason = "你的池塘（%s）還在用範例的生物（%s），把 Player Creature 換成你的生物。" % [_short(pond.path), _short(pond.player) if pond.player != "" else "空的"]
			continue
		var changes: PackedStringArray = _changed_properties(pond.rules, example.get("rules"), POND_PROPERTIES)
		if changes.is_empty():
			reason = "池塘（%s）的規則都跟範例一樣，至少改一條（例如 Food Count、Predator Count）。" % _short(pond.path)
			continue
		return Result.new(true, _short(pond.path))
	return Result.new(false, reason)


## 6. 接上標題、玩到結算：標題畫面的 Pond Scene 指向自己的池塘，而且在教學關試玩到贏或輸
func check_title_and_play(play_succeeded: bool, played_pond: String) -> Result:
	var pond_path: String = get_title_pond()
	if pond_path == "":
		return Result.new(false, "讀不到標題畫面的 Pond Scene。")
	if not _is_mine(pond_path):
		return Result.new(false, "標題畫面的 Pond Scene 還是 %s：打開 game/title_screen/title_screen.tscn，點 TitleScreen，把你的池塘拖進 Pond Scene。" % _short(pond_path))
	if not play_succeeded or played_pond != pond_path:
		return Result.new(false, "標題已經接上 %s，按上面的「試玩」玩到贏或輸。" % _short(pond_path))
	return Result.new(true, "%s 玩到結算了" % _short(pond_path))


## 7. 額外：自己的天敵：池塘的天敵生物指向 my_creature
func check_predator() -> Result:
	if _ponds.is_empty():
		return Result.new(false, "先完成第 5 步（做自己的池塘）。")
	for pond: Dictionary in _ponds:
		if _is_mine(pond.predator):
			return Result.new(true, "%s 的天敵是 %s" % [_short(pond.path), _short(pond.predator)])
	return Result.new(false, "池塘的天敵還是範例的生物：做一隻自己的天敵放在 %s，拖進池塘的 Predator Creature。" % _short(_folder).trim_suffix("/"))


## 8. 額外：觸手抓食物：自己的生物有 Tentacle 的行為是「抓最近的食物」
func check_grab() -> Result:
	for creature: Dictionary in _creatures:
		for tentacle: Dictionary in creature.tentacles:
			if tentacle.get("behavior") == Tentacle.Behavior.GRAB_FOOD:
				return Result.new(true, _short(creature.path))
	return Result.new(false, "還沒有觸手會抓食物：把一個 Tentacle 的 Behavior 改成「抓最近的食物」。")


## 9. 額外：寫一點程式：自己的生物場景掛了自己的腳本，而且有連接 grew 訊號
func check_script() -> Result:
	var has_script: bool = false
	for creature: Dictionary in _creatures:
		has_script = has_script or creature.has_own_script
		if creature.has_own_script and creature.grew_connected:
			return Result.new(true, _short(creature.path))
	if has_script:
		return Result.new(false, "有掛自己的腳本了，但還沒連接 grew 訊號（點生物最上層的節點 → 節點分頁 → 雙擊 grew）。")
	return Result.new(false, "還沒有掛自己的腳本：參考 example/grow_challenge，在生物底下加一個節點、掛上腳本。")


## 10. 額外：加一個掛件：自己的生物有 Ornament，形狀不是預設的「角」，或底下放了 Sprite2D／Polygon2D
func check_ornament() -> Result:
	var has_ornament: bool = false
	for creature: Dictionary in _creatures:
		for ornament: Dictionary in creature.ornaments:
			has_ornament = true
			if ornament.shape != Ornament.Shape.HORN or ornament.has_art:
				return Result.new(true, _short(creature.path))
	if has_ornament:
		return Result.new(false, "掛件還是預設的「角」：換一個形狀，或在掛件底下放自己畫的圖（Sprite2D）。")
	return Result.new(false, "還沒有掛件：在 Body 底下加一個 Ornament 節點。")


## 標題畫面的 Pond Scene 指向哪個池塘（一般路徑），讀不到就是空字串
func get_title_pond() -> String:
	var scene: PackedScene = _load_scene(_title_scene)
	if scene == null:
		return ""
	var value: Variant = _root_property(scene, &"pond_scene")
	if value == null:
		# 場景裡沒改過就是腳本的預設值
		var script: Script = _root_property(scene, &"script") as Script
		value = script.get_property_default_value(&"pond_scene") if script != null else null
	if not value is String or value == "":
		return ""
	return ResourceUID.ensure_path(value) if (value as String).begins_with("uid://") else value


# ---------------------------------------------------------------- 讀檔、整理摘要


func _read_scene(path: String) -> void:
	var scene: PackedScene = _load_scene(path)
	if scene == null:
		_broken[path] = "檔案壞掉了或不是場景"
		return
	var root: Node = scene.instantiate()
	if root == null:
		_broken[path] = "場景打不開"
		return
	if root is Creature:
		_creatures.append(_summarize_creature(path, scene, root))
	elif root is Pond:
		_ponds.append(_summarize_pond(path, root))
	root.free()


func _summarize_creature(path: String, scene: PackedScene, root: Node) -> Dictionary:
	var summary: Dictionary = {
		"path": path, "file_name": path.get_file().get_basename(),
		"source": str(root.get_meta("source_example", "")),
		"body": null, "legs": [], "tentacles": [], "ornaments": [],
		"has_own_script": false, "grew_connected": _grew_connected(scene),
	}
	for node: Node in [root] + root.find_children("*", "", true, false):
		var script: Script = node.get_script() as Script
		if script != null and not script.resource_path.begins_with(PARTS_FOLDER):
			summary.has_own_script = true
		if node is ChainBody and summary.body == null:
			summary.body = _read_properties(node, BODY_PROPERTIES.keys())
		elif node is IKLeg:
			summary.legs.append(_read_properties(node, LEG_PROPERTIES))
		elif node is Tentacle:
			summary.tentacles.append(_read_properties(node, TENTACLE_PROPERTIES))
		elif node is Ornament:
			var has_art: bool = false
			for child: Node in node.get_children():
				has_art = has_art or child is Sprite2D or child is Polygon2D
			summary.ornaments.append({"shape": node.get("shape"), "has_art": has_art})
	return summary


func _summarize_pond(path: String, root: Node) -> Dictionary:
	var player: PackedScene = root.get("player_creature") as PackedScene
	var predator: PackedScene = root.get("predator_creature") as PackedScene
	return {
		"path": path, "rules": _read_properties(root, POND_PROPERTIES),
		"player": player.resource_path if player != null else "",
		"predator": predator.resource_path if predator != null else "",
	}


## 有沒有連接 grew 訊號：在編輯器連接的（存在場景裡），或是自己的腳本裡有寫 grew.connect
func _grew_connected(scene: PackedScene) -> bool:
	var state: SceneState = scene.get_state()
	for i: int in state.get_connection_count():
		if state.get_connection_signal(i) == &"grew":
			return true
	var root: Node = scene.instantiate()
	var connected: bool = false
	for node: Node in [root] + root.find_children("*", "", true, false):
		var script: GDScript = node.get_script() as GDScript
		if script != null and not script.resource_path.begins_with(PARTS_FOLDER) and "grew.connect" in script.source_code:
			connected = true
	root.free()
	return connected


## 讀出屬性，換成可以直接比較的值（Curve、Gradient 比內容，小數四捨五入）
func _read_properties(node: Node, names: Array) -> Dictionary:
	var values: Dictionary = {}
	for property: String in names:
		values[property] = _comparable(node.get(property))
	return values


static func _comparable(value: Variant) -> Variant:
	if value is Gradient:
		return var_to_str([(value as Gradient).offsets, (value as Gradient).colors])
	if value is Curve:
		var points: Array = []
		for i: int in (value as Curve).point_count:
			points.append((value as Curve).get_point_position(i))
		return var_to_str(points)
	if value is Resource:
		return (value as Resource).resource_path
	if value is float:
		return snappedf(value, 0.0001)
	return value


# ---------------------------------------------------------------- 比對


## 第 3、4 步共用：零件比來源範例多，或範例本來就有、而且改了屬性
func _check_parts(key: String, properties: PackedStringArray, label: String, node_type: String) -> Result:
	if _creatures.is_empty():
		return Result.new(false, "先完成第 1 步。")
	var same_count: bool = false
	for creature: Dictionary in _creatures:
		var source_parts: Array = _source_of(creature).get(key, [])
		var parts: Array = creature[key]
		if parts.size() > source_parts.size():
			return Result.new(true, "%s（%s：範例 %d 個 → %d 個）" % [_short(creature.path), node_type, source_parts.size(), parts.size()])
		if not source_parts.is_empty() and not parts.is_empty() and _sorted_strings(parts) != _sorted_strings(source_parts):
			return Result.new(true, "%s（改了%s的屬性）" % [_short(creature.path), label])
		same_count = same_count or (not parts.is_empty())
	if same_count:
		return Result.new(false, "%s的數量跟範例一樣，也沒有改%s的屬性：再加一個 %s，或改一個%s的屬性。" % [label, label, node_type, label])
	return Result.new(false, "還沒有%s：在 Body 底下加一個 %s 節點。" % [label, node_type])


## 哪些屬性跟來源不一樣（來源讀不到時，全部都算不一樣）
static func _changed_properties(values: Dictionary, source: Variant, names: Array) -> PackedStringArray:
	var changes: PackedStringArray = []
	for property: String in names:
		if not source is Dictionary or values.get(property) != (source as Dictionary).get(property):
			changes.append(property)
	return changes


static func _sorted_strings(parts: Array) -> PackedStringArray:
	var strings: PackedStringArray = []
	for part: Dictionary in parts:
		strings.append(var_to_str(part))
	strings.sort()
	return strings


## 來源範例的摘要（metadata/source_example 記著從哪隻範例複製），讀不到就是空的
func _source_of(creature: Dictionary) -> Dictionary:
	var source: String = creature.source
	if source == "":
		return {}
	if not _example_cache.has(source):
		_example_cache[source] = {}
		var path: String = _examples_folder + source + ".tscn"
		var scene: PackedScene = _load_scene(path)
		var root: Node = scene.instantiate() if scene != null else null
		if root is Creature:
			_example_cache[source] = _summarize_creature(path, scene, root)
		if root != null:
			root.free()
	return _example_cache[source]


func _example_pond_summary() -> Dictionary:
	var scene: PackedScene = _load_scene(_example_pond)
	var root: Node = scene.instantiate() if scene != null else null
	var summary: Dictionary = _summarize_pond(_example_pond, root) if root is Pond else {}
	if root != null:
		root.free()
	return summary


## 範例資料夾裡多出來的生物（社員複製後存在範例資料夾，沒有搬到 my_creature）
func _find_misplaced_copy() -> String:
	for path: String in _list_scenes(_examples_folder):
		var scene: PackedScene = _load_scene(path)
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		var misplaced: bool = root is Creature and str(root.get_meta("source_example", "")) != path.get_file().get_basename()
		root.free()
		if misplaced:
			return path
	return ""


func _is_mine(path: String) -> bool:
	return path.begins_with(_folder)


# ---------------------------------------------------------------- 工具


func _chinese_names(properties: PackedStringArray) -> String:
	var names: PackedStringArray = []
	for property: String in properties:
		names.append(BODY_PROPERTIES.get(property, property))
	return "、".join(names)


## 顯示用的短路徑：拿掉 res://
static func _short(path: String) -> String:
	return path.trim_prefix("res://")


static func _load_scene(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene


## 資料夾（含子資料夾）裡所有 .tscn 的路徑
static func _list_scenes(folder: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(folder):
		return paths
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() == "tscn":
			paths.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		if not sub.begins_with("."):
			paths.append_array(_list_scenes(folder.path_join(sub)))
	return paths


## 不實例化，直接從場景檔讀最上層節點的屬性（繼承的場景會往原本的場景找）
static func _root_property(scene: PackedScene, property: StringName) -> Variant:
	if scene == null:
		return null
	var state: SceneState = scene.get_state()
	for i: int in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == property:
			return state.get_node_property_value(0, i)
	return _root_property(state.get_node_instance(0), property)
