extends Node2D
## 沙盒用的簡單食物：一個黃色圓點，在 "food" 群組裡。被吃掉就消失。
## （生態缸的正式飼料在 game/tank/scripts/food.gd）

const RADIUS: float = 6.0


func _ready() -> void:
	add_to_group("food")


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS * 1.8, Color(1.0, 0.85, 0.3, 0.2), true, -1.0, true)
	draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.85, 0.3), true, -1.0, true)


## Creature.eat() 會呼叫這個
func on_eaten(_creature: Creature) -> void:
	queue_free()
