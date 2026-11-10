extends Node


func _ready() -> void:
	(get_parent() as Creature).grew.connect(_on_grew)


func _on_grew(_level: int) -> void:
	pass
