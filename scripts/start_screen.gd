extends Control
## Title screen for Ferret Casino Royale. One button: start the game.

func _ready() -> void:
	$Center/VBox/StartButton.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
