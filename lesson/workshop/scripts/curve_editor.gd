class_name CurveEditor
extends VBoxContainer
## 工坊的粗細形狀編輯：平常從內建的形狀選一個。
## 勾「進階」可以直接拖曲線：拖點移動、雙擊空白處加點、右鍵點刪掉。左邊是頭、右邊是尾巴。

## 形狀改了
signal changed()

## 內建的形狀：名字 → 點（x 是頭到尾 0～1，y 是粗細 0～1）
const PRESETS: Dictionary = {
	"頭大尾尖": [Vector2(0, 0.75), Vector2(0.2, 1), Vector2(1, 0.1)],
	"平均": [Vector2(0, 1), Vector2(1, 1)],
	"尾巴圓": [Vector2(0, 0.8), Vector2(0.3, 1), Vector2(1, 0.6)],
	"中間粗": [Vector2(0, 0.5), Vector2(0.5, 1), Vector2(1, 0.3)],
	"頭小尾大": [Vector2(0, 0.6), Vector2(0.7, 1), Vector2(1, 0.8)],
	"葫蘆": [Vector2(0, 0.8), Vector2(0.25, 1), Vector2(0.45, 0.55), Vector2(0.7, 1), Vector2(1, 0.4)],
}
## 點的半徑（像素）、曲線區的高度（再加上跟著字變的一段）
const POINT_RADIUS: float = 7.0
const CANVAS_HEIGHT: float = 50.0

var _curve: Curve
var _preset: OptionButton
var _canvas: Control
## 正在拖的點（-1 是沒有）
var _dragging: int = -1


func edit(curve: Curve) -> void:
	_curve = curve
	for child: Node in get_children():
		child.queue_free()
	var row := HBoxContainer.new()
	add_child(row)
	_preset = OptionButton.new()
	_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset.add_item("（自訂）")
	for preset_name: String in PRESETS:
		_preset.add_item(preset_name)
	_preset.item_selected.connect(_on_preset_selected)
	row.add_child(_preset)
	var advanced := CheckBox.new()
	advanced.text = "進階"
	advanced.tooltip_text = "直接拖曲線：拖點移動、雙擊空白處加點、右鍵點刪掉"
	row.add_child(advanced)

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, CANVAS_HEIGHT + WorkshopSettings.ui(30))
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_canvas_input)
	_canvas.visible = false
	advanced.toggled.connect(func(on: bool) -> void: _canvas.visible = on)
	add_child(_canvas)
	_select_matching_preset()


func _on_preset_selected(index: int) -> void:
	if index == 0:
		return
	_curve.clear_points()
	for point: Vector2 in PRESETS[_preset.get_item_text(index)]:
		_curve.add_point(point)
	_changed()


## 現在的曲線跟哪個內建形狀一樣，選單就選那個；都不一樣是「（自訂）」
func _select_matching_preset() -> void:
	_preset.select(0)
	for i: int in range(1, _preset.item_count):
		var points: Array = PRESETS[_preset.get_item_text(i)]
		if points.size() != _curve.point_count:
			continue
		var same: bool = true
		for k: int in points.size():
			same = same and _curve.get_point_position(k).is_equal_approx(points[k])
		if same:
			_preset.select(i)
			return


# ---------------------------------------------------------------- 進階：拖曲線


## 曲線座標（0～1）↔ 畫面座標
func _to_canvas(point: Vector2) -> Vector2:
	return Vector2(point.x * _canvas.size.x, (1.0 - point.y) * _canvas.size.y)


func _from_canvas(at: Vector2) -> Vector2:
	return Vector2(clampf(at.x / _canvas.size.x, 0, 1), clampf(1.0 - at.y / _canvas.size.y, 0, 1))


func _point_at(at: Vector2) -> int:
	for i: int in _curve.point_count:
		if _to_canvas(_curve.get_point_position(i)).distance_to(at) <= POINT_RADIUS * 1.5:
			return i
	return -1


func _on_canvas_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		var hit: int = _point_at(button.position)
		if button.button_index == MOUSE_BUTTON_RIGHT and hit >= 0 and _curve.point_count > 2:
			_curve.remove_point(hit)  # 右鍵：刪點（最少留 2 個）
			_changed()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.double_click and hit < 0 and _curve.point_count < PartDesign.MAX_POINTS:
			_curve.add_point(_from_canvas(button.position))  # 雙擊空白：加點
			_changed()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = hit
	elif button != null and not button.pressed:
		_dragging = -1
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging >= 0:
		var point: Vector2 = _from_canvas(motion.position)
		_curve.set_point_value(_dragging, point.y)
		_dragging = _curve.set_point_offset(_dragging, point.x)  # 換位置後點的編號可能會變
		_changed()


func _draw_canvas() -> void:
	var area := Rect2(Vector2.ZERO, _canvas.size)
	_canvas.draw_rect(area, Color(0, 0, 0, 0.3))
	var line := PackedVector2Array()
	for x: int in int(_canvas.size.x) + 1:
		var t: float = x / _canvas.size.x
		line.append(_to_canvas(Vector2(t, _curve.sample(t))))
	_canvas.draw_polyline(line, Color.WHITE, 2.0, true)
	for i: int in _curve.point_count:
		_canvas.draw_circle(_to_canvas(_curve.get_point_position(i)), POINT_RADIUS, Color("#f2b766"))
	var font_size: int = WorkshopSettings.font_size
	_canvas.draw_string(get_theme_default_font(), Vector2(4, _canvas.size.y - 4), "頭", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_canvas.draw_string(get_theme_default_font(), Vector2(_canvas.size.x - font_size * 2 - 4, _canvas.size.y - 4), "尾巴", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)


func _changed() -> void:
	_canvas.queue_redraw()
	_select_matching_preset()
	changed.emit()
