extends Node2D
@onready var menu_effect: ColorRect = $CanvasLayer/MenuEffect
@onready var menu: VBoxContainer = $CanvasLayer/Menu
@onready var back_btn: Button = $CanvasLayer/Menu/BackBtn
@onready var exit_btn: Button = $CanvasLayer/Menu/ExitBtn

func _ready() -> void:
	
	menu.visible = false
	menu_effect.visible = false
	
	back_btn.pressed.connect(_on_back_btn_pressed)
	exit_btn.pressed.connect(_on_exit_btn_pressed)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("escape"):
		menu.visible = !menu.visible
		menu_effect.visible = !menu_effect.visible

func _on_back_btn_pressed() -> void:
	menu.visible = false
	menu_effect.visible = false
	ClickPlay.play_click()

func _on_exit_btn_pressed() -> void:
	ClickPlay.play_click()
	get_tree().change_scene_to_file("res://scenes/title.tscn")
