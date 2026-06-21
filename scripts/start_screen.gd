extends Control
## Title screen for Ferret Casino Royale. One button: start the game.

const START_SCREEN_MUSIC = preload("res://assets/start-screen-music.mp3")
const START_CLICK_STING = preload("res://assets/start-click-sting.mp3")
const START_SCREEN_VOLUME_DB := -8.0
const START_SCREEN_MUTED_DB := -40.0
const START_CLICK_VOLUME_DB := -6.0

var music_player: AudioStreamPlayer
var start_sting_player: AudioStreamPlayer
var starting := false
var intro_finished := false
var throb_time := 0.0
var throb_active := false

func _ready() -> void:
	_build_music_player()
	_build_start_sting_player()
	$StartButton.pressed.connect(_on_start_pressed)
	$StartButton.disabled = true
	$PressAnyKey.visible = false
	_play_start_intro()

func _on_start_pressed() -> void:
	if starting or not intro_finished:
		return
	starting = true
	$StartButton.disabled = true
	$BlackCover.visible = true
	_fade_out_music()
	_fade_out_prompt()
	_play_start_sting()
	var black_tween := create_tween()
	black_tween.tween_property($BlackCover, "modulate:a", 1.0, 0.45)
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _start_prompt_pulse() -> void:
	var prompt := $PressAnyKey
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(prompt, "modulate:a", 0.35, 0.9)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.9)

func _fade_out_prompt() -> void:
	var tween := create_tween()
	tween.tween_property($PressAnyKey, "modulate:a", 0.0, 0.4)

func _build_music_player() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.stream = START_SCREEN_MUSIC
	music_player.autoplay = false
	music_player.volume_db = START_SCREEN_VOLUME_DB
	add_child(music_player)
	if music_player.stream is AudioStreamMP3:
		(music_player.stream as AudioStreamMP3).loop = true
	music_player.play()

func _build_start_sting_player() -> void:
	start_sting_player = AudioStreamPlayer.new()
	start_sting_player.stream = START_CLICK_STING
	start_sting_player.autoplay = false
	start_sting_player.volume_db = START_CLICK_VOLUME_DB
	add_child(start_sting_player)

func _fade_out_music() -> void:
	if music_player == null or not music_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(music_player, "volume_db", START_SCREEN_MUTED_DB, 0.8)
	await tween.finished
	music_player.stop()

func _play_start_sting() -> void:
	if start_sting_player == null:
		return
	start_sting_player.volume_db = START_CLICK_VOLUME_DB
	start_sting_player.play()
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(start_sting_player, "volume_db", START_SCREEN_MUTED_DB, 0.8)
	tween.tween_callback(func(): start_sting_player.stop())

func _process(delta: float) -> void:
	if not throb_active or starting:
		return
	throb_time += delta
	var bg := $Background
	var x_wave := sin(throb_time * 2.7) + 0.45 * sin(throb_time * 5.1 + 1.1)
	var y_wave := sin(throb_time * 2.2 + 0.8) + 0.35 * sin(throb_time * 4.7 + 2.4)
	var zoom_wave := sin(throb_time * 1.8 + 0.4)
	var tilt_wave := sin(throb_time * 2.35 + 1.7) + 0.25 * sin(throb_time * 4.3)
	var scale_amount := 1.02 + 0.03 * (zoom_wave * 0.5 + 0.5)
	bg.scale = Vector2(scale_amount, scale_amount)
	bg.position = Vector2(x_wave * -10.0, y_wave * -7.0)
	bg.rotation_degrees = tilt_wave * 0.45

func _play_start_intro() -> void:
	await get_tree().create_timer(5.0).timeout
	_start_background_throb()
	$PressAnyKey.visible = true
	_start_prompt_pulse()
	var tween := create_tween()
	tween.tween_property($BlackCover, "modulate:a", 0.0, 1.2)
	await tween.finished
	$BlackCover.visible = false
	$StartButton.disabled = false
	intro_finished = true

func _start_background_throb() -> void:
	var bg := $Background
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.pivot_offset = bg.size * 0.5
	bg.scale = Vector2.ONE
	bg.position = Vector2.ZERO
	bg.rotation_degrees = 0.0
	throb_time = 0.0
	throb_active = true
