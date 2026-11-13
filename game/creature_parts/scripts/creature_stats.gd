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
## 抓取範圍（像素）：最長的觸手
var grab: float = 0.0
## 視野（像素）
var sight: float = 0.0
## 升一級要吃幾個
var level_cost: int = 1
## 四種能力各 0～1（除以上限），顯示星星、算成本用
var ratios: Dictionary = {}


## 算出某個形狀的能力（shape 通常是 CreatureGrowth.shape_at() 的結果）
static func compute(shape: CreatureDesign, balance: CreatureBalance) -> CreatureStats:
	var stats := CreatureStats.new()
	var body: BodyDesign = shape.body
	stats.size = CreatureGrowth.body_size(body)
	# 速度：推進力（腳、游動）÷ 體型，越大越慢
	stats.thrust = balance.base_thrust + count_feet(shape) * balance.thrust_per_foot + body.swim_amplitude * balance.thrust_per_swim
	stats.speed = clampf(balance.speed_factor * pow(stats.thrust / stats.size, balance.speed_power), balance.min_speed, balance.max_speed)
	# 轉向：身體越長越難轉
	var length: float = (body.segment_count - 1) * body.spacing
	stats.turn = clampf(balance.base_turn / (1.0 + length * balance.turn_per_length), balance.min_turn, balance.max_turn)
	# 抓取：最長的觸手
	for tentacle: TentacleDesign in shape.tentacles:
		stats.grab = maxf(stats.grab, tentacle.length)
	stats.grab = minf(stats.grab, balance.max_grab)
	# 視野：眼睛越多、越大，看得越遠
	var eye_power: float = 0.0
	for eyes: EyesDesign in shape.eyes:
		eye_power += eyes.count * eyes.size
	stats.sight = minf(balance.base_sight + eye_power * balance.sight_per_eye, balance.max_sight)
	# 成本：能力越強（四種加起來），升一級要吃越多
	stats.ratios = {
		"speed": stats.speed / balance.max_speed,
		"turn": stats.turn / balance.max_turn,
		"grab": stats.grab / maxf(balance.max_grab, 1.0),
		"sight": stats.sight / maxf(balance.max_sight, 1.0),
	}
	var power: float = 0.0
	for ratio: float in stats.ratios.values():
		power += ratio
	stats.level_cost = maxi(roundi(balance.growth_cost(shape.growth_mode) * (1.0 + power * balance.cost_per_power)), 1)
	return stats


## 腳的數量：「兩邊」的一組算 2 隻
static func count_feet(shape: CreatureDesign) -> int:
	var feet: int = 0
	for leg: LegDesign in shape.legs:
		feet += 2 if leg.side == CreaturePart.Side.BOTH else 1
	return feet


## 某種能力（"speed"、"turn"、"grab"、"sight"）幾顆星：1～max_stars，沒有這種能力是 0
func stars(ability: String, max_stars: int) -> int:
	var ratio: float = ratios.get(ability, 0.0)
	if ratio <= 0.0:
		return 0
	return clampi(ceili(ratio * max_stars), 1, max_stars)
