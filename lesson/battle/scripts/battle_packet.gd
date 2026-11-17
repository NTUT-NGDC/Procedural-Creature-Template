class_name BattlePacket
extends RefCounted
## 連線對戰：加入時要傳的資料（名稱＋設計檔＋圖）怎麼打包、主機怎麼檢查、收到的人怎麼還原。
## 詳細的格式見外層 repo 的 docs/network_format.md。
##
## 安全：不傳 .tres（.tres 可以夾帶程式），設計檔只傳 to_dict() 的數字、字串、陣列；圖只傳 PNG 的位元組。
## 主機收到後逐項檢查，不合格就拒絕；收到的一方用 from_dict() 自己建設計檔、用 load_png_from_buffer() 讀圖。
## 都是純函式，加入畫面、主機、測試用同一份。

## 協定版本：改了資料格式就加 1，版本不同的連不上
const VERSION: int = 1
## 名稱最多幾個字
const MAX_NAME: int = 16
## 所有圖加起來最多多大（位元組）
const MAX_IMAGE_BYTES: int = 1024 * 1024
## 整包資料最多多大（圖＋設計檔＋一點餘裕）
const MAX_PACKET_BYTES: int = 1536 * 1024
## 每張圖最大幾像素（工坊匯入時已經縮到這麼大）
const MAX_IMAGE_SIDE: int = 512
## 圖太大時，依序試著縮成這些大小（長邊幾像素）
const SHRINK_SIDES: Array[int] = [384, 256, 192, 128]


## 這份設計檔用到哪些圖（檔名，不重複）：身體的頭、每一節、尾巴，和每個掛件的圖
static func image_files(design: CreatureDesign) -> PackedStringArray:
	var files := PackedStringArray()
	var names: Array = []
	for field: String in BodyDesign.image_fields():
		names.append(design.body.get(field))
	for ornament: OrnamentDesign in design.ornaments:
		names.append(ornament.image_file)
	for file: Variant in names:
		var safe: String = OrnamentDesign.safe_image_file(str(file))
		if safe != "" and not files.has(safe):
			files.append(safe)
	return files


## 從硬碟讀這份設計檔用到的圖：檔名 → PNG 位元組。讀不到的圖略過（生物照樣能玩，只是沒有那張圖）
static func read_images(design: CreatureDesign) -> Dictionary:
	var images: Dictionary = {}
	for file: String in image_files(design):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(design.image_path(file))
		if not bytes.is_empty():
			images[file] = bytes
	return images


## 位元組 → KB（四捨五入，顯示用）
static func kb(bytes: int) -> int:
	return roundi(bytes / 1024.0)


## 圖加起來多大（位元組）
static func total_bytes(images: Dictionary) -> int:
	var total: int = 0
	for file: String in images:
		total += (images[file] as PackedByteArray).size()
	return total


## 圖太大時要縮成多大：0 是不用縮；-1 是縮到最小還是太大（圖太多張）；其他是長邊要縮成幾像素
static func shrink_side_needed(images: Dictionary) -> int:
	if total_bytes(images) <= MAX_IMAGE_BYTES:
		return 0
	for side: int in SHRINK_SIDES:
		if total_bytes(shrink_images(images, side)) <= MAX_IMAGE_BYTES:
			return side
	return -1


## 把每張圖的長邊縮到 side 像素以內（本來就比較小的不動），回傳新的一份（原本的不改）
static func shrink_images(images: Dictionary, side: int) -> Dictionary:
	var result: Dictionary = {}
	for file: String in images:
		var image := Image.new()
		if image.load_png_from_buffer(images[file]) != OK:
			continue
		var longest: int = maxi(image.get_width(), image.get_height())
		if longest > side:
			var k: float = float(side) / longest
			image.resize(maxi(roundi(image.get_width() * k), 1), maxi(roundi(image.get_height() * k), 1), Image.INTERPOLATE_LANCZOS)
		result[file] = image.save_png_to_buffer()
	return result


## 打包要傳給主機的資料
static func build(player_name: String, design: CreatureDesign, images: Dictionary) -> Dictionary:
	return {
		"version": VERSION,
		"player_name": clean_name(player_name),
		"design": design.to_dict(),
		"images": images,
	}


## 名稱：去掉前後空白、最多 MAX_NAME 個字、不能換行
static func clean_name(text: String) -> String:
	return text.strip_edges().replace("\n", " ").left(MAX_NAME)


## 主機檢查收到的資料：回傳空字串是沒問題，不然回傳要告訴對方的原因（中文）
static func check(data: Variant, balance: CreatureBalance) -> String:
	if not data is Dictionary:
		return "資料格式不對"
	var packet: Dictionary = data
	if not packet.get("version") is int or packet.version != VERSION:  # 型別不同的值不能直接比（會出錯），先確認是整數
		return "版本不一樣：請跟主機用同一版的專案（git pull）"
	if var_to_bytes(packet).size() > MAX_PACKET_BYTES:
		return "資料太大了（上限 %d KB）" % kb(MAX_PACKET_BYTES)
	if not packet.get("player_name") is String or not packet.get("design") is Dictionary or not packet.get("images") is Dictionary:
		return "資料格式不對"
	var design: CreatureDesign = CreatureDesign.from_data(packet.design)
	var used: PackedStringArray = image_files(design)
	var images: Dictionary = packet.images
	var total: int = 0
	for file: Variant in images:
		if not file is String or not used.has(file):
			return "有設計檔沒用到的圖"
		if not images[file] is PackedByteArray:
			return "圖的格式不對：%s" % file
		var bytes: PackedByteArray = images[file]
		total += bytes.size()
		var image := Image.new()
		if not is_png(bytes) or image.load_png_from_buffer(bytes) != OK:
			return "讀不到這張圖：%s" % file
		if image.get_width() > MAX_IMAGE_SIDE or image.get_height() > MAX_IMAGE_SIDE:
			return "圖太大了：%s（最大 %d × %d）" % [file, MAX_IMAGE_SIDE, MAX_IMAGE_SIDE]
	if total > MAX_IMAGE_BYTES:
		return "圖加起來太大了（上限 %d KB）" % kb(MAX_IMAGE_BYTES)
	var complexity: int = CreatureStats.complexity_of(design, balance)
	if complexity > balance.max_complexity:
		return "這隻生物太複雜了（複雜度 %d，上限 %d）" % [complexity, balance.max_complexity]
	return ""


## 開頭是不是 PNG 的記號（不是的話不用讀，省得印一堆錯誤）
static func is_png(bytes: PackedByteArray) -> bool:
	return bytes.size() > 8 and bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])


## 收到的人還原設計檔：from_dict() 逐欄檢查，圖讀成 Texture2D 放進 image_cache（讀不到的略過）。
## 先用 check() 檢查過再呼叫
static func unpack_design(packet: Dictionary) -> CreatureDesign:
	var design: CreatureDesign = CreatureDesign.from_data(packet.get("design", {}) if packet.get("design") is Dictionary else {})
	var images: Variant = packet.get("images")
	if images is Dictionary:
		for file: Variant in images:
			var image := Image.new()
			if file is String and images[file] is PackedByteArray and is_png(images[file]) and image.load_png_from_buffer(images[file]) == OK:
				design.image_cache[file] = ImageTexture.create_from_image(image)
	return design
