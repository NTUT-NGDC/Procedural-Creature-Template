class_name FastDraw
extends RefCounted
## 畫圖的快速版：生物、飼料、水草很多的時候（對戰時一個畫面幾十隻），用這兩個畫比較不會卡。
##   ・circle()：圓。先做好一張「白色、邊緣柔和的圓」的圖，每次只是把這張圖染色、縮放貼上去。
##     比 draw_circle() 開抗鋸齒快很多，而且同一張圖可以一起送去顯示卡（一次畫一大批）
##   ・strip()：有粗細的線（觸手、腳、水草）：沿著每一點的兩側排出一條三角形帶子，兩端是半圓，一次畫完
## 用法：在 _draw() 裡呼叫，第一個參數傳 self，例如 FastDraw.circle(self, Vector2.ZERO, 10.0, Color.RED)
##
## 合併：在 _draw() 開頭呼叫 begin(self)、最後呼叫 end()，中間的 circle()、strip() 會先收集起來，
## end() 時一次送去顯示卡（一個零件只要一次繪圖呼叫）。中間如果用了別的 draw_xxx()，
## 它會畫在收集的東西下面（收集的東西 end() 時才畫）。
##
## 畫質：low_quality 是 true 時，零件不畫外框、影子、吸盤、花紋這些比較花時間的細節（對戰預設開）

## 圓的圖有多大（像素）：越大，畫大圓時邊緣越清楚
const TEXTURE_SIZE: int = 128
## 圓的邊緣柔和的寬度（圖上的像素）
const EDGE: float = 2.0
## 線的兩端半圓切幾段
const CAP_STEPS: int = 6
## 圖正中間的位置（不透明的白色）：線（strip）用這一點的顏色，才能跟圓用同一張圖、一起畫
const SOLID_UV: Vector2 = Vector2(0.5, 0.5)
const QUAD_UVS: PackedVector2Array = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

## 畫質「低」：不畫外框等比較花時間的細節（生態缸的「畫質」欄位會設定這個）
static var low_quality: bool = false

static var _circle: Texture2D
## 正在收集的零件（begin() 到 end() 之間），沒有在收集是 null
static var _batch: CanvasItem = null
static var _vertices := PackedVector2Array()
static var _colors := PackedColorArray()
static var _uvs := PackedVector2Array()
static var _indices := PackedInt32Array()


## 開始收集 canvas 的圓和線
static func begin(canvas: CanvasItem) -> void:
	_batch = canvas
	_vertices.resize(0)
	_colors.resize(0)
	_uvs.resize(0)
	_indices.resize(0)


## 把收集的圓和線一次畫出來
static func end() -> void:
	if _batch != null and not _indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(_batch.get_canvas_item(), _indices, _vertices, _colors, _uvs,
			PackedInt32Array(), PackedFloat32Array(), circle_texture().get_rid())
	_batch = null


## 畫一個實心圓（center、radius 是 canvas 的本地座標）
static func circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var size := Vector2(radius, radius) * (2.0 * TEXTURE_SIZE / (TEXTURE_SIZE - EDGE * 2.0))  # 圖的邊緣留了一點空白
	if _batch != canvas:
		canvas.draw_texture_rect(circle_texture(), Rect2(center - size / 2.0, size), false, color)
		return
	# 收集：一個正方形（兩個三角形），貼整張圓的圖
	var first: int = _vertices.size()
	var corner: Vector2 = center - size / 2.0
	_vertices.append_array([corner, corner + Vector2(size.x, 0.0), corner + size, corner + Vector2(0.0, size.y)])
	_colors.append_array([color, color, color, color])
	_uvs.append_array(QUAD_UVS)
	_indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])


## 白色的圓的圖（第一次用到時才做，之後共用同一張）
static func circle_texture() -> Texture2D:
	if _circle == null:
		var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_LA8)
		var center: float = TEXTURE_SIZE / 2.0
		var radius: float = center - EDGE
		for y: int in TEXTURE_SIZE:
			for x: int in TEXTURE_SIZE:
				var distance: float = Vector2(x + 0.5 - center, y + 0.5 - center).length()
				image.set_pixel(x, y, Color(1, 1, 1, clampf((radius - distance) / EDGE + 0.5, 0.0, 1.0)))
		image.generate_mipmaps()  # 畫得很小的時候也平滑
		_circle = ImageTexture.create_from_image(image)
	return _circle


## 畫一條有粗細的線：points 是本地座標，widths 是每一點中心到邊緣的距離，colors 是每一點的顏色。
## caps 是兩端要不要畫半圓（兩端被別的東西蓋住時不用畫，比較快）
static func strip(canvas: CanvasItem, points: PackedVector2Array, widths: PackedFloat32Array, colors: PackedColorArray, caps: bool = true) -> void:
	var count: int = points.size()
	if count < 2:
		return
	if _batch == canvas:
		_add_strip(_vertices, _colors, _uvs, _indices, points, widths, colors, caps)  # 收集，end() 時一起畫
		return
	var vertices := PackedVector2Array()
	var vertex_colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	_add_strip(vertices, vertex_colors, uvs, indices, points, widths, colors, caps)
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, vertex_colors, uvs,
		PackedInt32Array(), PackedFloat32Array(), circle_texture().get_rid())


## 把一條線的三角形接在 vertices、indices 後面
static func _add_strip(vertices: PackedVector2Array, vertex_colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array,
		points: PackedVector2Array, widths: PackedFloat32Array, colors: PackedColorArray, caps: bool) -> void:
	var count: int = points.size()
	var base: int = vertices.size()  # 這條線的第一個頂點
	var base_index: int = indices.size()
	var cap_vertices: int = CAP_STEPS + 2 if caps else 0
	vertices.resize(base + count * 2 + cap_vertices * 2)
	vertex_colors.resize(vertices.size())
	uvs.resize(vertices.size())
	indices.resize(base_index + (count - 1) * 6 + (CAP_STEPS * 3 * 2 if caps else 0))
	for i: int in range(base, vertices.size()):
		uvs[i] = SOLID_UV
	for i: int in count:
		# 這一點的「往旁邊」方向：前後兩段的垂直方向取平均；轉彎的地方拉長一點，粗細才不會變細
		var after: Vector2 = (points[mini(i + 1, count - 1)] - points[i]).normalized().orthogonal() if i < count - 1 else Vector2.ZERO
		var before: Vector2 = (points[i] - points[i - 1]).normalized().orthogonal() if i > 0 else after
		if i == count - 1:
			after = before
		var miter: Vector2 = (before + after).normalized()
		var side: Vector2 = miter * widths[i] / maxf(miter.dot(after), 0.5)
		var v: int = base + i * 2
		vertices[v] = points[i] + side
		vertices[v + 1] = points[i] - side
		vertex_colors[v] = colors[i]
		vertex_colors[v + 1] = colors[i]
		if i > 0:
			var a: int = v - 2  # 上一點的兩個頂點
			var k: int = base_index + (i - 1) * 6
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + 2
			indices[k + 3] = a + 1
			indices[k + 4] = a + 3
			indices[k + 5] = a + 2
	if caps:
		var cap_start: int = base + count * 2
		var cap_index: int = base_index + (count - 1) * 6
		_cap(vertices, vertex_colors, indices, cap_start, cap_index, points[0], points[0] - points[1], widths[0], colors[0])
		_cap(vertices, vertex_colors, indices, cap_start + cap_vertices, cap_index + CAP_STEPS * 3, points[-1], points[-1] - points[-2], widths[-1], colors[-1])


## 線的一端加一個半圓（扇形）：頂點從 first 開始放、三角形從 first_index 開始放，outward 是往外的方向
static func _cap(vertices: PackedVector2Array, vertex_colors: PackedColorArray, indices: PackedInt32Array, first: int, first_index: int, center: Vector2, outward: Vector2, radius: float, color: Color) -> void:
	var start: float = outward.angle() - PI / 2.0
	vertices[first] = center
	vertex_colors[first] = color
	for k: int in CAP_STEPS + 1:
		vertices[first + 1 + k] = center + Vector2.from_angle(start + PI * k / CAP_STEPS) * radius
		vertex_colors[first + 1 + k] = color
		if k > 0:
			indices[first_index + (k - 1) * 3] = first
			indices[first_index + (k - 1) * 3 + 1] = first + k
			indices[first_index + (k - 1) * 3 + 2] = first + k + 1
