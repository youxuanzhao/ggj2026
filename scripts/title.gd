extends Node2D

@onready var options: Array[Label] = [$VBoxContainer/Option1,$VBoxContainer/Option2,$VBoxContainer/Option3]

@onready var title_white: Label = $TitleWhite
@onready var title_black: Label = $TitleBlack

var selected = 0;

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("down"):
		print(options[selected].text)
		options[selected].text = options[selected].text.trim_prefix("> ")
		selected += 1;
		if selected > 2:
			selected = 0
		options[selected].text = options[selected].text.insert(0, "> ")
	
	if Input.is_action_just_pressed("up"):
		options[selected].text = options[selected].text.trim_prefix("> ")
		selected -= 1;
		if selected < 0:
			selected = 2
		options[selected].text = options[selected].text.insert(0, "> ")
	
	if Input.is_action_just_pressed("space"):
		if selected == 0:
			transit_to_game()
		elif selected == 1:
			transit_to_editor()
		elif selected == 2:
			transit_to_credit() 

func transit_to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	
func transit_to_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/game_editor.tscn")
	
func transit_to_credit() -> void:
	pass
