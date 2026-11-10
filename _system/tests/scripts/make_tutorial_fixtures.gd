extends Node
## 產生教學關檢查用的範例資料夾（_system/tests/tutorial_fixtures/）。
## 每個資料夾模擬一種「社員的 my_creature」，tutorial_checker_test.gd 檢查每一步該不該過。
##
## 零件或範例生物改了之後，重新產生一次：
##   godot --headless --path . res://_system/tests/make_tutorial_fixtures.tscn

const OUT: String = "res://_system/tests/tutorial_fixtures/"
const EXAMPLES: String = "res://example/creatures/"
const LEG: GDScript = preload("res://game/creature_parts/scripts/ik_leg.gd")
const TENTACLE: GDScript = preload("res://game/creature_parts/scripts/tentacle.gd")
const ORNAMENT: GDScript = preload("res://game/creature_parts/scripts/ornament.gd")
const GROW_SCRIPT: GDScript = preload("res://example/grow_challenge/grow_challenge.gd")


func _ready() -> void:
	_clean(OUT)
	DirAccess.make_dir_recursive_absolute(OUT)
	FileAccess.open(OUT + ".gdignore", FileAccess.WRITE).store_string("")

	_write_text("empty/.keep", "")
	_write_text("garbage/broken.tscn", "這不是場景 {{{")
	var plain := Node2D.new()
	_save(plain, "garbage/not_creature.tscn")

	_save(_example("snake"), "same_name/snake.tscn")
	_save(_example("snake"), "copy_only/my_snake.tscn")
	_save(_example("snake", {"Body": {"segment_count": 30}}), "body_one/my_snake.tscn")
	_save(_example("snake", {"Body": {"segment_count": 30, "pattern": 2}}), "body_two/my_snake.tscn")
	_save(_with_child(_example("snake"), "Body", LEG, "Legs", {}), "legs_added/my_snake.tscn")
	_save(_example("spider"), "spider_same/my_spider.tscn")
	_save(_example("spider", {"Body/Legs1": {"thigh_length": 40.0}}), "spider_leg_changed/my_spider.tscn")
	_save(_with_child(_example("snake"), "Body", TENTACLE, "Tail", {"behavior": Tentacle.Behavior.GRAB_FOOD}), "tentacle_grab/my_snake.tscn")

	# 池塘：玩家還是範例的蛇
	_save(_example("snake"), "pond_example_player/my_snake.tscn")
	_save(_pond({"food_count": 10}), "pond_example_player/my_pond.tscn")
	# 池塘：玩家換了，規則沒改
	_save(_example("snake"), "pond_no_rule/my_snake.tscn")
	_save(_pond({"player_creature": OUT + "pond_no_rule/my_snake.tscn"}), "pond_no_rule/my_pond.tscn")

	# 寫一點程式：有腳本但沒接 grew、腳本裡用程式接 grew
	_write_text("script_no_connect/effect.gd", "extends Node\n\n\nfunc _ready() -> void:\n\tprint(\"hello\")\n")
	_save(_with_script_node(_example("snake"), OUT + "script_no_connect/effect.gd", false), "script_no_connect/my_snake.tscn")
	_write_text("script_code_connect/effect.gd", "extends Node\n\n\nfunc _ready() -> void:\n\t(get_parent() as Creature).grew.connect(_on_grew)\n\n\nfunc _on_grew(_level: int) -> void:\n\tpass\n")
	_save(_with_script_node(_example("snake"), OUT + "script_code_connect/effect.gd", false), "script_code_connect/my_snake.tscn")

	# 掛件：預設的角（不算）、形狀「無」＋底下放圖（算）
	_save(_with_child(_example("snake"), "Body", ORNAMENT, "Horn", {}), "ornament_horn/my_snake.tscn")
	var sticker: Node = _with_child(_example("snake"), "Body", ORNAMENT, "Sticker", {"shape": Ornament.Shape.NONE})
	var sprite := Sprite2D.new()
	sprite.name = "Art"
	sprite.texture = load("res://icon.svg")
	sticker.get_node("Body/Sticker").add_child(sprite)
	_save(sticker, "ornament_sprite/my_snake.tscn")

	# 存錯地方：複製的生物留在範例資料夾（給 examples_folder 參數用）
	_save(_example("snake"), "misplaced_examples/snake.tscn")
	_save(_example("snake"), "misplaced_examples/my_snake.tscn")

	_make_full_pass()
	print("tutorial_fixtures 產生完成")
	get_tree().quit()


## 每一步都做到的社員資料夾（第 6 步要再試玩）
func _make_full_pass() -> void:
	var folder: String = OUT + "full_pass/"
	var creature: Node = _example("snake", {"Body": {"segment_count": 30, "pattern": 2}})
	_with_child(creature, "Body", LEG, "Legs", {})
	_with_child(creature, "Body", TENTACLE, "Whisker", {"behavior": Tentacle.Behavior.GRAB_FOOD})
	_with_child(creature, "Body", ORNAMENT, "Wings", {"shape": Ornament.Shape.WING, "side": CreaturePart.Side.BOTH})
	_with_script_node(creature, GROW_SCRIPT.resource_path, true)
	_save(creature, "full_pass/my_snake.tscn")
	_save(_example("predator_eel", {"Body": {"thickness": 30.0}}), "full_pass/my_eel.tscn")
	_save(_pond({"player_creature": folder + "my_snake.tscn", "predator_creature": folder + "my_eel.tscn", "food_count": 10}), "full_pass/my_pond.tscn")
	# 標題畫面：Pond Scene 接上自己的池塘
	var title: Control = (load("res://game/title_screen/title_screen.tscn") as PackedScene).instantiate()
	title.set("pond_scene", folder + "my_pond.tscn")
	_save(title, "full_pass/title_screen.tscn")


# ---------------------------------------------------------------- 工具


## 實例化一隻範例生物，changes 是 {節點路徑: {屬性: 值}}（"." 是最上層）
func _example(file_name: String, changes: Dictionary = {}) -> Node:
	var root: Node = (load(EXAMPLES + file_name + ".tscn") as PackedScene).instantiate()
	for node_path: String in changes:
		var node: Node = root.get_node(node_path)
		for property: String in changes[node_path]:
			node.set(property, changes[node_path][property])
	return root


func _with_child(root: Node, parent_path: String, script: GDScript, node_name: String, props: Dictionary) -> Node:
	var node: Node = script.new()
	node.name = node_name
	for property: String in props:
		node.set(property, props[property])
	root.get_node(parent_path).add_child(node)
	return root


## 在生物底下加一個掛腳本的節點；connect_grew 時用「編輯器連接」的方式接上 grew
func _with_script_node(root: Node, script_path: String, connect_grew: bool) -> Node:
	var node := Node.new()
	node.name = "Effect"
	node.set_script(load(script_path))
	root.add_child(node)
	if connect_grew:
		root.connect("grew", Callable(node, "_on_creature_grew"), CONNECT_PERSIST)
	return root


## 範例池塘，props 是要改的屬性（生物的值給路徑字串）
func _pond(props: Dictionary) -> Node:
	var pond: Node = (load("res://example/pond/pond.tscn") as PackedScene).instantiate()
	for property: String in props:
		var value: Variant = props[property]
		pond.set(property, load(value) if value is String and (value as String).ends_with(".tscn") else value)
	return pond


## 存成完整的場景（不是繼承範例的場景）
func _save(root: Node, relative_path: String) -> void:
	root.scene_file_path = ""
	for node: Node in root.find_children("*", "", true, false):
		if node.owner == null or node.owner == root:
			node.owner = root
	var path: String = OUT + relative_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packed := PackedScene.new()
	packed.pack(root)
	var error: Error = ResourceSaver.save(packed, path)
	if error != OK:
		push_error("存不了 %s：%s" % [path, error_string(error)])
	root.free()


func _write_text(relative_path: String, text: String) -> void:
	var path: String = OUT + relative_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(text)


## 刪掉舊的範例資料夾（只刪這個資料夾裡的東西）
func _clean(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub: String in DirAccess.get_directories_at(folder):
		_clean(folder.path_join(sub))
		DirAccess.remove_absolute(folder.path_join(sub))
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
