@tool
class_name LegDesign
extends PartDesign
## 設計檔裡的「一組腳」（對應 IKLeg 節點，欄位名稱一樣）。「兩邊」就是左右一對。

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭，-1 是最後一節
@export_range(-1, 80, 1) var attach_segment: int = 1
## 掛在哪一邊：兩邊會畫左右一對
@export_enum("左", "右", "兩邊") var side: int = CreaturePart.Side.BOTH

@export_group("形狀")
## 大腿長（像素）
@export_range(4, 200, 1) var thigh_length: float = 30.0
## 小腿長（像素）
@export_range(4, 200, 1) var shin_length: float = 34.0
## 膝蓋方向：向外是像蜘蛛一樣張開，向內相反
@export_enum("向外", "向內") var knee_direction: int = IKLeg.Knee.OUTWARD

@export_group("動作")
## 落腳角度：理想落腳點相對身體往前的方向，0 是往前、90 是往旁邊、180 是往後
@export_range(0, 180, 1, "radians_as_degrees") var rest_angle: float = deg_to_rad(70.0)
## 落腳距離：理想落腳點離髖關節多遠，是「大腿＋小腿」的幾倍
@export_range(0.2, 1.0, 0.05) var rest_distance: float = 0.75
## 跨步距離（像素）：腳掌離理想落腳點多遠就抬腳
@export_range(2, 200, 1) var step_distance: float = 24.0
## 跨步時間（秒）：抬一次腳要多久
@export_range(0.02, 1.0, 0.01) var step_time: float = 0.12
## 預判（秒）：抬腳時往移動方向多跨幾秒的距離
@export_range(0, 1, 0.01) var lead: float = 0.15
## 抬腳高度：腳在空中時，腳掌畫大多少、影子多明顯
@export_range(0, 20, 0.5) var lift_height: float = 4.0
## 分組：A、B 兩組輪流抬腳。「兩邊」時右邊自動用另一組
@export_enum("A", "B") var group: int = IKLeg.Group.A

@export_group("外觀")
## 腳的粗細（像素）
@export_range(1, 20, 0.5) var leg_width: float = 4.0
## 腳的顏色
@export var leg_color: Color = Color("#c9b59c")
