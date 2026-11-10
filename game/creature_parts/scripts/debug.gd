class_name CreatureDebug
extends Node
## 顯示骨架的全域開關（autoload，名稱是 Debug，在「專案設定 → 全域」裡）。
## 程式裡用 Debug.show_bones 讀或改；零件畫圖時用 CreatureDebug.bones_visible(self)，編輯器裡也不會出錯。
## 遊戲中按 F1 切換。打開時，每個生物零件會多畫骨架線、關節點和輔助線（橘色），
## 配色跟網頁版互動示範一樣。

## 骨架和輔助線的顏色
const BONE_COLOR: Color = Color("#f2b766")

## 現在要不要顯示骨架
var show_bones: bool = false


func _ready() -> void:
	# 遊戲暫停時也要能切換
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F1:
		show_bones = not show_bones
		get_viewport().set_input_as_handled()


## 零件在 _draw() 裡用這個判斷要不要畫骨架。編輯器裡沒有 Debug 節點，一律不畫
static func bones_visible(node: Node) -> bool:
	if Engine.is_editor_hint() or not node.is_inside_tree():
		return false
	var debug: Node = node.get_tree().root.get_node_or_null("Debug")
	return debug != null and bool(debug.get("show_bones"))
