@tool
class_name OrnamentDesign
extends PartDesign
## 設計檔裡的「一個掛件」（對應 Ornament 節點，欄位名稱一樣）。
## 可以用內建形狀，也可以放一張自己畫的圖（PNG 放在設計檔旁邊，這裡只寫檔名）。

@export_group("掛載位置")
## 掛在身體的第幾節：0 是頭，-1 是最後一節
@export_range(-1, 80, 1) var attach_segment: int = 0
## 掛在哪一邊：兩邊會畫左右一對（右邊是左邊翻過來的）
@export_enum("左", "右", "兩邊", "中間") var side: int = CreaturePart.Side.CENTER
## 位置偏移（像素）：x 是往前、y 是往外
@export var offset: Vector2 = Vector2.ZERO
## 角度：0 是朝前、90 是朝外、180 是朝後
@export_range(-180, 180, 1, "radians_as_degrees") var angle: float = 0.0

@export_group("形狀")
## 內建形狀。選「無」就只顯示自己的圖
@export_enum("無", "圓", "橢圓", "三角形", "角", "翅膀", "魚鰭", "葉子", "星星", "愛心") var shape: int = Ornament.Shape.HORN
## 大小：1 是原本的大小，自己的圖也會一起縮放
@export_range(0.1, 5, 0.05) var size: float = 1.0

@export_group("外觀")
## 顏色：形狀從根部（左）到尖端（右）的漸層。只放一個顏色就是單色
@export var color_gradient: Gradient = Ornament._make_default_gradient()
## 外框：顏色和粗細跟身體一樣
@export var outline: bool = true
## 畫在身體上面：開＝畫在身體上面（角、帽子），關＝畫在身體下面（翅膀）
@export var on_top: bool = true

@export_group("動作")
## 動法：固定、拍動、彈簧
@export_enum("固定", "拍動", "彈簧") var motion: int = Ornament.Motion.FIXED
## 拍動幅度：來回擺幾度
@export_range(0, 90, 1, "radians_as_degrees") var flap_amplitude: float = deg_to_rad(30.0)
## 拍動速度
@export_range(0, 20, 0.1) var flap_speed: float = 4.0
## 彈簧硬度：越大跟得越緊，越小越軟、晃得越久
@export_range(1, 30, 0.5) var spring_stiffness: float = 8.0

@export_group("自己的圖")
## 圖的檔名（PNG，放在設計檔同一個資料夾），空的就沒有圖
@export var image_file: String = ""
## 圖的大小（再乘上面的「大小」）
@export_range(0.05, 5, 0.01) var image_scale: float = 1.0
## 圖的旋轉角度
@export_range(-180, 180, 1, "radians_as_degrees") var image_rotation: float = 0.0


func design_only_fields() -> PackedStringArray:
	return PackedStringArray(["image_file", "image_scale", "image_rotation"])


## 讀資料時，圖的檔名只留「檔名」本身、而且要是 .png，不能指到別的資料夾
func from_dict(data: Dictionary) -> void:
	super(data)
	image_file = safe_image_file(image_file)


## 檔名檢查：去掉資料夾的部分，不是 .png 或有奇怪字元就當作沒有圖
static func safe_image_file(file: String) -> String:
	var file_name: String = file.get_file()
	if file_name.get_extension().to_lower() != "png" or not file_name.is_valid_filename():
		return ""
	return file_name
