@tool
class_name TentacleDesign
extends PartDesign
## 設計檔裡的「一組觸手」（對應 Tentacle 節點，欄位名稱一樣）。也可以當尾巴、鬍鬚、天線。

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭，-1 是最後一節（尾巴）
@export_range(-1, 80, 1) var attach_segment: int = 0
## 掛在哪一邊：兩邊會畫左右一對
@export_enum("左", "右", "兩邊", "中間") var side: int = CreaturePart.Side.BOTH

@export_group("形狀")
## 伸出角度：相對身體往前的方向，0 是往前、90 是往旁邊、180 是往後
@export_range(0, 180, 1, "radians_as_degrees") var reach_angle: float = deg_to_rad(150.0)
## 節數：越多越柔軟
@export_range(2, 40, 1) var segment_count: int = 10
## 長度（像素）
@export_range(10, 400, 1) var length: float = 80.0
## 根部粗細：中心到邊緣的距離（像素）
@export_range(0.5, 40, 0.5) var base_width: float = 6.0
## 末端粗細：中心到邊緣的距離（像素）
@export_range(0, 40, 0.5) var tip_width: float = 1.5

@export_group("動作")
## 行為：往後拖、波浪擺動、指向滑鼠、抓最近的食物
@export_enum("往後拖", "波浪擺動", "指向滑鼠", "抓最近的食物") var behavior: int = Tentacle.Behavior.DRAG
## 擺動幅度（像素）：觸手左右晃動的大小，0 是不晃
@export_range(0, 100, 1) var wave_amplitude: float = 15.0
## 擺動速度
@export_range(0, 10, 0.1) var wave_speed: float = 3.0
## FABRIK 迭代次數：越多越準；1 次會有「黏黏的」感覺
@export_range(1, 10, 1) var iterations: int = 4
## 抓取角度（抓最近的食物才有用）：只抓伸出方向左右各幾度以內的食物。越大越好抓，複雜度也越高
@export_range(10, 90, 1, "radians_as_degrees") var grab_angle: float = deg_to_rad(45.0)

@export_group("外觀")
## 顏色：從根部（左）到末端（右）的漸層。只放一個顏色就是單色
@export var color_gradient: Gradient = Tentacle._make_default_gradient()
## 吸盤：沿著觸手一側畫一排小圓點
@export var suckers: bool = true
## 吸盤顏色
@export var sucker_color: Color = Color("#f9d3e0")


## 等比放大時要一起放大的欄位
func length_fields() -> PackedStringArray:
	return PackedStringArray(["length", "base_width", "tip_width", "wave_amplitude"])
