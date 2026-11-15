class_name TutorialChecker
extends RefCounted
## 教學步驟的檢查：看工坊現在的設計檔＋實驗紀錄（TutorialRecord），判斷每一步過了沒。
##
## check() 過了回傳空字串，沒過回傳「還差什麼」（會顯示在步驟卡上）。
## 步驟的順序跟 data/tutorial_steps.tres 一樣：前 REQUIRED_COUNT 步必做，後面是額外題。
## 想調過關門檻：改下面的常數。

const REQUIRED_COUNT: int = 6
const STEP_COUNT: int = 9
## 「存檔」這一步：存完又改了就變回沒過（提醒再存一次）。其他步驟過了就一直算過
const SAVE_STEP: int = 5

## 第 2 步：彎曲角要拉到多大才算「弄壞」、要調回多小才算「修好」
const BREAK_BEND: float = deg_to_rad(150.0)
const FIXED_BEND: float = deg_to_rad(60.0)
## 第 3 步：身體至少要改幾種
const MIN_BODY_CHANGES: int = 2
## 第 3 步：身體的「種類」→ 算在這一種裡的欄位
const BODY_KINDS: Dictionary = {
	"節數": ["segment_count"],
	"間距": ["spacing"],
	"粗細": ["thickness"],
	"粗細形狀": ["width_curve"],
	"顏色": ["body_gradient"],
	"花紋": ["pattern", "pattern_color"],
	"外框": ["outline_color", "outline_width"],
}
## 第 4 步：FABRIK 次數調回幾次以上算修好
const FIXED_ITERATIONS: int = 3
## 第 5 步：落腳距離拉到多少算「打直」、調回多少以下算修好
const STRAIGHT_REST: float = 0.99
const FIXED_REST: float = 0.9
## 第 7 步：預覽等級要拉到幾級
const PREVIEW_LEVEL: int = 5
const DEFAULT_NAME: String = "我的生物"


## 第 index 步過了沒：過了回傳 ""，沒過回傳原因
static func check(index: int, design: CreatureDesign, record: TutorialRecord) -> String:
	if design == null or record == null:
		return "工坊裡還沒有生物"
	match index:
		0: return _check_name(design, record)
		1: return _check_bend(design, record)
		2: return _check_body(design, record)
		3: return _check_tentacle(design, record)
		4: return _check_legs(design, record)
		5: return _check_saved(design, record)
		6: return _check_growth(design, record)
		7: return _check_ornament_motion(design)
		8: return _check_ornament_image(design)
	return "沒有這一步"


## 過了之後還要不要每次重新檢查（只有「存檔」要）
static func is_sticky(index: int) -> bool:
	return index != SAVE_STEP


## 腳用了哪些分組（A、B），例如 [0] 表示全部都是 A
static func leg_groups(design: CreatureDesign) -> Array[int]:
	var groups: Array[int] = []
	for leg: LegDesign in design.legs:
		if not leg.group in groups:
			groups.append(leg.group)
	return groups


# ---------------------------------------------------------------- 每一步


static func _check_name(design: CreatureDesign, record: TutorialRecord) -> String:
	var new_name: String = design.creature_name.strip_edges()
	if new_name == "" or new_name == DEFAULT_NAME:
		return "在上面的「名字」欄取一個自己的名字"
	if new_name == str(record.start.get("creature_name", "")):
		return "名字還是「%s」，改成你自己的生物的名字" % new_name
	return ""


static func _check_bend(design: CreatureDesign, record: TutorialRecord) -> String:
	if record.max_bend_seen < BREAK_BEND:
		return "還沒把「最大彎曲角」拉到 %d 以上" % roundi(rad_to_deg(BREAK_BEND))
	if design.body.max_bend > FIXED_BEND:
		return "看到身體折成一團了嗎？把「最大彎曲角」調回 %d 以下（現在 %d）" % [roundi(rad_to_deg(FIXED_BEND)), roundi(rad_to_deg(design.body.max_bend))]
	return ""


static func _check_body(design: CreatureDesign, record: TutorialRecord) -> String:
	var start_body: Variant = record.start.get("body")
	var before: Dictionary = start_body if start_body is Dictionary else {}
	var after: Dictionary = design.body.to_dict()
	var changed: PackedStringArray = []
	for kind: String in BODY_KINDS:
		for field: String in BODY_KINDS[kind]:
			if before.get(field) != after.get(field):
				changed.append(kind)
				break
	if changed.size() < MIN_BODY_CHANGES:
		return "身體要改 %d 種以上，現在改了 %d 種%s" % [MIN_BODY_CHANGES, changed.size(), "（" + "、".join(changed) + "）" if not changed.is_empty() else ""]
	return ""


static func _check_tentacle(design: CreatureDesign, record: TutorialRecord) -> String:
	if design.tentacles.is_empty():
		return "還沒有觸手：到「觸手」分頁按「新增」"
	if record.min_iterations_seen > 1:
		return "把一隻觸手的「FABRIK 次數」拉到 1，「行為」選「指向滑鼠」，看它跟不跟得上"
	for tentacle: TentacleDesign in design.tentacles:
		if tentacle.iterations < FIXED_ITERATIONS:
			return "看到觸手跟不上了嗎？把「FABRIK 次數」調回 %d 以上（現在有一隻是 %d）" % [FIXED_ITERATIONS, tentacle.iterations]
	return ""


static func _check_legs(design: CreatureDesign, record: TutorialRecord) -> String:
	if design.legs.size() < 2:
		return "「腳」分頁要有 2 組以上的腳（現在 %d 組）：按「新增」或「複製」" % design.legs.size()
	if record.max_rest_distance_seen < STRAIGHT_REST:
		return "① 把一組腳的「落腳距離」拉到 1，看腳打直"
	for leg: LegDesign in design.legs:
		if leg.rest_distance > FIXED_REST:
			return "① 看到腳打直了嗎？把「落腳距離」調回 %.1f 以下（現在有一組是 %.2f）" % [FIXED_REST, leg.rest_distance]
	if not record.same_group_seen:
		return "② 把每一組腳的「分組」都設成同一組，看腳怎麼走"
	if leg_groups(design).size() < 2:
		return "② 看到腳怎麼走了嗎？把分組改回 A、B 都有"
	return ""


static func _check_saved(design: CreatureDesign, record: TutorialRecord) -> String:
	if record.saved.is_empty():
		return "還沒存檔：上面的「資料夾」填英文名字，再按「存檔」"
	if record.saved != design.to_dict():
		return "存檔之後又改了東西，再按一次「存檔」"
	return ""


static func _check_growth(design: CreatureDesign, record: TutorialRecord) -> String:
	if record.max_level_seen < PREVIEW_LEVEL:
		return "把下面的「預覽等級」拉到 %d 以上，看它怎麼長大" % PREVIEW_LEVEL
	if design.growth_mode == int(record.start.get("growth_mode", CreatureDesign.Growth.SCALE)):
		return "到「長大」分頁換一種跟一開始不一樣的「長大方式」"
	return ""


static func _check_ornament_motion(design: CreatureDesign) -> String:
	if design.ornaments.is_empty():
		return "還沒有掛件：到「掛件」分頁按「新增」"
	for ornament: OrnamentDesign in design.ornaments:
		if ornament.motion != Ornament.Motion.FIXED:
			return ""
	return "把一個掛件的「動法」改成「拍動」或「彈簧」"


static func _check_ornament_image(design: CreatureDesign) -> String:
	for ornament: OrnamentDesign in design.ornaments:
		if ornament.image_file != "":
			return ""
	return "選一個掛件按「匯入圖片」，放一張自己畫的 PNG" if not design.ornaments.is_empty() else "還沒有掛件：到「掛件」分頁按「新增」，再按「匯入圖片」"
