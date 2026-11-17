@tool
class_name CreatureDesign
extends PartDesign
## 設計檔：一隻生物的全部樣子（身體、腳、觸手、眼睛、掛件、長大方式、用了哪些圖）。
##
## 一隻生物一個資料夾：my_creature/<生物名>/design.tres，自己畫的圖（PNG）放在同一個資料夾。
## 把設計檔拖進 Creature 的「設計檔」欄位，Creature 就會自己長出身體和零件，不用自己加節點。
##
## 連線時不傳 .tres（.tres 可以夾帶程式），改傳 to_dict() 的資料，收到後用 from_dict() 讀。

## 設計檔的格式版本：以後改欄位時，用這個判斷是不是舊的設計檔
const FORMAT_VERSION: int = 1
## 每種零件最多幾個（避免收到太大的資料、網頁版跑不動）
const MAX_LEGS: int = 16
const MAX_TENTACLES: int = 16
const MAX_EYES: int = 4
const MAX_ORNAMENTS: int = 24

## 長大方式的編號，跟「長大方式」選單的順序一樣
enum Growth { SCALE, LONGER_WITH_LEGS, LONGER }

@export_group("基本")
## 生物的名字
@export var creature_name: String = "我的生物"
## 設計檔的格式版本（程式用，不用改）
@export_storage var format_version: int = FORMAT_VERSION

@export_group("長大")
## 長大方式：等比放大（最均衡）、變長＋長出腳（速度維持、比較貴）、只變長（最便宜、越長越慢）
@export_enum("等比放大", "變長＋長出腳", "只變長") var growth_mode: int = Growth.SCALE
## 變長＋長出腳：每隔幾節長一對腳
@export_range(1, 20, 1) var legs_every: int = 4
## 變長的時候（變長＋長出腳、只變長），多出來的體型有幾成拿來加粗身體，其他拿來加節數變長。
## 0 是只變長、粗細不變；1 是只變粗、長度不變
@export_range(0, 1, 0.05) var thicken_ratio: float = 0.0

@export_group("噴出的飼料")
## 這一組是這隻生物掉出來的飼料長怎樣：加速時一路掉的、撞死時散出來的都是。只是外觀，不算能力。
## 名字都用 spray_ 開頭（工坊的「飼料」分頁靠這個找）
## 飼料的顏色（可以調透明度）
@export var spray_color: Color = Color("#ffd84d")
## 飼料的形狀
@export_enum("圓", "星星", "愛心", "菱形", "泡泡", "水滴") var spray_shape: int = 0
## 看起來多大（倍率）。只是外觀：被吃到的範圍不變
@export_range(0.5, 2.5, 0.05) var spray_size: float = 1.0
## 轉個角度
@export_range(0, 360, 1, "radians_as_degrees") var spray_angle: float = 0.0
## 星星有幾個角（形狀選星星才有用）
@export_range(3, 8, 1) var spray_star_points: int = 5
## 星星的胖瘦：越小越尖、越大越胖（形狀選星星才有用）
@export_range(0.2, 0.9, 0.05) var spray_star_inner: float = 0.45
## 要不要描一圈外框
@export var spray_outline: bool = false
## 外框的顏色
@export var spray_outline_color: Color = Color.WHITE
## 外框的寬度：佔飼料大小的幾成
@export_range(0.05, 0.5, 0.01) var spray_outline_width: float = 0.2
## 要不要有光暈
@export var spray_glow: bool = true
## 光暈的顏色（通常淡淡的、半透明比較好看）
@export var spray_glow_color: Color = Color(1.0, 0.847, 0.302, 0.2)
## 光暈有多大：飼料大小的幾倍
@export_range(1.1, 4.0, 0.05) var spray_glow_size: float = 1.8
## 光暈一呼一吸的幅度。0 是不動
@export_range(0, 1, 0.05) var spray_glow_pulse: float = 0.3
## 左上角要不要有一個亮點（看起來比較立體）
@export var spray_shine: bool = true
## 亮點的顏色
@export var spray_shine_color: Color = Color(1, 1, 1, 0.6)

@export_group("零件")
## 身體
@export var body: BodyDesign = BodyDesign.new()
## 腳：每一項是一組（「兩邊」就是一對）
@export var legs: Array[LegDesign] = []
## 觸手（也可以當尾巴、鬍鬚、天線）
@export var tentacles: Array[TentacleDesign] = []
## 眼睛：每一項是一排
@export var eyes: Array[EyesDesign] = []
## 掛件（角、翅膀、魚鰭……，或自己畫的圖）
@export var ornaments: Array[OrnamentDesign] = []

## 圖放在哪個資料夾。空的就用設計檔所在的資料夾（連線收到的設計檔沒有檔案，要另外指定）
var image_folder: String = ""
## 連線收到的圖：檔名 → Texture2D。不存檔、不傳（不是 @export），load_image() 先找這裡
var image_cache: Dictionary = {}


## 「噴出的飼料」的欄位（工坊放在「飼料」分頁）：所有 spray_ 開頭的欄位
func spray_fields() -> PackedStringArray:
	var result := PackedStringArray()
	for prop: Dictionary in fields():
		if (prop.name as String).begins_with("spray_"):
			result.append(prop.name)
	return result


## 所有掛載零件的設計，照產生的順序：觸手、腳、掛件、眼睛（眼睛最後畫，才在最上面）
func all_parts() -> Array[PartDesign]:
	var result: Array[PartDesign] = []
	result.append_array(tentacles)
	result.append_array(legs)
	result.append_array(ornaments)
	result.append_array(eyes)
	return result


## 讀資料時：身體、零件清單另外處理（每項各自 from_dict），數量有上限
func from_dict(data: Dictionary) -> void:
	super(data)
	format_version = FORMAT_VERSION
	body = BodyDesign.new()
	if data.get("body") is Dictionary:
		body.from_dict(data.body)
	legs.assign(_decode_list(data.get("legs"), LegDesign, MAX_LEGS))
	tentacles.assign(_decode_list(data.get("tentacles"), TentacleDesign, MAX_TENTACLES))
	eyes.assign(_decode_list(data.get("eyes"), EyesDesign, MAX_EYES))
	ornaments.assign(_decode_list(data.get("ornaments"), OrnamentDesign, MAX_ORNAMENTS))


## 從資料建立一份新的設計檔
static func from_data(data: Dictionary) -> CreatureDesign:
	var design := CreatureDesign.new()
	design.from_dict(data)
	return design


## 一串零件的資料 → 零件設計的清單。不是 Dictionary 的項目略過，超過上限的不要
static func _decode_list(value: Variant, script: GDScript, limit: int) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for item: Variant in value:
		if result.size() >= limit:
			break
		if item is Dictionary:
			var part: PartDesign = script.new()
			part.from_dict(item)
			result.append(part)
	return result


# ---------------------------------------------------------------- 找設計檔


## 列出資料夾裡的生物（一隻一個資料夾，裡面有 design.tres）。
## folders 是「資料夾 → 顯示的前綴」，例如 {"res://my_creature/": "我的"}，照順序列。
## 回傳 [{"path": 設計檔路徑, "label": "我的：小火龍（dragon）", "group": "我的", "name": "小火龍"}]
## 匯出的版本（網頁版）裡 design.tres 會變成 design.tres.remap，所以用 ResourceLoader.exists() 找，不用 FileAccess
static func list_designs(folders: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for folder: String in folders:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for sub: String in DirAccess.get_directories_at(folder):
			var path: String = folder + sub + "/design.tres"
			if not ResourceLoader.exists(path):
				continue
			var loaded: CreatureDesign = load_fresh(path)
			var creature_name: String = loaded.creature_name if loaded != null else "?"
			result.append({"path": path, "label": "%s：%s（%s）" % [folders[folder], creature_name, sub], "group": folders[folder], "name": creature_name})
	return result


## 從檔案讀一份新的設計檔（不用快取：工坊剛存過的也會是最新的）。讀不到回傳 null
static func load_fresh(path: String) -> CreatureDesign:
	if not ResourceLoader.exists(path):
		return null
	var loaded: CreatureDesign = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CreatureDesign
	if loaded != null:
		loaded.image_folder = path.get_base_dir()  # 不用快取讀的話，保險起見自己記住圖在哪
	return loaded


# ---------------------------------------------------------------- 自己的圖


## 圖的完整路徑（file 是設計檔裡寫的檔名）
func image_path(file: String) -> String:
	var folder: String = image_folder if image_folder != "" else resource_path.get_base_dir()
	return folder.path_join(OrnamentDesign.safe_image_file(file))


## 讀一張圖。連線收到的圖在 image_cache；編輯器已經匯入的用 load()；剛存進來、還沒匯入的直接讀 PNG 檔。讀不到回傳 null
func load_image(file: String) -> Texture2D:
	if OrnamentDesign.safe_image_file(file) == "":
		return null
	if image_cache.has(file):
		return image_cache[file] as Texture2D
	if image_folder == "" and resource_path == "":
		return null  # 不是從檔案讀的設計檔（連線收到的），沒有資料夾可以找
	var path: String = image_path(file)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)
		if image != null:
			return ImageTexture.create_from_image(image)
	return null
