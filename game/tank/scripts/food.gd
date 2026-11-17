class_name Food
extends Node2D
## 飼料：發光的小點，浮在水裡、被水流輕輕帶著飄（不會往下沉）。分小顆和大顆，大顆算好幾個。
## 生物的頭碰到（或觸手抓到）就被吃掉。由生態缸（tank.gd）產生，不用自己放進場景。
## 生物掉出來的飼料（加速時一路掉的、撞死時散出來的）照那隻生物設計檔的「噴出的飼料」畫（look），只是外觀。

## 小顆、大顆的半徑（像素）：被吃到的範圍。外觀的「大小」不會改這個
const RADIUS: float = 6.0
const BIG_RADIUS: float = 10.0
## 被水流帶著走的比例
const FLOW_FOLLOW: float = 0.5
## 圓以外的形狀畫大一點，小小的星星、愛心才看得出來
const SHAPE_SCALE: float = 1.5

## 形狀的編號，跟設計檔「噴出的飼料」的形狀選單一樣
enum Shape { CIRCLE, STAR, HEART, DIAMOND, BUBBLE, DROP }

## 沒有 look 時的顏色（生態缸的飼料顏色）
var color: Color = Color("#ffd84d")
## 照哪一份設計檔的「噴出的飼料」畫。空的是一般的飼料（color 的圓點）
var look: CreatureDesign = null
## 能不能吃：工坊「噴一下看看」噴出來的只給人看，不能吃（觸手也不會去抓）
var edible: bool = true
## 吃到算幾個（小顆 1，大顆看平衡資料的 big_food_value）
var value: int = 1
## 半徑：小顆 RADIUS，大顆 BIG_RADIUS（生態缸放的時候設好）
var radius: float = RADIUS
## 地板的高度（全局 y）：飄到這裡就擋住
var floor_y: float = 690.0
## 左右的範圍（全局 x），飄出去會被擋回來
var min_x: float = 0.0
var max_x: float = 1280.0
## 幾秒之後才能吃（生物掉出來的飼料，不然撞到的那隻馬上又吃回去）
var wait: float = 0.0

var _time: float = 0.0

## 形狀的輪廓（半徑大約 1 的點，畫的時候放大），第一次用到才算、大家共用。
## 鍵是形狀（星星還要加上角數、胖瘦）
static var _outlines: Dictionary = {}


func _ready() -> void:
	if wait <= 0.0 and edible:
		add_to_group("food")  # 生態缸、觸手用這個群組找能吃的飼料
	_time = randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	if wait > 0.0:
		wait -= delta
		if wait <= 0.0 and edible:
			add_to_group("food")
	modulate.a = 0.5 if wait > 0.0 else 1.0  # 還不能吃：淡一點
	# 浮在水裡，被水流輕輕帶著飄；飄到邊上就擋住
	global_position += WaterFlow.at(global_position) * FLOW_FOLLOW * delta
	global_position.x = clampf(global_position.x, min_x + radius, max_x - radius)
	global_position.y = clampf(global_position.y, radius, floor_y)
	queue_redraw()


func _draw() -> void:
	draw_look(self, Vector2.ZERO, radius, look, color, _time)


## 畫一顆飼料（工坊的「飼料」分頁也用這個畫預覽）。
## base 是被吃到的半徑；design 空的話畫一般的飼料（fallback 顏色的圓點）；time 讓光暈一呼一吸
static func draw_look(canvas: CanvasItem, at: Vector2, base: float, design: CreatureDesign, fallback: Color, time: float) -> void:
	if design == null:  # 一般的飼料：圓點＋光暈＋亮點
		if not FastDraw.low_quality:
			FastDraw.circle(canvas, at, base * (1.8 + sin(time * 3.0) * 0.3), Color(fallback, 0.2))
		FastDraw.circle(canvas, at, base, fallback)
		FastDraw.circle(canvas, at + Vector2(-base, -base) / 3.0, base * 0.35, Color(1, 1, 1, 0.6))
		return
	var size: float = base * design.spray_size  # 看起來的大小
	if design.spray_glow and not FastDraw.low_quality:  # 光暈
		FastDraw.circle(canvas, at, size * maxf(design.spray_glow_size + sin(time * 3.0) * design.spray_glow_pulse, 0.0), design.spray_glow_color)
	var line: float = size * design.spray_outline_width  # 外框寬度（像素）
	match design.spray_shape:
		Shape.CIRCLE:
			FastDraw.circle(canvas, at, size, design.spray_color)
			if design.spray_outline:
				canvas.draw_arc(at, size, 0.0, TAU, 20, design.spray_outline_color, line)
		Shape.BUBBLE:  # 泡泡：淡淡的圓、一圈邊（有外框就用外框的顏色和寬度）
			FastDraw.circle(canvas, at, size * SHAPE_SCALE, Color(design.spray_color, design.spray_color.a * 0.25))
			canvas.draw_arc(at, size * SHAPE_SCALE, 0.0, TAU, 20,
				design.spray_outline_color if design.spray_outline else design.spray_color, line if design.spray_outline else 1.5)
		_:  # 其他形狀：把輪廓轉個角度、放大畫出來（外框寬度要除回放大的倍率，不然會跟著變粗）
			var zoom: float = size * SHAPE_SCALE
			var points: PackedVector2Array = outline(design.spray_shape, design.spray_star_points, design.spray_star_inner)
			canvas.draw_set_transform(at, design.spray_angle, Vector2.ONE * zoom)
			canvas.draw_colored_polygon(points, design.spray_color)
			if design.spray_outline:
				canvas.draw_polyline(points + PackedVector2Array([points[0]]), design.spray_outline_color, line / zoom)
			canvas.draw_set_transform(Vector2.ZERO)
	if design.spray_shine:  # 亮點
		FastDraw.circle(canvas, at + Vector2(-size, -size) / 3.0, size * 0.35, design.spray_shine_color)


## 形狀的輪廓（半徑大約 1，中心在原點）。star_points、star_inner 只有星星用
static func outline(which: int, star_points: int = 5, star_inner: float = 0.45) -> PackedVector2Array:
	var key: String = "%d_%d_%.2f" % [which, star_points, star_inner] if which == Shape.STAR else str(which)
	if not _outlines.has(key):
		_outlines[key] = _make_outline(which, star_points, star_inner)
	return _outlines[key]


static func _make_outline(which: int, star_points: int, star_inner: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	match which:
		Shape.STAR:  # 星星：外圈（尖角）、內圈（凹進去）輪流
			for i: int in star_points * 2:
				points.append(Vector2.from_angle(-PI / 2.0 + i * PI / star_points) * (1.0 if i % 2 == 0 else star_inner))
		Shape.HEART:  # 愛心曲線，縮成半徑 1 左右
			for i: int in 24:
				var t: float = i * TAU / 24.0
				points.append(Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) / 16.0)
		Shape.DIAMOND:
			points = PackedVector2Array([Vector2(0, -1.1), Vector2(0.7, 0), Vector2(0, 1.1), Vector2(-0.7, 0)])
		Shape.DROP:  # 水滴：上面尖、下面圓
			points.append(Vector2(0, -1.2))
			for i: int in 13:
				points.append(Vector2.from_angle(-PI / 6.0 + i * (PI + PI / 3.0) / 12.0) * 0.75 + Vector2(0, 0.3))
		_:
			for i: int in 12:
				points.append(Vector2.from_angle(i * TAU / 12.0))
	return points


## Creature.eat() 會呼叫這個：被吃掉就消失
func on_eaten(_creature: Creature) -> void:
	remove_from_group("food")
	queue_free()
