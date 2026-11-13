class_name CardDeck
extends Resource
## 抽卡用的卡牌內容。實際的卡牌寫在 lesson/card_draw/data/card_deck.tres。
##
## 想改卡牌：在 Godot 的檔案系統面板點兩下 card_deck.tres，
## 在右邊的檢查器裡改三個文字框，一行就是一張卡。空白行會被略過。

## 身體卡（要組出什麼生物），一行一張
@export_multiline var bodies: String = ""
## 棲地卡（生態缸要布置成什麼地方），一行一張
@export_multiline var habitats: String = ""
## 規則卡（要改哪一條遊戲規則），一行一張。行首加 ★ 的是進階卡（要寫一點程式）
@export_multiline var rules: String = ""


## 把「一行一張」的文字拆成卡牌清單：去掉每行前後的空白，略過空白行
static func split_cards(text: String) -> PackedStringArray:
	var cards: PackedStringArray = []
	for line: String in text.split("\n"):
		var card: String = line.strip_edges()
		if card != "":
			cards.append(card)
	return cards
