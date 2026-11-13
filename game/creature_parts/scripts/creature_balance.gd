@tool
class_name CreatureBalance
extends Resource
## 平衡資料：體型、能力、升級成本的所有係數。社長在檢查器調，不用改程式。
## 預設的檔案是 game/creature_parts/data/balance.tres。
##
## 公式（寫在 creature_stats.gd 和 creature_growth.gd）：
##   體型＝身體的面積（每節的寬度 × 2 × 間距，全部加起來）
##   推進力＝基本推進力＋腳的數量 × 每隻腳的推進力＋游動擺幅 × 游動推進力
##   速度＝速度係數 ×（推進力 ÷ 體型）的「體型影響」次方（夾在上下限）
##   轉向＝基本轉向 ÷（1＋身體長度 × 長度對轉向的影響）（夾在上下限）
##   抓取範圍＝最長的觸手（有上限）
##   視野＝基本視野＋眼睛數量 × 眼睛大小 × 每顆眼睛的視野（有上限）
##   升一級要吃幾個＝長大方式的成本 ×（1＋能力總和 × 能力對成本的影響）

## 預設的平衡資料
const DEFAULT_PATH: String = "res://game/creature_parts/data/balance.tres"

@export_group("體型")
## 一開始的體型最小多少（太小的生物會整隻放大到這裡）
@export_range(100, 20000, 10) var min_start_size: float = 800.0
## 一開始的體型最大多少（太大的生物會整隻縮小到這裡）
@export_range(100, 20000, 10) var max_start_size: float = 8000.0
## 每升一級，體型增加多少（不管哪種長大方式都一樣）
@export_range(10, 5000, 10) var size_per_level: float = 500.0
## 長大時身體最多幾節，超過就改成整隻等比放大
@export_range(2, 80, 1) var max_grow_segments: int = 80

@export_group("速度")
## 基本推進力：沒有腳、不游動也有的推進力
@export_range(0, 2000, 10) var base_thrust: float = 200.0
## 每隻腳的推進力（「兩邊」的一組腳算 2 隻）
@export_range(0, 1000, 5) var thrust_per_foot: float = 100.0
## 游動推進力：游動擺幅每 1 像素加多少推進力（蛇、魚靠這個）
@export_range(0, 500, 1) var thrust_per_swim: float = 150.0
## 速度係數：速度＝這個數字 ×（推進力 ÷ 體型）的「體型影響」次方
@export_range(0, 2000, 5) var speed_factor: float = 300.0
## 體型影響：1 是「推進力 ÷ 體型」原樣（大小差很多時速度也差很多），越小差距越小
@export_range(0.1, 1.0, 0.05) var speed_power: float = 0.5
## 速度下限、上限（像素／秒）
@export_range(10, 1000, 5) var min_speed: float = 60.0
@export_range(10, 1000, 5) var max_speed: float = 360.0

@export_group("轉向")
## 基本轉向（度／秒）：身體長度是 0 時的轉向速度
@export_range(30, 1080, 10, "radians_as_degrees") var base_turn: float = deg_to_rad(450.0)
## 長度對轉向的影響：身體每長 1 像素，轉向變慢多少
@export_range(0, 0.05, 0.0005) var turn_per_length: float = 0.004
## 轉向下限、上限（度／秒）
@export_range(10, 1080, 10, "radians_as_degrees") var min_turn: float = deg_to_rad(90.0)
@export_range(10, 1080, 10, "radians_as_degrees") var max_turn: float = deg_to_rad(450.0)

@export_group("抓取與視野")
## 抓取範圍上限（像素）：觸手再長也只算到這裡
@export_range(0, 1000, 5) var max_grab: float = 250.0
## 基本視野（像素）：沒有眼睛也看得到這麼遠
@export_range(0, 2000, 10) var base_sight: float = 200.0
## 每顆眼睛的視野：眼睛數量 × 眼睛大小 × 這個數字
@export_range(0, 2000, 10) var sight_per_eye: float = 150.0
## 視野上限（像素）
@export_range(0, 3000, 10) var max_sight: float = 600.0

@export_group("升級成本")
## 三種長大方式升一級的基本成本（要吃幾個）
@export_range(1, 50, 1) var cost_scale: int = 3
@export_range(1, 50, 1) var cost_longer_with_legs: int = 4
@export_range(1, 50, 1) var cost_longer: int = 2
## 能力對成本的影響：四種能力（各 0～1）加起來 × 這個數字，再乘在基本成本上
@export_range(0, 5, 0.05) var cost_per_power: float = 0.5

@export_group("星星")
## 能力顯示成幾顆星（1～這個數字）
@export_range(3, 10, 1) var max_stars: int = 5


## 預設的平衡資料（讀不到就用程式裡的預設值）
static func get_default() -> CreatureBalance:
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded: CreatureBalance = load(DEFAULT_PATH) as CreatureBalance
		if loaded != null:
			return loaded
	return CreatureBalance.new()


## 某種長大方式升一級的基本成本
func growth_cost(mode: int) -> int:
	match mode:
		CreatureDesign.Growth.LONGER_WITH_LEGS:
			return cost_longer_with_legs
		CreatureDesign.Growth.LONGER:
			return cost_longer
	return cost_scale
