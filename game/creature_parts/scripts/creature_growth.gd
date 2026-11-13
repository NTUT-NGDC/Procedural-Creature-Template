@tool
class_name CreatureGrowth
extends RefCounted
## 長大方式：算出「設計檔＋等級」時生物長什麼樣子（回傳一份新的設計檔，不會改到原本的）。
##
## 體型＝身體的面積。每升一級體型增加一樣多（平衡資料的 size_per_level），差別在長在哪裡：
##   ① 等比放大：整隻放大
##   ② 變長＋長出腳：加節數，每隔幾節長一對腳
##   ③ 只變長：加節數，腳不變
## 一開始的體型會先夾在平衡資料的上下限之間（太大、太小的整隻縮放）。
## ②③ 長到複雜度上限（零件太多）就不再加節、加腳，剩下的改成整隻放大。
## Creature 升級時、工坊的「升 5 級預覽」、NPC 都用這個。


## 體型：身體的面積＝每一節的寬度 × 2 × 間距，全部加起來
static func body_size(body: BodyDesign) -> float:
	var total: float = 0.0
	for i: int in body.segment_count:
		var t: float = float(i) / maxf(body.segment_count - 1, 1)  # 這一節在身體上的位置，頭 0、尾 1
		var width: float = body.thickness * (body.width_curve.sample(t) if body.width_curve != null else 1.0)
		total += width * 2.0 * body.spacing
	return total


## 某個等級時的樣子（level 小於 0 當作 0）
static func shape_at(design: CreatureDesign, level: int, balance: CreatureBalance) -> CreatureDesign:
	var shape: CreatureDesign = CreatureDesign.from_data(design.to_dict())  # 複製一份，不改原本的
	shape.image_folder = design.image_folder if design.image_folder != "" else design.resource_path.get_base_dir()
	var size: float = body_size(shape.body)
	var start: float = clampf(size, balance.min_start_size, balance.max_start_size)
	scale_all(shape, sqrt(start / size))  # 一開始的體型夾在上下限之間
	var target: float = start + balance.size_per_level * maxi(level, 0)
	if shape.growth_mode == CreatureDesign.Growth.SCALE:
		scale_all(shape, sqrt(target / start))  # 面積跟長度的平方成正比，所以開根號
	else:
		grow_longer(shape, target, balance.max_grow_segments)
		if shape.growth_mode == CreatureDesign.Growth.LONGER_WITH_LEGS:
			add_legs(shape, design.body.segment_count)
		fit_complexity(shape, design, balance)
		reach_size(shape, target)
	return shape


## ① 等比放大：每個零件的長度類欄位都乘上 factor
static func scale_all(shape: CreatureDesign, factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		return
	shape.body.scale_lengths(factor)
	for part: PartDesign in shape.all_parts():
		part.scale_lengths(factor)


## ②③ 變長：加節數加到體型差不多（節數有上限 max_segments）
static func grow_longer(shape: CreatureDesign, target: float, max_segments: int) -> void:
	var body: BodyDesign = shape.body
	var per_segment: float = body_size(body) / body.segment_count  # 平均一節多大
	body.segment_count = clampi(roundi(target / per_segment), body.segment_count, maxi(max_segments, body.segment_count))


## 超過複雜度上限：一節一節少長回來（② 長出來的腳跟著重排），直到不超過上限。
## 原本的設計檔就超過上限的（舊的設計檔），至少長大時不再變多
static func fit_complexity(shape: CreatureDesign, design: CreatureDesign, balance: CreatureBalance) -> void:
	var limit: int = maxi(balance.max_complexity, CreatureStats.complexity_of(design, balance))
	while CreatureStats.complexity_of(shape, balance) > limit and shape.body.segment_count > design.body.segment_count:
		shape.body.segment_count -= 1
		if shape.growth_mode == CreatureDesign.Growth.LONGER_WITH_LEGS:
			shape.legs.resize(design.legs.size())  # 長出來的腳拿掉，照新的長度重新長
			add_legs(shape, design.body.segment_count)


## 體型補到 target：差很多（節數、複雜度到上限）就整隻等比放大，只差一點點就微調粗細（面積跟粗細成正比）
static func reach_size(shape: CreatureDesign, target: float) -> void:
	var size: float = body_size(shape.body)
	if size < target * 0.9:
		scale_all(shape, sqrt(target / size))
	else:
		shape.body.thickness *= target / size


## ② 長出腳：從最後一組腳開始，往尾巴每隔 legs_every 節複製一組，A、B 組輪流。
## 最後一組腳到尾巴的距離維持跟原本一樣（還沒長大時不會多出腳）
static func add_legs(shape: CreatureDesign, original_segments: int) -> void:
	if shape.legs.is_empty():
		return  # 沒有腳的生物沒有腳可以複製，只會變長
	var template: LegDesign = shape.legs[0]  # 最靠尾巴的那組腳
	for leg: LegDesign in shape.legs:
		if _leg_segment(leg, original_segments) > _leg_segment(template, original_segments):
			template = leg
	var last: int = _leg_segment(template, original_segments)
	var tail_gap: int = original_segments - 1 - last  # 原本最後一組腳離尾巴幾節
	var group: int = template.group
	var segment: int = last + shape.legs_every
	while segment <= shape.body.segment_count - 1 - tail_gap and shape.legs.size() < CreatureDesign.MAX_LEGS:
		var leg: LegDesign = template.duplicate() as LegDesign
		group = 1 - group
		leg.attach_segment = segment
		leg.group = group
		shape.legs.append(leg)
		segment += shape.legs_every


## 腳掛在第幾節（-1 換成最後一節，超出範圍也當最後一節）
static func _leg_segment(leg: LegDesign, segments: int) -> int:
	return leg.attach_segment if leg.attach_segment >= 0 and leg.attach_segment < segments else segments - 1
