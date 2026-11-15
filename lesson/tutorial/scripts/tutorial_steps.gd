class_name TutorialSteps
extends Resource
## 工坊教學步驟的文字。實際內容寫在 lesson/tutorial/data/tutorial_steps.tres。
##
## 想改文字：在 Godot 的檔案系統面板點兩下 tutorial_steps.tres，
## 在右邊的檢查器展開 Steps，點開每一步改 Title、Description、Hint、Done Text。
## 步驟的順序和數量不要改，檢查邏輯（scripts/tutorial_checker.gd）是照這個順序對應的。

## 9 個步驟，順序：取名字、把身體折斷、改出自己的身體、觸手跟不上、腳打直腳亂走、存檔，
## 最後 3 個是額外題：看它長大、會動的掛件、自己畫的圖
@export var steps: Array[TutorialStep] = []
