class_name BalanceCheck
extends RefCounted
## 平衡檢查：「合法但對別人不公平」的組合。單人不限制，想怎麼調都可以；
## 多人對戰時，主機把設計檔自動調到這些規則裡面，再告訴學員調了什麼。
## 工坊的「平衡檢查」按鈕、對戰大廳、主機都用這一份。規則的數字在平衡資料的「平衡檢查（多人）」。
##
## 公式本身的上限（身體長度、觸手抓取範圍、游動推進力）寫在能力計算和長大方式裡，單人也有效，不在這裡。


## 檢查：回傳多人時會調整的地方（一項一句話，空的就是沒問題）。不會改到 design
static func check(design: CreatureDesign, balance: CreatureBalance) -> PackedStringArray:
	if design == null:
		return PackedStringArray()
	return fix(CreatureDesign.from_data(design.to_dict()), balance)


## 調整：直接改 design，回傳調了哪些（跟 check() 一樣的句子）
static func fix(design: CreatureDesign, balance: CreatureBalance) -> PackedStringArray:
	var changes := PackedStringArray()
	if design == null or design.body == null:
		return changes
	_fix_spacing(design.body, balance, changes)
	_fix_body_alpha(design.body, balance, changes)
	_fix_grab_tentacles(design, balance, changes)
	return changes


## 間距太大：節跟節中間有洞，別人的頭穿得過去。間距最多是粗細的 max_spacing_ratio 倍。
## 調的時候間距變小、身體變粗，「間距 × 粗細」（差不多是體型）不變，長得還是像原本那樣細細長長
static func _fix_spacing(body: BodyDesign, balance: CreatureBalance, changes: PackedStringArray) -> void:
	var ratio: float = balance.max_spacing_ratio
	if body.spacing <= body.thickness * ratio + 0.01:
		return
	var old: String = "間距 %d、粗細 %d" % [roundi(body.spacing), roundi(body.thickness)]
	var thickness: float = sqrt(body.spacing * body.thickness / ratio)  # 間距 ＝ 粗細 × ratio，兩個相乘不變
	body.spacing = maxf(floorf(thickness * ratio), 4.0)  # 間距最小 4
	body.thickness = minf(maxf(ceilf(body.spacing / ratio), body.thickness), 80.0)  # 進位，保證調完一定合格（粗細最多 80）
	body.spacing = minf(body.spacing, floorf(body.thickness * ratio))
	changes.append("身體%s → 間距 %d、粗細 %d：節跟節離太遠，中間的洞會讓別人的頭穿過去（間距最多是粗細的 %.1f 倍）" % [
		old, roundi(body.spacing), roundi(body.thickness), balance.max_spacing_ratio])


## 身體太透明：看不到的牆。顏色的不透明度至少 min_body_alpha；不畫身體又沒有每一節的圖，改成畫身體
static func _fix_body_alpha(body: BodyDesign, balance: CreatureBalance, changes: PackedStringArray) -> void:
	if not body.draw_body and body.segment_image == "":
		body.draw_body = true
		changes.append("「也畫身體」打開：沒有每一節的圖又不畫身體，別人看不到你的身體就會撞上去")
	if body.body_gradient == null:
		return
	var colors: PackedColorArray = body.body_gradient.colors
	var lowest: float = 1.0
	for i: int in colors.size():
		lowest = minf(lowest, colors[i].a)
		colors[i].a = maxf(colors[i].a, balance.min_body_alpha)
	if lowest >= balance.min_body_alpha - 0.001:
		return
	body.body_gradient = body.body_gradient.duplicate() as Gradient  # 複製一份再改，不動到別人共用的漸層
	body.body_gradient.colors = colors
	changes.append("身體的不透明度 %d%% → %d%%：太透明的身體是看不到的牆" % [roundi(lowest * 100.0), roundi(balance.min_body_alpha * 100.0)])


## 會抓食物的觸手太多：一次掃光一大片。最多 max_grab_tentacles 條（「兩邊」算 2 條），從最短的開始改成「波浪擺動」
static func _fix_grab_tentacles(design: CreatureDesign, balance: CreatureBalance, changes: PackedStringArray) -> void:
	var grabbing: Array[TentacleDesign] = []
	var count: int = 0
	for tentacle: TentacleDesign in design.tentacles:
		if tentacle.behavior == Tentacle.Behavior.GRAB_FOOD:
			grabbing.append(tentacle)
			count += _copies(tentacle.side)
	if count <= balance.max_grab_tentacles:
		return
	grabbing.sort_custom(func(a: TentacleDesign, b: TentacleDesign) -> bool: return a.length < b.length)
	var changed: int = 0
	for tentacle: TentacleDesign in grabbing:
		if count <= balance.max_grab_tentacles:
			break
		tentacle.behavior = Tentacle.Behavior.WAVE
		count -= _copies(tentacle.side)
		changed += 1
	changes.append("%d 組觸手從「抓最近的食物」改成「波浪擺動」：會抓食物的觸手最多 %d 條（「兩邊」算 2 條），太多會一下子掃光一大片" % [
		changed, balance.max_grab_tentacles])


## 「兩邊」是左右各一條，算 2 條
static func _copies(side: int) -> int:
	return 2 if side == CreaturePart.Side.BOTH else 1
