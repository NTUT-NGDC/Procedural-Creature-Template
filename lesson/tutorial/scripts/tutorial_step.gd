class_name TutorialStep
extends Resource
## 教學步驟一步要顯示的文字。實際內容寫在 lesson/tutorial/data/tutorial_steps.tres。

## 步驟標題，例如「2. 把身體折斷（鏈條跟隨）」
@export var title: String = ""
## 這一步要做什麼
@export_multiline var description: String = ""
## 卡住時的提示：在工坊的哪裡、改哪個控制項
@export_multiline var hint: String = ""
## 過關時顯示：這一步看到的原理是什麼
@export_multiline var done_text: String = ""
