extends Node
## 進階挑戰：接生物的 grew 訊號，讓生物長大的時候做點效果。
##
## 運作方式：
## 1. 這個節點（GrowEffect）放在生物底下，生物是它的父節點
## 2. 點最上層的生物節點 → 右邊切到「節點」分頁 → 「訊號」→ 雙擊 grew(level) → 選 GrowEffect → 連接
##    （這個範例已經連好了：grew 旁邊有綠色的連接圖示）
## 3. 生物每長大一級，就會呼叫 _on_creature_grew()，level 是長大後的等級
##
## 範例效果：每升 5 級，身體換一個顏色。
## （生物長大時會照設計檔重新擺好身體，顏色會變回設計檔的，所以每一級都要重新塗一次）
##
## 挑戰：試著做自己的效果！例如：
##   ・長大時眼睛變大一點（改 Eyes 的 size）
##   ・升到 10 級換花紋（改 ChainBody 的 pattern）
##   ・每升 5 級，翅膀拍得更快（改 Ornament 的 flap_speed）
##
## 測試：直接執行這個場景（F6），按空白鍵就會長大一級。
## 生態缸只讀設計檔、不會執行生物身上的腳本（連線時才不會跑到別人的程式），所以這個挑戰在這個場景裡玩。

## 輪流換的顏色
const COLORS: Array[Color] = [Color("#4f9d69"), Color("#e67e22"), Color("#9b59b6"), Color("#3498db"), Color("#e74c3c")]

## 這個節點的父節點就是生物
@onready var _creature: Creature = get_parent() as Creature


## 生物長大時會呼叫這裡（在編輯器的「節點」分頁連接的）
func _on_creature_grew(level: int) -> void:
	var body: ChainBody = _creature.get_body()
	if body == null:
		return
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0])
	gradient.colors = PackedColorArray([COLORS[floori(level / 5.0) % COLORS.size()]])  # 0～4 級第 1 個顏色、5～9 級第 2 個……
	body.body_gradient = gradient


## 測試用：直接執行這個場景時，按空白鍵長大一級
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().current_scene == _creature and event.is_action_pressed("ui_accept"):
		_creature.grow(1)
