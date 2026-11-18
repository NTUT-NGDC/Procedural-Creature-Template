@tool
class_name EyesDesign
extends PartDesign
## 設計檔裡的「一排眼睛」（對應 Eyes 節點，欄位名稱一樣）。

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭
@export_range(-1, 80, 1) var attach_segment: int = 0

@export_group("形狀")
## 眼睛數量：平均排在那一節上
@export_range(1, 6, 1) var count: int = 2
## 大小：眼白半徑是那一節粗細的幾倍
@export_range(0.05, 1.0, 0.01) var size: float = 0.3
## 間距：最外側的眼睛離中線多遠，是那一節粗細的幾倍
@export_range(0.0, 1.5, 0.01) var spread: float = 0.6

@export_group("外觀")
## 顯示：關掉就不畫出來，視野照算。頭用了自己畫的圖、圖上已經有眼睛的話，關掉才不會擋到圖。
## （欄位名跟節點的 visible 一樣，套用設計時會直接設到眼睛節點上）
@export var visible: bool = true
## 眼白顏色
@export var white_color: Color = Color.WHITE
## 瞳孔顏色
@export var pupil_color: Color = Color("#111111")

@export_group("動作")
## 看哪裡：前方、滑鼠、最近的食物、最近的天敵
@export_enum("前方", "滑鼠", "最近的食物", "最近的天敵") var look_target: int = Eyes.LookAt.FORWARD
## 眨眼
@export var blink: bool = true
