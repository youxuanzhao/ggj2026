extends Node2D

@onready var logic = GameLogic

func _ready() -> void:
	logic.load_level_from_resource(load("res://assets/levels/level_1.tres"))
