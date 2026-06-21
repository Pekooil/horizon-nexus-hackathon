extends Control
## Title screen for Ferret Casino Royale. One button: start the game.

func _ready() -> void:
	$StartButton.pressed.connect(_on_start_pressed)
	_start_prompt_pulse()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _start_prompt_pulse() -> void:
	var prompt := $PressAnyKey
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(prompt, "modulate:a", 0.35, 0.9)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.9)
