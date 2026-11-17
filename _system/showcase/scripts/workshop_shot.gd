extends Control
## 拍一張「生物工坊」的宣傳圖（1080 × 1350）：工坊原本是橫的，縮小放在中間，上下加字。
## 拍完存到外層 repo 的 docs/promo/workshop.png 就關掉。
##   Godot --path . res://_system/showcase/workshop_shot.tscn

## 畫面大小（IG 直式 4:5）
const SCREEN: Vector2i = Vector2i(1080, 1350)
## 工坊原本的畫面大小
const WORKSHOP_SIZE: Vector2i = Vector2i(1280, 720)

## 工坊一開始載入哪隻生物
@export_file("*.tres") var design_path: String = "res://example/creatures/dragon/design.tres"
## 上面的大標題（太長可以用 \n 換行）
@export_multiline var title: String = "在生物工作坊，\n自己的幻想生物自己捏！"
## 標題下面的小字
@export var subtitle: String = "不需要會寫程式，用滑桿跟按鈕來創造生命吧"
## 工坊畫面下面的標題
@export var footer_title: String = "想跑快一點？一切都由你來創作"
## 工坊畫面下面的小字（太長可以用 \n 換行）
@export_multiline var footer: String = "小提示，增加腳的數量會提升跑速，\n其他就由你來自行探索吧！"
## 等幾秒再拍（讓生物先游起來）
@export_range(0.5, 10, 0.5) var wait_time: float = 3.0
## 背景顏色
@export var background_color: Color = Color("#0b1e24")


func _ready() -> void:
	get_window().borderless = true
	get_window().size = SCREEN
	get_window().position = Vector2i.ZERO
	get_window().content_scale_size = SCREEN
	size = Vector2(SCREEN)
	var background := ColorRect.new()
	background.color = background_color
	background.size = size
	add_child(background)

	# 工坊放在 SubViewport 裡跑原本的大小，再用圖片縮到畫面寬度
	var viewport := SubViewport.new()
	viewport.size = WORKSHOP_SIZE
	add_child(viewport)
	var workshop: Node = load("res://lesson/workshop/workshop.tscn").instantiate()
	workshop.set("start_design", design_path)
	viewport.add_child(workshop)
	workshop.call("_on_move_mode_selected", 1)  # 自己游（不然會一直往滑鼠的位置跑）
	var shown_height: float = SCREEN.x * float(WORKSHOP_SIZE.y) / WORKSHOP_SIZE.x
	var picture := TextureRect.new()
	picture.texture = viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.size = Vector2(SCREEN.x, shown_height)
	picture.position = Vector2(0, (SCREEN.y - shown_height) / 2.0 + 40.0)
	add_child(picture)

	_add_text(title, 55, Color("#ffd166"), 70.0)
	_add_text(subtitle, 33, Color.WHITE, 270.0)
	_add_text(footer_title, 44, Color("#ffd166"), picture.position.y + shown_height + 50.0)
	_add_text(footer, 33, Color.WHITE, picture.position.y + shown_height + 130.0)

	await get_tree().create_timer(wait_time).timeout
	await RenderingServer.frame_post_draw
	var folder: String = ProjectSettings.globalize_path("res://").path_join("../docs/promo")
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join("workshop.png"))
	print("截圖存到 ", folder)
	get_tree().quit()


## 一行置中的字
func _add_text(text: String, font_size: int, color: Color, y: float) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(SCREEN.x, font_size * 1.5)
	label.position = Vector2(0, y)
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = color
	label.label_settings = settings
	add_child(label)
