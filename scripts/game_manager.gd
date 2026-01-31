extends Node2D

var logic = GameLogic

func _init() -> void:
	logic.load_level_from_resource(load("res://assets/levels/level1.tres"))

func _ready():
	logic.load_level_from_resource(load("res://assets/levels/level1.tres"))
