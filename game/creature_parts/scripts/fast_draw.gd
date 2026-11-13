class_name FastDraw
extends RefCounted
## 畫圖的快速版：生物、飼料、水草很多的時候（對戰時一個畫面幾十隻），用這兩個畫比較不會卡。
##   ・circle()：圓。先做好一張「白色、邊緣柔和的圓」的圖，每次只是把這張圖染色、縮放貼上去。
##     比 draw_circle() 開抗鋸齒快很多，而且同一張圖可以一起送去顯示卡（一次畫一大批）
##   ・strip()：有粗細的線（觸手、腳、水草）：沿著每一點的兩側排出一條三角形帶子，兩端是半圓，一次畫完
## 用法：在 _draw() 裡呼叫，第一個參數傳 self，例如 FastDraw.circle(self, Vector2.ZERO, 10.0, Color.RED)

## 圓的圖有多大（像素）：越大，畫大圓時邊緣越清楚
const TEXTURE_SIZE: int = 128
## 圓的邊緣柔和的寬度（圖上的像素）
const EDGE: float = 2.0
## 線的兩端半圓切幾段
const CAP_STEPS: int = 6

static var _circle: Texture2D


## 畫一個實心圓（center、radius 是 canvas 的本地座標）
static func circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var size := Vector2(radius, radius) * (2.0 * TEXTURE_SIZE / (TEXTURE_SIZE - EDGE * 2.0))  # 圖的邊緣留了一點空白
	canvas.draw_texture_rect(circle_texture(), Rect2(center - size / 2.0, size), false, color)


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
	var cap_vertices: int = CAP_STEPS + 2 if caps else 0
	var vertices := PackedVector2Array()
	var vertex_colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(count * 2 + cap_vertices * 2)
	vertex_colors.resize(vertices.size())
	indices.resize((count - 1) * 6 + (CAP_STEPS * 3 * 2 if caps else 0))
	for i: int in count:
		# 這一點的「往旁邊」方向：前後兩段的垂直方向取平均；轉彎的地方拉長一點，粗細才不會變細
		var after: Vector2 = (points[mini(i + 1, count - 1)] - points[i]).normalized().orthogonal() if i < count - 1 else Vector2.ZERO
		var before: Vector2 = (points[i] - points[i - 1]).normalized().orthogonal() if i > 0 else after
		if i == count - 1:
			after = before
		var miter: Vector2 = (before + after).normalized()
		var side: Vector2 = miter * widths[i] / maxf(miter.dot(after), 0.5)
		vertices[i * 2] = points[i] + side
		vertices[i * 2 + 1] = points[i] - side
		vertex_colors[i * 2] = colors[i]
		vertex_colors[i * 2 + 1] = colors[i]
		if i > 0:
			var a: int = (i - 1) * 2  # 上一點的兩個頂點
			var k: int = (i - 1) * 6
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + 2
			indices[k + 3] = a + 1
			indices[k + 4] = a + 3
			indices[k + 5] = a + 2
	if caps:
		_cap(vertices, vertex_colors, indices, count * 2, (count - 1) * 6, points[0], points[0] - points[1], widths[0], colors[0])
		_cap(vertices, vertex_colors, indices, count * 2 + cap_vertices, (count - 1) * 6 + CAP_STEPS * 3, points[-1], points[-1] - points[-2], widths[-1], colors[-1])
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, vertex_colors)


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
