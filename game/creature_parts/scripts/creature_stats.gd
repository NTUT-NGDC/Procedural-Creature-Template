@tool
class_name CreatureStats
extends RefCounted
## 能力：從生物「現在的形狀」算出來，不存死的數字。外觀和能力綁在一起：
##   腳多跑得快、身體長難轉彎、觸手長抓得遠、眼睛多看得遠；越大越慢。掛件、裝飾不算能力。
## 所有係數在平衡資料（CreatureBalance）裡。

## 體型（身體的面積）
var size: float = 0.0
## 推進力
var thrust: float = 0.0
## 速度（像素／秒）
var speed: float = 0.0
## 轉向（弧度／秒）
var turn: float = 0.0
## 抓取範圍（像素）：會抓食物的觸手裡最長的那條
var grab: float = 0.0
## 沒有會抓食物的觸手時，「抓取」不顯示星星、改寫這個：最長那條觸手在做什麼（例如「指向滑鼠」），沒有觸手是「沒有觸手」
var grab_trait: String = ""
## 視野（像素）
var sight: float = 0.0
## 升一級要吃幾個（已經乘上成長曲線）
var level_cost: int = 1
## 還沒乘成長曲線的升級成本（0 級時升一級要吃幾個，不四捨五入）。算「總共吃了多少」用
var base_cost: float = 1.0
## 會抓食物的觸手有幾條（「兩邊」算 2 條）
var grab_count: int = 0
## 複雜度（零件越多越高，上限在平衡資料的 max_complexity）
var complexity: int = 0
## 四種能力各 0～1（除以上限），顯示星星、算成本用
var ratios: Dictionary = {}


## 設計檔長到 level 級時的能力（遊戲、工坊、NPC 都用這個）。
## 速度會隨體型變慢，但最多慢到 0 級速度的 min_speed_ratio 倍（不然長大反而越來越難玩）
static func at_level(design: CreatureDesign, level: int, balance: CreatureBalance, shape: CreatureDesign = null) -> CreatureStats:
	var stats: CreatureStats = compute(shape if shape != null else CreatureGrowth.shape_at(design, level, balance), balance)
	if level > 0:
		var start: CreatureStats = compute(CreatureGrowth.shape_at(design, 0, balance), balance)
		stats.speed = maxf(stats.speed, start.speed * balance.min_speed_ratio)
	stats.level_cost = cost_at(stats.base_cost, level, balance)
	return stats


## 成長曲線：等級 level 時升一級要吃幾個＝基本成本 ×（1＋等級 × cost_per_level），等級越高越慢
static func cost_at(base: float, level: int, balance: CreatureBalance) -> int:
	return maxi(roundi(base * (1.0 + maxi(level, 0) * balance.cost_per_level)), 1)


## 從 0 級升到 level 級，總共吃了幾個（每一級的基本成本當作一樣，用現在的 base_cost 算）。死掉掉多少飼料用
static func food_to_reach(base: float, level: int, balance: CreatureBalance) -> int:
	var total: int = 0
	for i: int in maxi(level, 0):
		total += cost_at(base, i, balance)
	return total


## 算出某個形狀的能力（shape 通常是 CreatureGrowth.shape_at() 的結果）
static func compute(shape: CreatureDesign, balance: CreatureBalance) -> CreatureStats:
	var stats := CreatureStats.new()
	var body: BodyDesign = shape.body
	stats.size = CreatureGrowth.body_size(body)
	# 速度：推進力（腳、游動）÷ 體型，越大越慢
	var swim: float = minf(body.swim_amplitude * balance.thrust_per_swim, balance.max_swim_thrust)  # 游動有上限：擺幅不算複雜度
	stats.thrust = balance.base_thrust + count_feet(shape) * balance.thrust_per_foot + swim
	stats.speed = clampf(balance.speed_factor * pow(stats.thrust / stats.size, balance.speed_power), balance.min_speed, balance.max_speed)
	# 轉向：身體越長越難轉；觸手拖在後面，最長那條算一部分（turn_tentacle_ratio）
	var longest_tentacle: float = 0.0
	for tentacle: TentacleDesign in shape.tentacles:
		longest_tentacle = maxf(longest_tentacle, tentacle.length)
	var length: float = (body.segment_count - 1) * body.spacing + longest_tentacle * balance.turn_tentacle_ratio
	stats.turn = clampf(balance.base_turn / (1.0 + length * balance.turn_per_length), balance.min_turn, balance.max_turn)
	# 抓取：會抓食物的觸手裡最長的那條（往後拖、指向滑鼠的觸手不會撿飼料，不算）
	var longest: TentacleDesign = null
	for tentacle: TentacleDesign in shape.tentacles:
		if tentacle.behavior == Tentacle.Behavior.GRAB_FOOD:
			stats.grab = maxf(stats.grab, tentacle.length)
			stats.grab_count += _copies(tentacle.side)
		if longest == null or tentacle.length > longest.length:
			longest = tentacle
	stats.grab = minf(stats.grab, balance.max_grab)
	if stats.grab <= 0.0:
		stats.grab_trait = "沒有觸手" if longest == null else Tentacle.BEHAVIOR_NAMES[clampi(longest.behavior, 0, Tentacle.BEHAVIOR_NAMES.size() - 1)]
	# 視野：眼睛越多、越大，看得越遠
	var eye_power: float = 0.0
	for eyes: EyesDesign in shape.eyes:
		eye_power += eyes.count * eyes.size
	stats.sight = minf(balance.base_sight + eye_power * balance.sight_per_eye, balance.max_sight)
	# 成本：能力越強（四種加起來），升一級要吃越多
	stats.ratios = {
		"speed": stats.speed / balance.max_speed,
		"turn": stats.turn / balance.max_turn,
		"grab": stats.grab / maxf(balance.max_grab, 1.0),  # 星星最多滿格；算成本時再乘上觸手條數（下面）
		"sight": stats.sight / maxf(balance.max_sight, 1.0),
	}
	var power: float = 0.0
	for ratio: float in stats.ratios.values():
		power += ratio
	# 會抓食物的觸手越多條，一次抓越多顆：每多一條，抓取多算 grab_per_extra_tentacle 成
	power += stats.ratios.grab * maxi(stats.grab_count - 1, 0) * balance.grab_per_extra_tentacle
	# 複雜度：零件越多越貴（掛件不算，掛件不會讓生物變強）
	stats.complexity = complexity_of(shape, balance)
	var parts: float = float(complexity_of(shape, balance, false)) / maxf(balance.max_complexity, 1.0)
	stats.base_cost = balance.growth_cost(shape.growth_mode) * (1.0 + power * balance.cost_per_power) * (1.0 + parts * balance.cost_per_complexity)
	stats.level_cost = cost_at(stats.base_cost, 0, balance)  # 還沒算成長曲線；at_level() 會照等級再算一次
	return stats


## 複雜度：每種零件的數量 × 平衡資料裡的點數，加起來。「兩邊」的零件算 2 個。
## with_ornaments 是要不要算掛件（上限要算、升級成本不算）
static func complexity_of(shape: CreatureDesign, balance: CreatureBalance, with_ornaments: bool = true) -> int:
	var points: int = shape.body.segment_count * balance.points_per_body_segment
	points += count_feet(shape) * balance.points_per_foot
	for tentacle: TentacleDesign in shape.tentacles:
		points += tentacle.segment_count * _copies(tentacle.side) * balance.points_per_tentacle_segment
		if tentacle.behavior == Tentacle.Behavior.GRAB_FOOD:  # 會抓食物的觸手：抓取角度越大越貴（90 度是 points_per_grab_angle 點）
			points += roundi(tentacle.grab_angle / (PI / 2.0) * balance.points_per_grab_angle * _copies(tentacle.side))
	for eyes: EyesDesign in shape.eyes:
		points += eyes.count * balance.points_per_eye
	if with_ornaments:
		for ornament: OrnamentDesign in shape.ornaments:
			points += _copies(ornament.side) * balance.points_per_ornament
	return points


## 「兩邊」是左右各一個，算 2 個
static func _copies(side: int) -> int:
	return 2 if side == CreaturePart.Side.BOTH else 1


## 腳的數量：「兩邊」的一組算 2 隻
static func count_feet(shape: CreatureDesign) -> int:
	var feet: int = 0
	for leg: LegDesign in shape.legs:
		feet += _copies(leg.side)
	return feet


## 顯示在畫面上的能力：幾顆星（★★★☆☆）。「抓取」沒有會抓食物的觸手時，改寫觸手在做什麼（grab_trait）
func ability_text(ability: String, max_stars: int) -> String:
	if ability == "grab" and grab_trait != "":
		return grab_trait
	var count: int = stars(ability, max_stars)
	return "★".repeat(count) + "☆".repeat(max_stars - count)


## 某種能力（"speed"、"turn"、"grab"、"sight"）幾顆星：1～max_stars，沒有這種能力是 0
func stars(ability: String, max_stars: int) -> int:
	var ratio: float = ratios.get(ability, 0.0)
	if ratio <= 0.0:
		return 0
	return clampi(ceili(ratio * max_stars), 1, max_stars)
