@tool
class_name WaterFlow
extends RefCounted
## 水流場：「這個位置、這個時間，水往哪個方向流、流多快」。
## 生物、觸手、掛件的彈簧、水草、海葵、飼料都讀同一個水流，整缸才會一起晃。
##
## 用法：WaterFlow.at(位置) 回傳水流的速度（像素／秒）。
## 強度等設定由生態缸（或工坊）設定；強度 0 就是靜水（編輯器裡、沙盒都是 0）。

## 強度（像素／秒）：水流最快多快，0 是靜水
static var strength: float = 0.0
## 波的大小（像素）：越大，一大片的水往同一個方向流；越小越亂
static var wave_size: float = 300.0
## 變化速度：水流方向變得多快
static var speed: float = 0.6


## 水流：兩組正弦波疊起來。左右的流跟著高度變、上下的流跟著左右位置變，
## 再隨著時間慢慢移動，看起來就像一團一團打轉的水
static func at(point: Vector2, time: float = now()) -> Vector2:
	if strength <= 0.0:
		return Vector2.ZERO
	var x: float = point.x / wave_size
	var y: float = point.y / wave_size
	var t: float = time * speed
	var flow := Vector2(
		sin(y * 1.7 + t) + 0.5 * sin(y * 3.1 - t * 1.3),  # 左右：跟著高度變
		0.6 * cos(x * 1.3 - t * 0.8) + 0.3 * sin(x * 2.9 + t))  # 上下：跟著左右位置變
	return flow / 1.5 * strength  # 兩個波加起來最大約 1.5，除掉讓「強度」就是最快的速度


## 現在的時間（秒）
static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 把設定改回靜水（離開生態缸、工坊時用）
static func reset() -> void:
	strength = 0.0
	wave_size = 300.0
	speed = 0.6
