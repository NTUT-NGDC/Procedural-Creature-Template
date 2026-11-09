class_name TutorialStep
extends Resource
## 教學關一個步驟要顯示的文字。實際內容寫在 lesson/tutorial/data/tutorial_steps.tres。

## 步驟標題，例如「1. 複製一隻範例生物」
@export var title: String = ""
## 這一步要做什麼
@export_multiline var description: String = ""
## 卡住時的提示：在 Godot 編輯器的哪裡、改哪個屬性
@export_multiline var hint: String = ""
