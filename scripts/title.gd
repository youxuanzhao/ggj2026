extends Node2D

@onready var options: Array[Label] = [$Option1,$Option2]

@onready var title_white: Label = $TitleWhite
@onready var title_black: Label = $TitleBlack

var selected = 0;

func _process(delta: float) -> void:
	
	if Input.is_action_just_pressed("ui_down"):
		print(options[selected].text)
		options[selected].text = options[selected].text.trim_prefix("> ")
		selected += 1;
		if selected > 1:
			selected = 0
		options[selected].text = options[selected].text.insert(0, "> ")
	
	if Input.is_action_just_pressed("ui_up"):
		options[selected].text = options[selected].text.trim_prefix("> ")
		selected -= 1;
		if selected < 0:
			selected = 1
		options[selected].text = options[selected].text.insert(0, "> ")
	
	if Input.is_action_just_pressed("ui_accept"):
		if selected == 0:
			var tween = get_tree().create_tween()
			tween.tween_property(title_black,"position", title_white.position, 1.0)
			tween.tween_callback(transit_to_level_1)	

func transit_to_level_1() -> void:
	pass
	
