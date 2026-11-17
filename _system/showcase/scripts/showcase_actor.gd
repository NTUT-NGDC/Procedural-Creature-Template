class_name ShowcaseActor
extends Resource
## 展示場景裡的一隻生物：用哪份設計檔、換什麼顏色、多大、在影片裡做什麼。
## 在 data/storyboard.tres 的「演員」清單裡改。

## 角色的編號，跟下面「角色」選單的順序一樣
enum Role { LANE, PASS, FEED }

## 設計檔（用範例生物就好，不會改到原本的檔案）
@export var design: CreatureDesign
## 換身體的顏色：透明（A＝0）就是用原本的顏色
@export var body_color: Color = Color(0, 0, 0, 0)
## 一開始幾級（越高越大）。吃到飼料還會再長大
@export_range(0, 30, 1) var level: int = 0
## 主角：一開始從左邊游過畫面中間（龍），之後照「角色」做
@export var is_star: bool = false
## 在影片裡做什麼：繞圈＝在畫面裡繞；游過去＝從一邊游到另一邊，出畫面再從另一邊出來；吃飼料＝在餵食點附近找飼料吃
@export_enum("繞圈", "游過去", "吃飼料") var role: int = Role.LANE
## 游的速度是原本的幾倍
@export_range(0.2, 3, 0.05) var speed_scale: float = 1.0

@export_group("繞圈")
## 繞圈的中心（0～1，畫面的比例：0.5, 0.5 是正中間）
@export var lane_center: Vector2 = Vector2(0.5, 0.5)
## 繞圈的半徑（0～1，畫面的比例）
@export var lane_radius: Vector2 = Vector2(0.3, 0.2)
## 反方向繞（打勾是逆時針）
@export var lane_reverse: bool = false
## 從圈上的哪裡開始（0～1，0 是最右邊，順時針轉）
@export_range(0, 1, 0.01) var lane_phase: float = 0.0

@export_group("游過去")
## 在畫面的哪個高度游過去（0 是最上面、1 是最下面）
@export_range(0, 1, 0.01) var pass_height: float = 0.5
## 從右邊游到左邊（沒打勾是左到右）
@export var pass_from_right: bool = false
## 一開始游到哪裡了（0 是剛要進畫面，1 是剛出畫面）
@export_range(0, 1, 0.01) var pass_offset: float = 0.0

@export_group("吃飼料")
## 在第幾個餵食點吃（劇本的「餵食點」清單，從 0 算）
@export_range(0, 9, 1) var feed_spot: int = 0
