class_name PartEditor
extends VBoxContainer
## 工坊的零件編輯區：照設計資料的欄位自動長出控制項。
##   有範圍的數字 → 滑桿；選單 → 下拉選單；勾選 → 勾選框；顏色 → 選色器；
##   漸層 → GradientEditor；曲線 → CurveEditor；位置偏移 → 兩個滑桿。
## 分組（@export_group）變成小標題。設計資料加了新欄位，這裡會自動多一個控制項。

## 改了某個欄位
signal changed()
## 掛件按了「匯入圖片」
signal import_image_requested(part: OrnamentDesign)

## 位置偏移（Vector2）的滑桿範圍（像素）
const OFFSET_RANGE: float = 100.0
## 名稱欄的寬度（小字時；大字時用 WorkshopSettings.ui() 放大）
const NAME_WIDTH: float = 88.0
## 滑桿旁邊數字的寬度
const NUMBER_WIDTH: float = 36.0

## 改之前先問「可以這樣改嗎」：回傳 false 就退回原本的值（工坊用來擋「超過複雜度上限」）。空的就都可以改
var can_change: Callable

var _part: PartDesign
var _labels: WorkshopLabels


## 開始編輯一個零件。skip 是不要顯示的欄位
func edit(part: PartDesign, labels: WorkshopLabels, skip: PackedStringArray = PackedStringArray()) -> void:
	_part = part
	_labels = labels
	for child: Node in get_children():
		child.queue_free()
	for prop: Dictionary in part.get_property_list():
		if prop.usage & PROPERTY_USAGE_GROUP:
			_add_header(prop.name)
		elif prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_EDITOR and not prop.name in skip:
			_add_field(prop)
	_remove_empty_headers()


func _add_field(prop: Dictionary) -> void:
	var field: String = prop.name
	var control: Control = null
	if field == "image_file":
		control = _image_row()
	elif prop.hint == PROPERTY_HINT_ENUM:
		control = _option(field, prop.hint_string.split(","))
	elif prop.type == TYPE_BOOL:
		control = _check(field)
	elif prop.type == TYPE_COLOR:
		control = _color(field)
	elif prop.type == TYPE_VECTOR2:
		control = _vector(field)
	elif prop.type == TYPE_OBJECT and _part.get(field) is Gradient:
		control = _gradient(field)
	elif prop.type == TYPE_OBJECT and _part.get(field) is Curve:
		control = _curve(field)
	elif (prop.type == TYPE_INT or prop.type == TYPE_FLOAT) and prop.hint == PROPERTY_HINT_RANGE:
		control = _slider(field, prop)
	if control == null:
		return  # 不認得的欄位（例如零件清單）不顯示
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = _labels.name_of(field)
	name_label.custom_minimum_size.x = WorkshopSettings.ui(NAME_WIDTH)
	name_label.tooltip_text = _labels.hint_of(field)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = _labels.hint_of(field)
	row.add_child(control)
	add_child(row)


# ---------------------------------------------------------------- 各種控制項


## 滑桿＋數字。radians_as_degrees 的欄位顯示成度
func _slider(field: String, prop: Dictionary) -> Control:
	var parts: PackedStringArray = prop.hint_string.split(",")
	var degrees: bool = "radians_as_degrees" in prop.hint_string
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = float(parts[0])
	slider.max_value = float(parts[1])
	slider.step = float(parts[2]) if parts.size() > 2 and parts[2].is_valid_float() else (1.0 if prop.type == TYPE_INT else 0.01)
	slider.value = rad_to_deg(_part.get(field)) if degrees else float(_part.get(field))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var number := Label.new()
	number.custom_minimum_size.x = WorkshopSettings.ui(NUMBER_WIDTH)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show_value: Callable = func(value: float) -> void:
		number.text = ("%d°" % roundi(value)) if degrees else (str(int(value)) if is_equal_approx(value, roundf(value)) else "%.2f" % value)
	show_value.call(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		if not _set_field(field, deg_to_rad(value) if degrees else (int(value) if prop.type == TYPE_INT else value)):
			slider.set_value_no_signal(rad_to_deg(_part.get(field)) if degrees else float(_part.get(field)))  # 不能改：滑桿退回去
		show_value.call(slider.value))
	box.add_child(slider)
	box.add_child(number)
	return box


func _option(field: String, items: PackedStringArray) -> Control:
	var option := OptionButton.new()
	for item: String in items:
		option.add_item(item.get_slice(":", 0))
	option.select(_part.get(field))
	option.item_selected.connect(func(index: int) -> void:
		if not _set_field(field, index):
			option.select(_part.get(field)))  # 不能改：選單退回去
	return option


func _check(field: String) -> Control:
	var check := CheckBox.new()
	check.button_pressed = _part.get(field)
	check.toggled.connect(func(on: bool) -> void: _set_field(field, on))
	return check


func _color(field: String) -> Control:
	var button := ColorPickerButton.new()
	button.color = _part.get(field)
	button.custom_minimum_size = Vector2(WorkshopSettings.ui(30), WorkshopSettings.ui(20))
	button.color_changed.connect(func(color: Color) -> void: _set_field(field, color))
	return button


## 位置偏移：往前（x）、往外（y）兩個滑桿
func _vector(field: String) -> Control:
	var box := VBoxContainer.new()
	for axis: int in 2:
		var row := HBoxContainer.new()
		var axis_label := Label.new()
		axis_label.text = "往前" if axis == 0 else "往外"
		row.add_child(axis_label)
		var slider := HSlider.new()
		slider.min_value = -OFFSET_RANGE
		slider.max_value = OFFSET_RANGE
		slider.step = 1.0
		slider.value = (_part.get(field) as Vector2)[axis]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			var vector: Vector2 = _part.get(field)
			vector[axis] = value
			_set_field(field, vector))
		row.add_child(slider)
		box.add_child(row)
	return box


func _gradient(field: String) -> Control:
	var editor := GradientEditor.new()
	var is_body: bool = _part is BodyDesign
	editor.edit(_part.get(field), "頭" if is_body else "根部", "尾巴" if is_body else "尖端")
	editor.changed.connect(changed.emit)
	return editor


func _curve(field: String) -> Control:
	var editor := CurveEditor.new()
	editor.edit(_part.get(field))
	editor.changed.connect(changed.emit)
	return editor


## 掛件的圖：顯示檔名＋「匯入圖片」「拿掉」
func _image_row() -> Control:
	var ornament: OrnamentDesign = _part as OrnamentDesign
	var box := HBoxContainer.new()
	var file_label := Label.new()
	file_label.text = ornament.image_file if ornament.image_file != "" else "（沒有）"
	file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_label.clip_text = true
	box.add_child(file_label)
	var import_button := Button.new()
	import_button.text = "匯入圖片"
	import_button.tooltip_text = "選一張 PNG（去背的圖最好），會複製到你的生物資料夾"
	import_button.pressed.connect(func() -> void: import_image_requested.emit(ornament))
	box.add_child(import_button)
	var remove := Button.new()
	remove.text = "拿掉"
	remove.disabled = ornament.image_file == ""
	remove.pressed.connect(func() -> void:
		_set_field("image_file", "")
		file_label.text = "（沒有）"
		remove.disabled = true)
	box.add_child(remove)
	return box


# ---------------------------------------------------------------- 其他


## 改一個欄位。can_change 說不行就退回原本的值，回傳 false
func _set_field(field: String, value: Variant) -> bool:
	var old: Variant = _part.get(field)
	_part.set(field, value)
	if can_change.is_valid() and not can_change.call():
		_part.set(field, old)
		return false
	changed.emit()
	return true


func _add_header(text: String) -> void:
	var header := Label.new()
	header.text = "── %s ──" % text
	header.add_theme_color_override("font_color", Color("#f2b766"))
	add_child(header)


## 底下沒有控制項的小標題拿掉（例如整組都被 skip 掉）
func _remove_empty_headers() -> void:
	var children: Array[Node] = get_children()
	for i: int in children.size():
		var is_header: bool = children[i] is Label
		var next_is_header: bool = i + 1 >= children.size() or children[i + 1] is Label
		if is_header and next_is_header:
			children[i].queue_free()
