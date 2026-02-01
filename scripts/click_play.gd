extends Node

@onready var click_player = $AudioStreamPlayer
@onready var beep_player = $AudioStreamPlayer2

func play_click():
	click_player.play()

func play_beep():
	beep_player.play()
