extends Control
## IG 輪播最後一張：報名用的 QR Code（1080 × 1350）。
## 文字和 QR Code 圖片放在外層 repo 的 docs/promo/qr_card/（網址不放進學員 repo）：
##   qr_card.tres：文字（QrCardText）；signup_qr.png：QR Code（用 docs/promo/make_qr.py 產生）
## 拍完存成外層的 docs/promo/slide_5.png 就關掉：
##   Godot --path . res://_system/showcase/qr_card.tscn

## 畫面大小（IG 直式 4:5）
const SCREEN: Vector2i = Vector2i(1080, 1350)
## 外層 repo 放素材的資料夾（從專案資料夾往上一層）
const PROMO_FOLDER: String = "../docs/promo"
const ORANGE: Color = Color("#f2b766")
const YELLOW: Color = Color("#ffd166")
const INK: Color = Color("#0b1e24")
## 卡片的內距、QR Code 和下面文字的間距
const CARD_PADDING: float = 56.0
## 等幾秒再拍（讓背景的生物先游起來）
const WAIT_TIME: float = 2.5

## 背景變多暗（0 不變暗、1 全黑）：不要搶 QR Code
@export_range(0, 1, 0.05) var background_dim: float = 0.45

var _text: QrCardText
var _creatures: Array[Creature] = []


func _ready() -> void:
	get_window().borderless = true
	get_window().size = SCREEN
	get_window().position = Vector2i.ZERO
	get_window().content_scale_size = SCREEN
	size = Vector2(SCREEN)
	var folder: String = ProjectSettings.globalize_path("res://").path_join(PROMO_FOLDER)
	_text = ResourceLoader.load(folder.path_join("qr_card/qr_card.tres")) as QrCardText
	var qr: Image = Image.load_from_file(folder.path_join("qr_card/signup_qr.png"))
	if _text == null or qr == null:
		push_error("讀不到 %s/qr_card/ 裡的 qr_card.tres 或 signup_qr.png" % folder)
		get_tree().quit(1)
		return
	WaterFlow.strength = 20.0
	_add_background()
	_add_band()
	_add_card(ImageTexture.create_from_image(qr))

	await get_tree().create_timer(WAIT_TIME).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("slide_5.png"))
	print("存到 ", folder.path_join("slide_5.png"))
	get_tree().quit()


func _exit_tree() -> void:
	WaterFlow.reset()


# ---------- 背景 ----------

## 生態缸的水、水草，兩隻生物在卡片上下游過去，最後整個壓暗
func _add_background() -> void:
	var world := Node2D.new()
	add_child(world)
	var water := TankWater.new()
	water.world_size = Vector2(SCREEN)
	world.add_child(water)
	for i: int in 9:
		var weed := Weed.new()
		weed.position = Vector2(60.0 + i * 120.0 + (i % 2) * 30.0, SCREEN.y - 26.0)
		weed.height = 90.0 + (i * 37 % 5) * 30.0
		weed.segment_count = maxi(4, roundi(weed.height / 20.0))
		weed.lean = 0.15 * sin(i * 1.7)
		world.add_child(weed)
	_add_swimmer(world, "dragon", Vector2(180, 1170), 0.0)
	_add_swimmer(world, "jellyfish", Vector2(980, 1110), PI)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, background_dim)
	dim.size = size
	add_child(dim)


## 一隻往 heading 方向直直游的生物
func _add_swimmer(world: Node2D, design_name: String, at: Vector2, heading: float) -> void:
	var creature := Creature.new()
	creature.design = load("res://example/creatures/%s/design.tres" % design_name)
	creature.control_mode = Creature.Mode.WANDER
	creature.bounds = Rect2(-600, -600, SCREEN.x + 1200, SCREEN.y + 1200)
	world.add_child(creature)
	creature.set_level(2)
	creature.global_position = at - Vector2.from_angle(heading) * creature.speed * 0.7 * WAIT_TIME
	creature.heading = heading
	creature.reset_pose()
	creature.brain = func() -> Dictionary: return {"angle": heading, "speed": creature.speed * 0.7}
	_creatures.append(creature)


# ---------- 前景 ----------

## 上方：橘色色帶上寫社團名，下面一行黃色大標題
func _add_band() -> void:
	var band := ColorRect.new()
	band.color = ORANGE
	band.position = Vector2(0, 70)
	band.size = Vector2(SCREEN.x, 76)
	add_child(band)
	_add_label(_text.club_line, 44, INK, Vector2(0, 80), SCREEN.x)
	_add_label(_text.title, 66, YELLOW, Vector2(0, 178), SCREEN.x, true)


## 中間：白色卡片，裡面是 QR Code（原尺寸、不縮放）、表單名稱、網址
func _add_card(qr: Texture2D) -> void:
	var qr_size: Vector2 = qr.get_size()
	var width: float = qr_size.x + CARD_PADDING * 2.0
	var height: float = qr_size.y + CARD_PADDING + 150.0
	var card := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(24)
	style.set_border_width_all(6)
	style.border_color = ORANGE
	card.add_theme_stylebox_override("panel", style)
	card.size = Vector2(width, height)
	card.position = Vector2((SCREEN.x - width) / 2.0, 330.0).round()
	add_child(card)

	var picture := TextureRect.new()
	picture.texture = qr
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 不要平滑，點的邊才會銳利
	picture.size = qr_size
	picture.position = card.position + Vector2(CARD_PADDING, CARD_PADDING * 0.6).round()
	add_child(picture)

	var below: float = picture.position.y + qr_size.y + 6.0
	_add_label(_text.form_label, 44, INK, Vector2(card.position.x, below), width)
	var shown: String = _text.shown_url if _text.shown_url != "" else _text.url.trim_prefix("https://").trim_prefix("http://")
	_add_label(shown, 33, Color("#4a5a60"), Vector2(card.position.x, below + 66.0), width)


func _add_label(text: String, font_size: int, color: Color, at: Vector2, width: float, shadow: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = at
	label.size = Vector2(width, font_size * 1.4)
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = color
	if shadow:
		settings.shadow_color = Color(0, 0, 0, 0.6)
		settings.shadow_offset = Vector2(4, 4)
	label.label_settings = settings
	add_child(label)
