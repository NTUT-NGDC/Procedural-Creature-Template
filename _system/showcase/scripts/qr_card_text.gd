class_name QrCardText
extends Resource
## 輪播最後一張「報名 QR Code」的文字。資料檔不放在專案裡，在外層 repo 的 docs/promo/qr_card/qr_card.tres。
## 改了網址要重跑 docs/promo/make_qr.py 產生新的 QR Code，再重拍圖。

## 色帶上的小字
@export var club_line: String = "北科遊戲研究社｜交流會"
## 大標題
@export var title: String = "每週四，一起來做遊戲！"
## QR Code 下面的說明
@export var form_label: String = "非社員報名表單"
## 報名表單的網址（QR Code 指向這裡；make_qr.py 也讀這一行）
@export var url: String = ""
## 卡片上顯示的網址（掃不到的人手動輸入）。空的就顯示 url 拿掉 https:// 的樣子
@export var shown_url: String = ""
