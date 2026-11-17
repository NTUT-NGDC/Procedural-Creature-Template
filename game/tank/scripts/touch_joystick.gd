class_name TouchJoystick
extends Control
## 手機用的虛擬搖桿：在手機上玩生態缸時自動加上（Tank 的「手機搖桿」設定，判斷方式見 Tank.is_phone()）。
##
## 　・左半邊：手指放下的地方出現搖桿，往哪推生物就往哪轉；放開手指照原方向繼續游
## 　・右下角的圓：按住加速（用另一根手指按）
## 　・右半邊其他地方：點一下在那裡放飼料
## 最上面一條（暫停按鈕那裡）不算，留給按鈕。
## 沒有觸控螢幕時（「總是顯示」測試用），滑鼠當成一根手指。

## 搖桿推了方向（弧度）
signal steered(angle: float)
## 加速鈕按下、放開
signal boost_changed(on: bool)
## 右半邊點了一下（畫面座標）
signal feed_tapped(at: Vector2)

## 搖桿外圈的半徑（像素）
@export_range(40, 200, 1) var stick_radius: float = 90.0
## 推不到這麼遠不算（像素），避免手指一放上去就轉向
@export_range(0, 60, 1) var dead_zone: float = 12.0
## 加速鈕的半徑（像素）
@export_range(40, 200, 1) var boost_radius: float = 80.0
## 最上面幾像素留給按鈕（暫停），碰到不算
@export_range(0, 200, 1) var top_margin: float = 90.0

## 點一下：手指移動不超過幾像素、多快放開才算「點」（不然是滑過去）
const TAP_MOVE: float = 24.0
const TAP_TIME: float = 0.35
## 滑鼠當手指時用的編號
const MOUSE_FINGER: int = 99

## 哪根手指在推搖桿（-1 是沒有）、搖桿中心、小圓現在在哪
var _stick_finger: int = -1
var _stick_center: Vector2 = Vector2.ZERO
var _stick_knob: Vector2 = Vector2.ZERO
## 哪根手指在按加速（-1 是沒有）
var _boost_finger: int = -1
## 右半邊正在點的手指：編號 → {"at": 位置, "time": 按下的時間}
var _taps: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不擋按鈕：手指的事件在 _input 自己讀


## 加速鈕的中心（右下角）
func boost_center() -> Vector2:
	return size - Vector2(boost_radius, boost_radius) * 1.6


## 沒有手指的時候，搖桿畫在哪（提示：左下角）
func idle_center() -> Vector2:
	return Vector2(stick_radius * 1.8, size.y - stick_radius * 1.8)


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_finger_down(touch.index, touch.position)
		else:
			_finger_up(touch.index, touch.position)
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null:
		_finger_move(drag.index, drag.position)
		return
	# 沒有觸控螢幕（電腦上測試）：滑鼠當一根手指。觸控螢幕模擬出來的滑鼠事件不理，不然會算兩次
	if DisplayServer.is_touchscreen_available() or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_finger_down(MOUSE_FINGER, click.position)
		else:
			_finger_up(MOUSE_FINGER, click.position)
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_finger_move(MOUSE_FINGER, motion.position)


## 手指放下：看放在哪一區
func _finger_down(finger: int, at: Vector2) -> void:
	if at.y < top_margin:
		return  # 最上面留給暫停按鈕
	if at.distance_to(boost_center()) <= boost_radius and _boost_finger == -1:
		_boost_finger = finger
		boost_changed.emit(true)
	elif at.x < size.x / 2.0 and _stick_finger == -1:
		_stick_finger = finger
		_stick_center = at
		_stick_knob = at
	elif at.x >= size.x / 2.0:
		_taps[finger] = {"at": at, "time": Time.get_ticks_msec() / 1000.0}
	queue_redraw()


## 手指移動：推搖桿
func _finger_move(finger: int, at: Vector2) -> void:
	if finger != _stick_finger:
		return
	var offset: Vector2 = at - _stick_center
	if offset.length() > stick_radius:  # 推出外圈：搖桿跟著手指走，不用把手指拉回來
		_stick_center = at - offset.normalized() * stick_radius
		offset = at - _stick_center
	_stick_knob = _stick_center + offset
	if offset.length() > dead_zone:
		steered.emit(offset.angle())
	queue_redraw()


## 手指放開
func _finger_up(finger: int, at: Vector2) -> void:
	if finger == _stick_finger:
		_stick_finger = -1
	if finger == _boost_finger:
		_boost_finger = -1
		boost_changed.emit(false)
	if _taps.has(finger):
		var tap: Dictionary = _taps[finger]
		_taps.erase(finger)
		if at.distance_to(tap.at) <= TAP_MOVE and Time.get_ticks_msec() / 1000.0 - float(tap.time) <= TAP_TIME:
			feed_tapped.emit(at)
	queue_redraw()


## 全部放開（暫停時手指放開的事件收不到，回來時重設，不然會一直加速）
func release_all() -> void:
	if _boost_finger != -1:
		boost_changed.emit(false)
	_stick_finger = -1
	_boost_finger = -1
	_taps.clear()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		release_all()


func is_boosting() -> bool:
	return _boost_finger != -1


## 半透明白圈：搖桿（沒在推的時候淡淡地畫在左下角當提示）和加速鈕
func _draw() -> void:
	var active: bool = _stick_finger != -1
	var center: Vector2 = _stick_center if active else idle_center()
	var knob: Vector2 = _stick_knob if active else center
	draw_circle(center, stick_radius, Color(1, 1, 1, 0.12 if active else 0.06))
	draw_arc(center, stick_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.35 if active else 0.18), 3.0)
	draw_circle(knob, stick_radius * 0.4, Color(1, 1, 1, 0.5 if active else 0.2))
	var boost_at: Vector2 = boost_center()
	draw_circle(boost_at, boost_radius, Color(1, 1, 1, 0.35 if is_boosting() else 0.12))
	draw_arc(boost_at, boost_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.5 if is_boosting() else 0.25), 3.0)
	var font: Font = get_theme_default_font()
	var font_size: int = 22
	var text_size: Vector2 = font.get_string_size("加速", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, boost_at + Vector2(-text_size.x / 2.0, font_size * 0.35), "加速", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.8))
