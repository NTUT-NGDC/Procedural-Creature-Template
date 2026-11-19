@tool
class_name CreatureBalance
extends Resource
## 平衡資料：體型、能力、升級成本的所有係數。社長在檢查器調，不用改程式。
## 預設的檔案是 game/creature_parts/data/balance.tres。
##
## 公式（寫在 creature_stats.gd 和 creature_growth.gd）：
##   體型＝身體的面積（每節的寬度 × 2 × 間距，全部加起來）。身體長度有上限，太長的縮短間距、加粗
##   推進力＝基本推進力＋腳的數量 × 每隻腳的推進力＋游動擺幅 × 游動推進力（游動的有上限）
##   速度＝速度係數 ×（推進力 ÷ 體型）的「體型影響」次方（夾在上下限）
##   轉向＝基本轉向 ÷（1＋身體長度 × 長度對轉向的影響）（夾在上下限）
##   抓取範圍＝會抓食物的觸手裡最長的那條（有上限，觸手實際也只抓得到這麼遠）；觸手越多條，能力分數越高
##   視野＝基本視野＋眼睛數量 × 眼睛大小 × 每顆眼睛的視野（有上限）。玩家的視野越大，生態缸的鏡頭拉得越遠
##   升一級要吃幾個＝長大方式的成本 ×（1＋能力總和 × 能力對成本的影響）×（1＋能力零件的複雜度 ÷ 上限 × 複雜度對成本的影響）
##     ×（1＋等級 × 成長曲線）：等級越高升級越慢
##   複雜度＝身體節數 × 點數＋腳的數量 × 點數＋觸手節數 × 點數＋眼睛數量 × 點數＋掛件數量 × 點數
##     （零件越多，每台電腦畫起來越重。工坊超過上限就不能再加；長大到上限就改成整隻放大；
##       生態缸、對戰不收超過上限的生物。掛件算在上限裡，但不算進升級成本，因為掛件不會讓生物變強）
##
## 生態缸的規則（寫在 game/tank/scripts/tank_rules.gd，像 Slither）：
##   撞：頭撞到別人（頭或身體，不管誰大），撞人的那隻死掉
##   頭碰頭：衝向對方的那隻死；兩隻都朝對方衝超過「正面對撞速度」就兩隻都死
##   死掉的生物掉出「升到這一級總共吃了多少」× 掉幾成，變成大顆飼料

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
## 一開始身體最長多少（像素，頭到尾）：太長的會縮短間距、加粗（體型不變）。畫面寬 1280
@export_range(50, 5000, 10) var max_start_length: float = 600.0
## 長大時身體最長多少（像素）：到了就不再變長，多的體型都拿來變粗
@export_range(50, 5000, 10) var max_body_length: float = 1200.0

@export_group("速度")
## 基本推進力：沒有腳、不游動也有的推進力
@export_range(0, 2000, 10) var base_thrust: float = 200.0
## 每隻腳的推進力（「兩邊」的一組腳算 2 隻）
@export_range(0, 1000, 5) var thrust_per_foot: float = 100.0
## 游動推進力：游動擺幅每 1 像素加多少推進力（蛇、魚靠這個）
@export_range(0, 500, 1) var thrust_per_swim: float = 150.0
## 游動推進力上限：擺幅再大，游動的推進力也只算到這裡（擺幅不算複雜度，不設上限的話等於免費的速度）
@export_range(0, 10000, 10) var max_swim_thrust: float = 1500.0
## 速度係數：速度＝這個數字 ×（推進力 ÷ 體型）的「體型影響」次方
@export_range(0, 2000, 5) var speed_factor: float = 300.0
## 體型影響：1 是「推進力 ÷ 體型」原樣（大小差很多時速度也差很多），越小差距越小
@export_range(0.1, 1.0, 0.05) var speed_power: float = 0.5
## 速度下限、上限（像素／秒）
@export_range(10, 1000, 5) var min_speed: float = 60.0
@export_range(10, 1000, 5) var max_speed: float = 360.0
## 長大最多慢到 0 級速度的幾倍（1 是長大完全不會變慢）
@export_range(0.1, 1.0, 0.05) var min_speed_ratio: float = 0.8

@export_group("轉向")
## 基本轉向（度／秒）：身體長度是 0 時的轉向速度
@export_range(30, 1080, 10, "radians_as_degrees") var base_turn: float = deg_to_rad(450.0)
## 長度對轉向的影響：身體每長 1 像素，轉向變慢多少（長度＝身體＋最長的觸手 × 觸手算幾成）
@export_range(0, 0.05, 0.0005) var turn_per_length: float = 0.004
## 轉向下限、上限（度／秒）
@export_range(10, 1080, 10, "radians_as_degrees") var min_turn: float = deg_to_rad(60.0)
@export_range(10, 1080, 10, "radians_as_degrees") var max_turn: float = deg_to_rad(280.0)
## 觸手算幾成長度：最長那條觸手 × 這個比例，加進轉向用的長度（觸手越長越難轉）
@export_range(0, 2, 0.05) var turn_tentacle_ratio: float = 0.5

@export_group("抓取與視野")
## 抓取範圍上限（像素）：觸手再長，也只抓得到這麼遠的飼料
@export_range(0, 1000, 5) var max_grab: float = 250.0
## 會抓食物的觸手每多一條（「兩邊」算 2 條），抓取的能力分數多幾成（升級跟著變貴）
@export_range(0, 1, 0.01) var grab_per_extra_tentacle: float = 0.1
## 基本視野（像素）：沒有眼睛也看得到這麼遠
@export_range(0, 2000, 10) var base_sight: float = 200.0
## 每顆眼睛的視野：眼睛數量 × 眼睛大小 × 這個數字
@export_range(0, 2000, 10) var sight_per_eye: float = 150.0
## 視野上限（像素）
@export_range(0, 3000, 10) var max_sight: float = 600.0
## 玩家的視野到上限時，鏡頭拉到幾倍（1 是不拉遠，越小看到的地圖越多）。視野在基本和上限之間照比例
@export_range(0.4, 1.0, 0.05) var max_zoom_out: float = 0.75

@export_group("升級成本")
## 三種長大方式升一級的基本成本（要吃幾個）
@export_range(1, 50, 1) var cost_scale: int = 3
@export_range(1, 50, 1) var cost_longer_with_legs: int = 4
@export_range(1, 50, 1) var cost_longer: int = 2
## 能力對成本的影響：四種能力（各 0～1）加起來 × 這個數字，再乘在基本成本上
@export_range(0, 5, 0.05) var cost_per_power: float = 0.5
## 複雜度對成本的影響：能力零件的複雜度 ÷ 上限 × 這個數字，再乘在基本成本上（零件越多越貴）
@export_range(0, 5, 0.05) var cost_per_complexity: float = 0.5
## 成長曲線：每高一級，升級要吃的多幾成（0.25 是 4 級時要吃 2 倍、8 級 3 倍）。0 是每一級都一樣
@export_range(0, 2, 0.01) var cost_per_level: float = 0.25

@export_group("複雜度")
## 複雜度上限：一隻生物最多幾點。對戰時每台電腦要畫全部的生物，零件太多會拖慢所有人
@export_range(20, 1000, 1) var max_complexity: int = 120
## 身體每一節幾點
@export_range(0, 20, 1) var points_per_body_segment: int = 1
## 每隻腳幾點（「兩邊」的一組算 2 隻）
@export_range(0, 50, 1) var points_per_foot: int = 6
## 觸手每一節幾點（「兩邊」算 2 條）
@export_range(0, 20, 1) var points_per_tentacle_segment: int = 1
## 會抓食物的觸手，抓取角度開到最大（左右各 90 度）每條多幾點；角度小的照比例少（四捨五入）
@export_range(0, 20, 0.5) var points_per_grab_angle: float = 2.0
## 每顆眼睛幾點
@export_range(0, 20, 1) var points_per_eye: int = 1
## 每個掛件幾點（「兩邊」算 2 個）
@export_range(0, 50, 1) var points_per_ornament: int = 2

@export_group("飼料")
## 生態缸裡自己長出飼料的間隔（秒），0 是不會自己長。地圖越大、生物越多，要長得越快
@export_range(0, 30, 0.05) var food_interval: float = 0.2
## 場上最多幾個飼料（生物掉出來的不算在內）
@export_range(0, 300, 1) var max_food: int = 150
## 缸裡自己長的飼料，有多少機率是大顆（0～1）
@export_range(0, 1, 0.01) var big_food_chance: float = 0.15
## 大顆飼料算幾個（小顆算 1 個）。死掉的生物掉出來的都是大顆，加速噴出來的是小顆
@export_range(1, 20, 1) var big_food_value: int = 3

@export_group("碰撞")
## 死掉的生物，掉出「升到這一級總共吃了多少」的幾成（變成大顆飼料）。1 是全部掉出來
@export_range(0, 1, 0.05) var drop_ratio: float = 0.5
## 死掉的生物最少掉幾個大顆飼料（0 級死掉也有）
@export_range(0, 20, 1) var min_drop_food: int = 2
## 一次最多掉幾個飼料（太多網頁版會卡）
@export_range(1, 200, 1) var max_drop_food: int = 30
## 撞人的角度：頭朝的方向左右各幾度以內碰到別人，才算撞人（撞人的死）；頭的側面、後面擦到不算。
## 兩隻都用這個角度碰到對方（正面對撞）就兩隻都死
@export_range(10, 90, 1, "radians_as_degrees") var ram_angle: float = deg_to_rad(45.0)
## 死掉重生之後，幾秒內撞到別人、被別人撞都沒事
@export_range(0, 10, 0.1) var respawn_invincible: float = 2.0

@export_group("加速")
## 加速時速度變成幾倍
@export_range(1.0, 4.0, 0.05) var boost_speed: float = 1.8
## 加速時每秒消耗幾個飼料（消耗的變成小顆飼料掉在身後）。
## 這一級吃到一半的用完了就掉一級、繼續消耗，一直噴到 0 級、一個都不剩才停
@export_range(0.1, 20, 0.1) var boost_cost: float = 2.0

@export_group("平衡檢查（多人）")
## 以下是工坊「平衡檢查」和對戰主機用的規則：單人不限制，多人時主機自動調到這裡面
## 間距最多是粗細的幾倍：太稀的話節跟節中間有洞，別人的頭穿得過去
@export_range(0.5, 5, 0.05) var max_spacing_ratio: float = 1.5
## 身體最少多不透明（0～1）：太透明就是看不到的牆
@export_range(0, 1, 0.05) var min_body_alpha: float = 0.6
## 會抓食物的觸手最多幾條（「兩邊」算 2 條），多的改成「波浪擺動」
@export_range(0, 32, 1) var max_grab_tentacles: int = 8

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
