class_name WorkshopSettings
extends RefCounted
## 工坊的介面設定（目前只有字的大小），存在 user://workshop_settings.cfg，下次打開工坊還記得。
##
## 俐方體是像素字型，11 的倍數最清楚：「小」11、「大」22；「中」16 在兩個中間，會稍微糊一點。
## 工坊裡跟著字變的寬度（名稱欄、數字欄、右邊的分頁……）都用 ui() 換算。

const SAVE_PATH: String = "user://workshop_settings.cfg"
## 可以選的字大小，順序跟工坊的「文字」選單一樣
const FONT_SIZES: Array[int] = [11, 16, 22]
const FONT_NAMES: PackedStringArray = ["文字：小", "文字：中", "文字：大"]
const BASE_FONT_SIZE: int = 11

static var font_size: int = BASE_FONT_SIZE


## 小字時是 base 的寬度，大字時照比例放大
static func ui(base: float) -> float:
	return base * font_size / BASE_FONT_SIZE


static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var value: Variant = config.get_value("workshop", "font_size", BASE_FONT_SIZE)
	font_size = value if value is int and value in FONT_SIZES else BASE_FONT_SIZE  # 檔案被亂改也不會出事


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("workshop", "font_size", font_size)
	config.save(SAVE_PATH)
