extends Node
## 把舊的範例生物（example/creatures/*.tscn）轉成設計檔：example/creatures/<名字>/design.tres。
## 掛件底下有自己的圖（Sprite2D）的話，PNG 也複製到同一個資料夾。
## 只在改成設計檔的時候跑一次；之後範例直接改設計檔，舊的 .tscn 會刪掉。
##
## 在命令列執行（跑完再跑一次 --import，讓編輯器匯入複製過去的 PNG）：
##   godot --headless --path . res://_system/tests/make_example_designs.tscn

const FOLDER: String = "res://example/creatures/"
## 檔名 → 中文名字、長大方式、變長＋長出腳時每隔幾節一對（長大方式之後 N2 第二段再調）
const EXAMPLES: Dictionary = {
	"snake": ["蛇", CreatureDesign.Growth.LONGER, 4],
	"centipede": ["蜈蚣", CreatureDesign.Growth.LONGER_WITH_LEGS, 2],
	"octopus": ["章魚", CreatureDesign.Growth.SCALE, 4],
	"spider": ["蜘蛛", CreatureDesign.Growth.SCALE, 4],
	"jellyfish": ["水母", CreatureDesign.Growth.SCALE, 4],
	"dragon": ["龍", CreatureDesign.Growth.LONGER_WITH_LEGS, 6],
	"doodle": ["塗鴉蛇", CreatureDesign.Growth.LONGER, 4],
	"predator_eel": ["鰻魚", CreatureDesign.Growth.SCALE, 4],
}


func _ready() -> void:
	var failed: int = 0
	for file: String in EXAMPLES:
		if not _convert(file):
			failed += 1
	print("[範例設計檔] 完成，%d 隻失敗" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _convert(file: String) -> bool:
	var scene: PackedScene = load(FOLDER + file + ".tscn") as PackedScene
	var creature: Creature = scene.instantiate() as Creature if scene != null else null
	if creature == null or creature.get_body() == null:
		push_error("讀不到 %s.tscn，或它沒有身體" % file)
		return false
	var folder: String = FOLDER + file + "/"
	DirAccess.make_dir_recursive_absolute(folder)

	var design := CreatureDesign.new()
	design.creature_name = EXAMPLES[file][0]
	design.growth_mode = EXAMPLES[file][1]
	design.legs_every = EXAMPLES[file][2]
	design.body.capture_from(creature.get_body())
	for child: Node in creature.get_body().get_children():
		var part: PartDesign = _capture_part(child, folder)
		if part is LegDesign:
			design.legs.append(part)
		elif part is TentacleDesign:
			design.tentacles.append(part)
		elif part is EyesDesign:
			design.eyes.append(part)
		elif part is OrnamentDesign:
			design.ornaments.append(part)
	creature.free()

	var error: Error = ResourceSaver.save(design, folder + "design.tres")
	print("%s → %sdesign.tres（腳 %d、觸手 %d、眼睛 %d、掛件 %d）%s" % [file, folder, design.legs.size(), design.tentacles.size(), design.eyes.size(), design.ornaments.size(), "" if error == OK else "存檔失敗 %d" % error])
	return error == OK


## 一個零件節點 → 零件設計。掛件底下的 Sprite2D 變成「自己的圖」，PNG 複製到資料夾
func _capture_part(node: Node, folder: String) -> PartDesign:
	var part: PartDesign = null
	if node is IKLeg:
		part = LegDesign.new()
	elif node is Tentacle:
		part = TentacleDesign.new()
	elif node is Eyes:
		part = EyesDesign.new()
	elif node is Ornament:
		part = OrnamentDesign.new()
	else:
		return null
	part.capture_from(node)
	var sprite: Sprite2D = _first_sprite(node)
	if part is OrnamentDesign and sprite != null and sprite.texture != null:
		var source: String = sprite.texture.resource_path
		DirAccess.copy_absolute(source, folder + source.get_file())
		part.image_file = source.get_file()
		part.image_scale = sprite.scale.x
		part.image_rotation = sprite.rotation
	return part


func _first_sprite(node: Node) -> Sprite2D:
	for child: Node in node.get_children():
		if child is Sprite2D:
			return child
	return null
