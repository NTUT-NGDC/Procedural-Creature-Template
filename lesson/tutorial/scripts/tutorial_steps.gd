class_name TutorialSteps
extends Resource
## 教學關 10 個步驟的文字。實際內容寫在 lesson/tutorial/data/tutorial_steps.tres。
##
## 想改文字：在 Godot 的檔案系統面板點兩下 tutorial_steps.tres，
## 在右邊的檢查器展開 Steps，點開每一步改 Title、Description、Hint。
## 步驟的順序和數量不要改，檢查邏輯是照這個順序對應的。

## 10 個步驟，順序：複製範例生物、改身體、加腳、加觸手或尾巴、做自己的池塘、接上標題玩到結算，
## 最後 4 個是額外題：自己的天敵、觸手抓食物、寫一點程式、加一個掛件
@export var steps: Array[TutorialStep] = []
