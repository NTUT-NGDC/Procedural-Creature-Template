@tool
class_name BodyDesign
extends PartDesign
## 設計檔裡的「身體」（對應 ChainBody 節點，欄位名稱一樣）。

@export_group("形狀")
## 節數：身體有幾節（含頭）
@export_range(2, 80, 1) var segment_count: int = 16
## 間距：每節之間的距離（像素）
@export_range(4, 60, 1) var spacing: float = 14.0
## 最大彎曲角：每節跟前一節最多能彎幾度。越小身體越直，180 等於不限制
@export_range(5, 180, 1, "radians_as_degrees") var max_bend: float = deg_to_rad(30.0)
## 粗細：身體最粗的地方，中心到邊緣的距離（像素）
@export_range(2, 80, 1) var thickness: float = 16.0
## 粗細曲線：從頭（左）到尾（右）的粗細比例，1 是最粗
@export var width_curve: Curve = ChainBody._make_default_curve()

@export_group("動作")
## 游動擺幅（像素）：往前走時身體左右擺動的幅度，0 是不擺
@export_range(0, 40, 0.5) var swim_amplitude: float = 0.0
## 游動頻率：每秒擺幾次
@export_range(0, 6, 0.1) var swim_frequency: float = 2.0

@export_group("外觀")
## 身體顏色：從頭（左）到尾（右）的漸層。只放一個顏色就是單色
@export var body_gradient: Gradient = ChainBody._make_default_gradient()
## 外框顏色
@export var outline_color: Color = Color("#cdeccf")
## 外框粗細（像素），0 是沒有外框
@export_range(0, 10, 0.5) var outline_width: float = 2.5
## 花紋
@export_enum("無", "斑點", "條紋", "背鰭") var pattern: int = ChainBody.Pattern.SPOTS
## 花紋顏色
@export var pattern_color: Color = Color("#2f6e45")

@export_group("自己的圖")
## 頭那一節的圖（PNG 檔名，放在生物的資料夾）。畫的時候頭朝右
@export var head_image: String = ""
## 頭的圖大小：1 是圖剛好跟身體最粗的地方一樣粗
@export_range(0.1, 5, 0.05) var head_image_scale: float = 1.0
## 每一節的圖（像鱗片、珠子）。沒有頭、尾巴的圖時，頭和尾巴也用這張
@export var segment_image: String = ""
## 每一節的圖大小：1 是圖剛好跟那一節一樣粗
@export_range(0.1, 5, 0.05) var segment_image_scale: float = 1.0
## 尾巴那一節的圖
@export var tail_image: String = ""
## 尾巴的圖大小：1 是圖剛好跟身體最粗的地方一樣粗
@export_range(0.1, 5, 0.05) var tail_image_scale: float = 1.0
## 圖的旋轉（度）：畫的時候頭不是朝右，用這個轉回來
@export_range(-180, 180, 1, "radians_as_degrees") var image_rotation: float = 0.0
## 也畫身體：勾起來是圖疊在程式畫的身體上面（像鱗片）；不勾只畫圖（像一串珠子）
@export var draw_body: bool = true


## 等比放大時要一起放大的欄位
func length_fields() -> PackedStringArray:
	return PackedStringArray(["spacing", "thickness", "swim_amplitude"])


## 圖的檔名只在設計檔裡；身體節點拿的是讀好的圖（Creature 幫忙讀）
func design_only_fields() -> PackedStringArray:
	return PackedStringArray(image_fields())


## 放圖的欄位（工坊顯示「匯入圖片」、存檔時把圖一起複製）
static func image_fields() -> PackedStringArray:
	return PackedStringArray(["head_image", "segment_image", "tail_image"])


## 讀舊的設計檔（.tres）：以前只有一個「圖的大小」（image_scale），三張圖都用它。回傳 true 表示認得這個欄位
func _set(property: StringName, value: Variant) -> bool:
	if property == &"image_scale" and (value is float or value is int):
		var scale: float = clampf(float(value), 0.1, 5.0)
		head_image_scale = scale
		segment_image_scale = scale
		tail_image_scale = scale
		return true
	return false


## 讀資料時，圖的檔名只留「檔名」本身、而且要是 .png，不能指到別的資料夾
func from_dict(data: Dictionary) -> void:
	super(data)
	# 舊的設計檔只有一個「圖的大小」（image_scale）：三張圖都用它
	var old_scale: Variant = data.get("image_scale")
	if (old_scale is float or old_scale is int) and not data.has("segment_image_scale"):
		var scale: float = clampf(float(old_scale), 0.1, 5.0)
		head_image_scale = scale
		segment_image_scale = scale
		tail_image_scale = scale
	for field: String in image_fields():
		set(field, OrnamentDesign.safe_image_file(get(field)))
