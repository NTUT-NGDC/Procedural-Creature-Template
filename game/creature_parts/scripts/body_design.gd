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


## 等比放大時要一起放大的欄位
func length_fields() -> PackedStringArray:
	return PackedStringArray(["spacing", "thickness", "swim_amplitude"])
