class_name GradientEditor
extends VBoxContainer
## 工坊的顏色編輯：平常是兩個選色器（頭／尾巴，或根部／尖端），兩個選一樣就是單色。
## 勾「進階」可以加很多顏色、調整每個顏色的位置（漸層）。

## 顏色改了
signal changed()

## 最多幾個顏色
const MAX_STOPS: int = PartDesign.MAX_POINTS

var _gradient: Gradient
## 自己記一份顏色和位置（Gradient 會自己排序，用編號對不起來）
var _offsets: PackedFloat32Array = []
var _colors: PackedColorArray = []
var _simple: HBoxContainer
var _start_button: ColorPickerButton
var _end_button: ColorPickerButton
var _advanced_check: CheckBox
var _advanced: VBoxContainer
var _preview: Control


## 開始編輯一個漸層。start_text、end_text 是兩端的名字（例如「頭」「尾巴」）
func edit(gradient: Gradient, start_text: String, end_text: String) -> void:
	_gradient = gradient
	_offsets = gradient.offsets.duplicate()
	_colors = gradient.colors.duplicate()
	for child: Node in get_children():
		child.queue_free()

	_simple = HBoxContainer.new()
	add_child(_simple)
	_start_button = _color_button(_colors[0], func(color: Color) -> void: _set_simple(color, _end_button.color))
	_end_button = _color_button(_colors[-1], func(color: Color) -> void: _set_simple(_start_button.color, color))
	_simple.add_child(_label(start_text))
	_simple.add_child(_start_button)
	_simple.add_child(_label(end_text))
	_simple.add_child(_end_button)
	_advanced_check = CheckBox.new()
	_advanced_check.text = "進階"
	_advanced_check.tooltip_text = "加很多顏色、調整每個顏色的位置"
	_advanced_check.toggled.connect(func(on: bool) -> void: _advanced.visible = on)
	_simple.add_child(_advanced_check)

	_advanced = VBoxContainer.new()
	add_child(_advanced)
	_advanced.visible = _offsets.size() > 2
	_advanced_check.button_pressed = _advanced.visible
	_build_advanced()


## 簡單模式：只留兩個顏色，頭（根部）一個、尾巴（尖端）一個
func _set_simple(start: Color, end: Color) -> void:
	_offsets = PackedFloat32Array([0.0, 1.0])
	_colors = PackedColorArray([start, end])
	_apply()
	_build_advanced()


## 進階模式：預覽條＋每個顏色一列（位置滑桿、選色器、刪除）＋新增
func _build_advanced() -> void:
	for child: Node in _advanced.get_children():
		child.queue_free()
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(0, WorkshopSettings.ui(12))
	_preview.draw.connect(_draw_preview)
	_advanced.add_child(_preview)
	for i: int in _offsets.size():
		var row := HBoxContainer.new()
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = _offsets[i]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.tooltip_text = "這個顏色在哪裡：0 是頭（根部），1 是尾巴（尖端）"
		slider.value_changed.connect(func(value: float) -> void:
			_offsets[i] = value
			_apply())
		row.add_child(slider)
		row.add_child(_color_button(_colors[i], func(color: Color) -> void:
			_colors[i] = color
			_apply()))
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "刪掉這個顏色"
		remove.disabled = _offsets.size() <= 1
		remove.pressed.connect(func() -> void:
			_offsets.remove_at(i)
			_colors.remove_at(i)
			_apply()
			_build_advanced())
		row.add_child(remove)
		_advanced.add_child(row)
	var add := Button.new()
	add.text = "＋ 加一個顏色"
	add.disabled = _offsets.size() >= MAX_STOPS
	add.pressed.connect(func() -> void:
		_offsets.append(0.5)
		_colors.append(_gradient.sample(0.5))
		_apply()
		_build_advanced())
	_advanced.add_child(add)


## 把顏色寫回漸層，同步兩個簡單選色器，通知外面
func _apply() -> void:
	_gradient.offsets = _offsets
	_gradient.colors = _colors
	_start_button.color = _gradient.sample(0.0)
	_end_button.color = _gradient.sample(1.0)
	if _preview != null:
		_preview.queue_redraw()
	changed.emit()


func _draw_preview() -> void:
	var width: float = _preview.size.x
	for x: int in int(width):
		_preview.draw_line(Vector2(x, 0), Vector2(x, _preview.size.y), _gradient.sample(x / width))
	for offset: float in _offsets:
		_preview.draw_line(Vector2(offset * width, 0), Vector2(offset * width, _preview.size.y), Color.BLACK, 2.0)


func _color_button(color: Color, on_change: Callable) -> ColorPickerButton:
	var button := ColorPickerButton.new()
	button.color = color
	button.custom_minimum_size = Vector2(WorkshopSettings.ui(30), WorkshopSettings.ui(20))
	button.color_changed.connect(on_change)
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
