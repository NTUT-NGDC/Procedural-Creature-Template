@tool
class_name WorkshopLabels
extends Resource
## 生物工坊的文字：每個欄位的中文名稱、滑鼠移上去的說明。
## 設計檔加了新欄位，就在這裡加上它的名字（沒有的話工坊會直接顯示英文欄位名稱）。
## 資料在 lesson/workshop/data/workshop_labels.tres。

## 欄位名稱 → 中文名稱
@export var names: Dictionary = {}
## 欄位名稱 → 說明（滑鼠移到控制項上時顯示）
@export var hints: Dictionary = {}
## 三種長大方式的說明，順序跟「長大方式」選單一樣
@export_multiline var growth_help: PackedStringArray = []


## 欄位的中文名稱，沒有就用欄位名稱
func name_of(field: String) -> String:
	return names.get(field, field)


func hint_of(field: String) -> String:
	return hints.get(field, "")
