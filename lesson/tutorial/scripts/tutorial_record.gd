class_name TutorialRecord
extends RefCounted
## 教學步驟的「實驗紀錄」：這次打開工坊之後，社員曾經把滑桿拉到哪裡。
##
## 實驗步驟是「先弄壞、看它壞掉，再修好」：只看現在的設計檔，分不出「沒試過」和「試過又修好」，
## 所以把拉到過的極端值記在這裡，檢查（tutorial_checker.gd）同時看設計檔和這份紀錄。
## 只記在記憶體裡，關掉工坊就清空。

## 一開始的設計檔（讀檔或按「新的」那一刻），用來比較「改了哪些」
var start: Dictionary = {}
## 身體的「最大彎曲角」最大拉到過幾度（弧度）
var max_bend_seen: float = 0.0
## 觸手的「FABRIK 次數」最小調到過幾次
var min_iterations_seen: int = 99
## 腳的「落腳距離」最大拉到過多少
var max_rest_distance_seen: float = 0.0
## 有沒有試過「2 組以上的腳全部同一組」
var same_group_seen: bool = false
## 「預覽等級」最大拉到過幾級
var max_level_seen: int = 0
## 最後一次存檔時的設計檔（還沒存過是空的）
var saved: Dictionary = {}


## 讀了一隻生物（或按「新的」）：記下起點。拉到過的值不清掉，做過的實驗還算數
func open(design: CreatureDesign) -> void:
	start = design.to_dict()


## 設計檔改了：更新拉到過的極端值
func observe(design: CreatureDesign) -> void:
	max_bend_seen = maxf(max_bend_seen, design.body.max_bend)
	for tentacle: TentacleDesign in design.tentacles:
		min_iterations_seen = mini(min_iterations_seen, tentacle.iterations)
	for leg: LegDesign in design.legs:
		max_rest_distance_seen = maxf(max_rest_distance_seen, leg.rest_distance)
	if design.legs.size() >= 2 and TutorialChecker.leg_groups(design).size() == 1:
		same_group_seen = true


func observe_level(level: int) -> void:
	max_level_seen = maxi(max_level_seen, level)


func mark_saved(design: CreatureDesign) -> void:
	saved = design.to_dict()
