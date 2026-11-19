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
## 身體長度也有上限（一開始 max_start_length，長大慢慢放寬到 max_body_length）：太長的縮短間距、加粗，體型不變。
## 觸手也有長度上限（一開始 max_start_tentacle，長大最長 max_tentacle_length）。
## 身體一定要看得到（make_visible()）：太透明、不畫身體又沒有圖、太細的，先調好再長大。
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
	shape.image_cache = design.image_cache  # 連線收到的圖（同一份，不複製）
	make_visible(shape, balance)  # 太透明、不畫身體、太細的先調成看得到
	var size: float = body_size(shape.body)
	var start: float = clampf(size, balance.min_start_size, balance.max_start_size)
	scale_all(shape, sqrt(start / size))  # 一開始的體型夾在上下限之間
	var target: float = start + balance.size_per_level * maxi(level, 0)
	if shape.growth_mode == CreatureDesign.Growth.SCALE:
		scale_all(shape, sqrt(target / start))  # 面積跟長度的平方成正比，所以開根號
	else:
		var thicken: float = pow(target / start, shape.thicken_ratio)  # 變粗的那幾成：體型跟粗細成正比，粗細乘 (target ÷ start) 的 thicken_ratio 次方
		shape.body.thickness *= thicken
		scale_parts(shape, thicken)  # 零件（掛件、觸手、腳）跟著身體變粗的比例一起變大
		grow_longer(shape, target, balance.max_grow_segments)  # 剩下的加節數補上
		if shape.growth_mode == CreatureDesign.Growth.LONGER_WITH_LEGS:
			add_legs(shape, design.body.segment_count)
		fit_complexity(shape, design, balance)
		reach_size(shape, target)
	fit_length(shape, length_limit(start, target, balance))
	fit_tentacles(shape, tentacle_limit(start, target, balance))
	return shape


## 看得到的身體：撞到別人的身體會死，別人看不到你的身體就會撞上去（看不到的牆）。直接改 shape，
## 回傳調了哪些（一項一句話；工坊顯示用）。單人、多人都一樣
static func make_visible(shape: CreatureDesign, balance: CreatureBalance) -> PackedStringArray:
	var notes := PackedStringArray()
	var body: BodyDesign = shape.body
	if body == null:
		return notes
	# 不畫身體又沒有每一節的圖：只剩頭，身體看不到
	if not body.draw_body and body.segment_image == "":
		body.draw_body = true
		notes.append("沒有每一節的圖，所以還是會畫身體")
	# 太透明：每個顏色的不透明度至少 min_body_alpha
	if body.body_gradient != null:
		var colors: PackedColorArray = body.body_gradient.colors
		var lowest: float = 1.0
		for i: int in colors.size():
			lowest = minf(lowest, colors[i].a)
			colors[i].a = maxf(colors[i].a, balance.min_body_alpha)
		if lowest < balance.min_body_alpha - 0.001:
			body.body_gradient = body.body_gradient.duplicate() as Gradient  # 複製一份再改，不動到設計檔的漸層
			body.body_gradient.colors = colors
			notes.append("身體太透明：不透明度 %d%% → %d%%" % [roundi(lowest * 100.0), roundi(balance.min_body_alpha * 100.0)])
	# 太細：平均寬度至少 min_body_width，加粗、間距縮短同樣的倍數（體型不變）
	var width: float = body_size(body) / maxf(2.0 * body.spacing * body.segment_count, 0.001)
	if width < balance.min_body_width and width > 0.0:
		var factor: float = balance.min_body_width / width
		body.thickness *= factor
		body.spacing /= factor
		notes.append("身體太細：平均寬 %.1f → %.1f（間距跟著變短，體型不變）" % [width, balance.min_body_width])
	return notes


## 設計檔在遊戲裡會被調成看得到的哪些地方（不會改到 design）。工坊顯示用
static func visibility_notes(design: CreatureDesign, balance: CreatureBalance) -> PackedStringArray:
	if design == null:
		return PackedStringArray()
	return make_visible(CreatureDesign.from_data(design.to_dict()), balance)


## 觸手長度上限：一開始 max_start_tentacle，跟著體型慢慢放寬（像整隻放大一樣），最長到 max_tentacle_length
static func tentacle_limit(start: float, target: float, balance: CreatureBalance) -> float:
	return minf(balance.max_start_tentacle * sqrt(target / maxf(start, 1.0)), maxf(balance.max_tentacle_length, balance.max_start_tentacle))


## 觸手太長：剪到上限（粗細不變）
static func fit_tentacles(shape: CreatureDesign, max_length: float) -> void:
	for tentacle: TentacleDesign in shape.tentacles:
		tentacle.length = minf(tentacle.length, max_length)


## 身體長度上限：一開始 max_start_length，跟著體型慢慢放寬（像整隻放大一樣），最長到 max_body_length。
## start 是一開始的體型（夾過上下限）、target 是這一級的體型
static func length_limit(start: float, target: float, balance: CreatureBalance) -> float:
	return minf(balance.max_start_length * sqrt(target / maxf(start, 1.0)), maxf(balance.max_body_length, balance.max_start_length))


## 設計檔長到 level 級時，身體最長多長（工坊顯示用）
static func length_limit_at(design: CreatureDesign, level: int, balance: CreatureBalance) -> float:
	var start: float = clampf(body_size(design.body), balance.min_start_size, balance.max_start_size)
	return length_limit(start, start + balance.size_per_level * maxi(level, 0), balance)


## 身體長度：頭到尾巴多長（像素）
static func body_length(body: BodyDesign) -> float:
	return (body.segment_count - 1) * body.spacing


## 身體太長：間距縮短、身體加粗同樣的倍數，體型（面積）不變。零件不跟著變
static func fit_length(shape: CreatureDesign, max_length: float) -> void:
	var length: float = body_length(shape.body)
	if length <= max_length or length <= 0.0:
		return
	var factor: float = max_length / length
	shape.body.spacing *= factor
	shape.body.thickness /= factor


## ① 等比放大：身體和每個零件的長度類欄位都乘上 factor
static func scale_all(shape: CreatureDesign, factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		return
	shape.body.scale_lengths(factor)
	scale_parts(shape, factor)


## 零件（掛件、觸手、腳、眼睛）的長度類欄位都乘上 factor（身體不動）
static func scale_parts(shape: CreatureDesign, factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		return
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
		scale_parts(shape, target / size)  # 零件跟著身體粗細一起微調


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
