class_name ShowcaseStoryboard
extends Resource
## IG 宣傳影片的劇本：每一段幾秒開始、字幕寫什麼、有哪些生物。
## 改 data/storyboard.tres 就好，不用改程式。秒數都是從影片開頭算。

@export_group("秒數")
## 一群生物在游，主角（龍）從中間游過
@export_range(0, 60, 0.1) var swim_start: float = 0.0
## 看不見的目標點在畫面裡繞，大家一起追
@export_range(0, 60, 0.1) var chase_start: float = 4.0
## 切成骨架＋第一句字幕
@export_range(0, 60, 0.1) var bones_start: float = 6.0
## 切回原本的樣子＋第二句字幕
@export_range(0, 60, 0.1) var bones_end: float = 9.0
## 結尾畫面（變暗＋三行字）
@export_range(0, 60, 0.1) var ending_start: float = 12.0
## 影片總長
@export_range(1, 60, 0.1) var total: float = 15.0

@export_group("橫幅")
## 最上面橘色色帶上的字（跟輪播最後一張一樣），整段影片都在、不會淡入淡出
@export var banner_text: String = "北科遊戲研究社｜交流會"
## 色帶下面那行小字（時間和主題）。空的就不畫
@export var banner_subtitle: String = "11/19（四）程序化動畫"

@export_group("字幕")
## 骨架那段的字幕
@export var caption_bones: String = "這些動畫，沒有一格是畫的"
## 切回來那段的字幕
@export var caption_rules: String = "只靠幾條規則，每一幀算出來"
## 結尾的字（一行一句）
@export var ending_lines: PackedStringArray = ["11/19（四）19:00｜做一隻自己的生物", "北科遊戲研究社・每週交流會", "不用會寫程式・非社員也歡迎"]
## 字幕的字級（俐方體用 11 的倍數最清楚）
@export_range(11, 88, 11) var caption_size: int = 44
## 結尾第一行的字級
@export_range(11, 88, 11) var ending_title_size: int = 44
## 結尾其他行的字級
@export_range(11, 88, 11) var ending_size: int = 33
## 字幕放在畫面高度的哪裡（0 是最上面、1 是最下面）
@export_range(0, 1, 0.01) var caption_y: float = 0.22
## 字幕淡入淡出要幾秒
@export_range(0, 2, 0.05) var fade_time: float = 0.3
## 結尾畫面變多暗（0 不變暗、1 全黑）
@export_range(0, 1, 0.05) var ending_dim: float = 0.6

## 封面截圖在第幾秒拍（跑 -- shots 時用）
@export_range(0, 60, 0.1) var shot_time: float = 3.0

@export_group("目標點")
## 目標點繞圈的半徑（0～1，畫面的比例）
@export var chase_radius: Vector2 = Vector2(0.3, 0.25)
## 目標點繞一圈要幾秒
@export_range(0.5, 20, 0.1) var chase_period: float = 3.0
## 每隻追的位置在目標點旁邊錯開多遠（0～1，畫面寬度的比例）：0 是全部追同一點，會擠成一團
@export_range(0, 0.5, 0.01) var chase_spread: float = 0.16
## 追目標時，速度是原本的幾倍
@export_range(0.5, 3, 0.05) var chase_speed_scale: float = 1.4

@export_group("飼料")
## 餵食點（0～1，畫面的比例）：飼料會飄在這附近，被吃掉就再補一顆
@export var feed_spots: PackedVector2Array = [Vector2(0.27, 0.3), Vector2(0.7, 0.62)]
## 每個餵食點隨時有幾顆飼料
@export_range(0, 20, 1) var food_per_spot: int = 5
## 被吃掉之後，隔幾秒才補一顆（越短吃得越多、長得越快）
@export_range(0, 10, 0.1) var food_refill_time: float = 1.5
## 整個畫面隨機撒的飼料，隨時有幾顆（跟餵食點的分開算）
@export_range(0, 100, 1) var scatter_food: int = 24
## 隨機撒的飼料被吃掉之後，隔幾秒補一顆
@export_range(0, 10, 0.1) var scatter_refill_time: float = 0.3
## 飼料是大顆的機率（大顆比較大、吃了算好幾顆）
@export_range(0, 1, 0.05) var big_food_chance: float = 0.3
## 飼料散開多遠（0～1，畫面寬度的比例）
@export_range(0, 0.5, 0.01) var food_spread: float = 0.12
## 吃飼料的生物，離開餵食點多遠就回頭（0～1，畫面寬度的比例）
@export_range(0, 0.5, 0.01) var feed_range: float = 0.2

@export_group("保持距離")
## 離別隻的身體多近就開始閃開（像素）
@export_range(0, 400, 5) var personal_space: float = 120.0
## 閃開的力道：越大越不會靠近，太大會一直躲、游不到目標
@export_range(0, 5, 0.1) var avoid_strength: float = 1.5

@export_group("生物")
## 演員：每一隻生物
@export var actors: Array[ShowcaseActor] = []
## 鏡頭放大幾倍（生物在手機上才看得清楚）
@export_range(0.5, 3, 0.05) var zoom: float = 1.25
## 水流強度
@export_range(0, 200, 1) var flow_strength: float = 25.0
