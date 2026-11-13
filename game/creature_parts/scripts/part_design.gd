@tool
class_name PartDesign
extends Resource
## 設計檔裡「一個零件」的資料（身體、腳、觸手、眼睛、掛件都繼承這個）。
##
## 每個欄位的名字都跟零件節點的屬性一樣（例如 segment_count、max_bend），
## 所以 apply_to() 只要把同名的欄位一個一個複製過去，零件就會變成設計檔的樣子。
## 加新屬性時：零件節點和設計資料用同一個名字、同一個範圍。
##
## to_dict()／from_dict()：轉成只有數字、字串、陣列的資料，連線時傳這個，不傳 .tres。
## from_dict() 會檢查每一欄的型別，並把數字夾回 @export_range 的範圍內，收到奇怪的資料也不會出事。

## 漸層、曲線最多幾個點；字串最多幾個字；位置偏移最多幾像素
const MAX_POINTS: int = 16
const MAX_TEXT: int = 40
const MAX_OFFSET: float = 500.0


## 只在設計檔裡、零件節點上沒有的欄位（套用到節點時略過）。子類別可以覆寫
func design_only_fields() -> PackedStringArray:
	return PackedStringArray()


## 這份資料的所有欄位（照宣告的順序）
func fields() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for prop: Dictionary in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			result.append(prop)
	return result


## 把設計套用到零件節點：同名的屬性一個一個複製過去
func apply_to(node: Node) -> void:
	var skip: PackedStringArray = design_only_fields()
	for prop: Dictionary in fields():
		var field: String = prop.name
		if field in skip or not field in node:
			continue
		node.set(field, get(field))


## 反過來：從零件節點讀出設計（把舊的 .tscn 範例轉成設計檔時用）
func capture_from(node: Node) -> void:
	for prop: Dictionary in fields():
		var field: String = prop.name
		if field in node:
			var value: Variant = node.get(field)
			set(field, value.duplicate() if value is Resource else value)


## 轉成只有數字、字串、陣列的資料
func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for prop: Dictionary in fields():
		var value: Variant = encode(get(prop.name))
		if value != null:
			result[prop.name] = value
	return result


## 從資料讀回來。缺的欄位維持預設值；型別不對的欄位略過；數字夾回範圍內
func from_dict(data: Dictionary) -> void:
	for prop: Dictionary in fields():
		if data.has(prop.name):
			var value: Variant = decode(data[prop.name], prop)
			if value != null:
				set(prop.name, value)


# ---------------------------------------------------------------- 轉換


## 一個值 → 只有數字、字串、陣列的資料。不認得的型別回傳 null（不傳）
static func encode(value: Variant) -> Variant:
	if value is bool or value is int or value is float or value is String:
		return value
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Vector2:
		return [value.x, value.y]
	if value is Gradient:
		var colors: Array = []
		for color: Color in value.colors:
			colors.append(encode(color))
		return {"offsets": Array(value.offsets), "colors": colors}
	if value is Curve:
		var points: Array = []
		for i: int in value.point_count:
			var p: Vector2 = value.get_point_position(i)
			points.append([p.x, p.y, value.get_point_left_tangent(i), value.get_point_right_tangent(i)])
		return {"points": points}
	if value is PartDesign:
		return value.to_dict()
	if value is Array:
		return value.map(encode)
	return null


## 資料 → 欄位的值（prop 是欄位的資訊，用來知道型別和範圍）。不合格回傳 null
static func decode(value: Variant, prop: Dictionary) -> Variant:
	match prop.type:
		TYPE_BOOL:
			return value if value is bool else null
		TYPE_INT:
			return int(round(_clamp_to_range(value, prop))) if _is_number(value) else null
		TYPE_FLOAT:
			return _clamp_to_range(value, prop) if _is_number(value) else null
		TYPE_STRING:
			return (value as String).left(MAX_TEXT) if value is String else null
		TYPE_COLOR:
			return _decode_color(value)
		TYPE_VECTOR2:
			if not _is_numbers(value, 2):
				return null
			return Vector2(clampf(value[0], -MAX_OFFSET, MAX_OFFSET), clampf(value[1], -MAX_OFFSET, MAX_OFFSET))
		TYPE_OBJECT:
			match prop.hint_string:
				"Gradient":
					return _decode_gradient(value)
				"Curve":
					return _decode_curve(value)
	return null


## 數字夾回 @export_range 的範圍；選單（@export_enum）夾在第一個到最後一個選項之間
static func _clamp_to_range(value: float, prop: Dictionary) -> float:
	var hint: String = prop.hint_string
	if prop.hint == PROPERTY_HINT_RANGE:
		var parts: PackedStringArray = hint.split(",")
		var low: float = float(parts[0])
		var high: float = float(parts[1])
		if "radians_as_degrees" in hint:  # 範圍寫的是度，存的是弧度
			low = deg_to_rad(low)
			high = deg_to_rad(high)
		return clampf(value, low, high)
	if prop.hint == PROPERTY_HINT_ENUM:
		return clampf(value, 0.0, hint.split(",").size() - 1.0)
	return value


static func _decode_color(value: Variant) -> Variant:
	if not _is_numbers(value, 3) and not _is_numbers(value, 4):
		return null
	var alpha: float = value[3] if value.size() == 4 else 1.0
	return Color(clampf(value[0], 0, 1), clampf(value[1], 0, 1), clampf(value[2], 0, 1), clampf(alpha, 0, 1))


static func _decode_gradient(value: Variant) -> Variant:
	if not value is Dictionary or not value.get("offsets") is Array or not value.get("colors") is Array:
		return null
	var offsets: Array = value.offsets
	var colors: Array = value.colors
	if offsets.is_empty() or offsets.size() != colors.size() or offsets.size() > MAX_POINTS:
		return null
	var gradient := Gradient.new()
	var packed_offsets := PackedFloat32Array()
	var packed_colors := PackedColorArray()
	for i: int in offsets.size():
		var color: Variant = _decode_color(colors[i])
		if not _is_number(offsets[i]) or color == null:
			return null
		packed_offsets.append(clampf(offsets[i], 0.0, 1.0))
		packed_colors.append(color)
	gradient.offsets = packed_offsets
	gradient.colors = packed_colors
	return gradient


static func _decode_curve(value: Variant) -> Variant:
	if not value is Dictionary or not value.get("points") is Array:
		return null
	var points: Array = value.points
	if points.is_empty() or points.size() > MAX_POINTS:
		return null
	var curve := Curve.new()
	for point: Variant in points:
		if not _is_numbers(point, 4):
			return null
		curve.add_point(Vector2(clampf(point[0], 0, 1), clampf(point[1], 0, 1)), clampf(point[2], -10, 10), clampf(point[3], -10, 10))
	return curve


## 是不是一個正常的數字（不是 NaN、無限大）
static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


## 是不是剛好 count 個正常數字的陣列
static func _is_numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for item: Variant in value:
		if not _is_number(item):
			return false
	return true
