extends Node2D

@onready var options: Array[Label] = [$VBoxContainer/Option1,$VBoxContainer/Option2,$VBoxContainer/Option3]

@onready var title_white: Label = $TitleWhite
@onready var title_black: Label = $TitleBlack

@onready var black_rect: ColorRect = $CanvasLayer/BlackRect

@onready var logic = GameLogic

var selected = 0;

func _ready() -> void:
	logic.load_level_from_resource(preload("res://assets/levels/title.tres"))

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("down"):
		print(options[selected].text)
		ClickPlay.play_click()
		options[selected].text = options[selected].text.trim_prefix("> ")
		selected += 1;
		if selected > 2:
			selected = 0
		options[selected].text = options[selected].text.insert(0, "> ")
	
	if Input.is_action_just_pressed("up"):
		ClickPlay.play_click()
		options[selected].text = options[selected].text.trim_prefix("> ")
		selected -= 1;
		if selected < 0:
			selected = 2
		options[selected].text = options[selected].text.insert(0, "> ")
	
	if Input.is_action_just_pressed("space"):
		ClickPlay.play_click()
		if selected == 0:
			transit_to_game()
		elif selected == 1:
			transit_to_editor()
		elif selected == 2:
			transit_to_credit() 

func transit_to_game() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(black_rect,"color",Color.BLACK, 1.0)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	
func transit_to_editor() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(black_rect,"color",Color.BLACK, 1.0)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/game_editor.tscn")
	
func transit_to_credit() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(black_rect,"color",Color.BLACK, 1.0)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/credit.tscn")
