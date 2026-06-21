extends Control
## Root scene. Builds the 6 live camera feeds, the monitor wall, the click-to-zoom
## detail view with the Polaroid catch mechanic, the HUD, and win/lose overlay.

const ROOM_COUNT := 6
const FEED_RENDER_SIZE := Vector2i(960, 540)
const ROOM_BASE_SIZE := Vector2(480.0, 270.0)
const ROOM_SCENES: Array[PackedScene] = [
	preload("res://scenes/Rooms/Entrance.tscn"),
	preload("res://scenes/Rooms/Bar.tscn"),
	preload("res://scenes/Rooms/Lounge.tscn"),
	preload("res://scenes/Rooms/Poker.tscn"),
	preload("res://scenes/Rooms/Roulette.tscn"),
	preload("res://scenes/Rooms/Slot Machines.tscn"),
]
const ROOM_NAMES := ["Entrance", "Bar", "Lounge", "Poker", "Roulette", "Slot Machines"]
const SCREEN_TO_ROOM := [0, 4, 3, 2, 1, 5]
# Map of the casino floor, indexed the same as ROOM_NAMES/ROOM_SCENES:
# Entrance -> Bar -> {Lounge, Poker, Roulette}, with Poker/Roulette also
# linked to each other via the Slot Machines room.
const ROOM_GRAPH := {
	0: [1],          # Entrance -> Bar
	1: [0, 2, 3, 4],  # Bar -> Entrance, Lounge, Poker, Roulette
	2: [1],          # Lounge -> Bar
	3: [1, 5],       # Poker -> Bar, Slot Machines
	4: [1, 5],       # Roulette -> Bar, Slot Machines
	5: [3, 4],       # Slot Machines -> Poker, Roulette
}
const ENTRANCE_ROOM := 0
const MonitorQuad = preload("res://scripts/monitor_quad.gd")
const CHUNKY_FONT = preload("res://assets/ChunkyRetro-6YmnD.otf")
const MANROPE_FONT = preload("res://assets/fonts/Manrope-Medium.ttf")
const POLAROID_TEXTURE = preload("res://assets/polaroid.png")
const FILM_TEXTURE = preload("res://assets/film.png")
const MONEY_SYMBOL_TEXTURE := preload("res://assets/money_digits/money.png")
const MONEY_DOT_TEXTURE := preload("res://assets/money_digits/dot.png")
const MONEY_DIGIT_TEXTURES := {
	"0": preload("res://assets/money_digits/0.png"),
	"1": preload("res://assets/money_digits/1.png"),
	"2": preload("res://assets/money_digits/2.png"),
	"3": preload("res://assets/money_digits/3.png"),
	"4": preload("res://assets/money_digits/4.png"),
	"5": preload("res://assets/money_digits/5.png"),
	"6": preload("res://assets/money_digits/6.png"),
	"7": preload("res://assets/money_digits/7.png"),
	"8": preload("res://assets/money_digits/8.png"),
	"9": preload("res://assets/money_digits/9.png"),
}

# Monitor-wall nodes that live in Main.tscn (edit them in the editor):
@onready var monitor_screen: Control = $MonitorScreen
@onready var screen_layout: Node2D = $MonitorScreen/WallCenter/ScreenLayout
@onready var money_display: HBoxContainer = $MonitorScreen/Money
@onready var night_label: Label = $MonitorScreen/TopBar/Night
@onready var clock_label: Label = $MonitorScreen/TopBar/Clock
@onready var photos_label: Label = $MonitorScreen/TopBar/Photos
@onready var film_row: Control = $MonitorScreen/FilmRow
@onready var clock_hour_hand: Sprite2D = $MonitorScreen/ClockArt/HourHand
@onready var clock_minute_hand: Sprite2D = $MonitorScreen/ClockArt/MinuteHand

var feeds: Array[SubViewport] = []   # the off-screen render targets (textures)
var rooms: Array[Room] = []          # the editable room contents (game logic)
var characters: Array[Dictionary] = []   # roster: {id, room (-1 = queued), seat}

# Popups still built in code (modal UI, not part of the main screen):
var detail_view: Control
var detail_texture: TextureRect
var detail_label: Label
var photo_btn: Button
var banner: Label
var flash: ColorRect
var overlay: Control
var overlay_label: Label

var money_sprites: Array[TextureRect] = []
var film_sprites: Array[TextureRect] = []
var film_base_positions: Array[Vector2] = []
var intro_overlay: Control
var intro_day_card: Control
var intro_day_label: Label
var intro_instruction_card: CenterContainer
var intro_instruction_label: Label
var intro_day_films: Array[TextureRect] = []
var intro_sequence_running := false
var has_shown_first_time_instructions := false
var map_panel: Control
var map_buttons := {}   # room_idx -> Button on the floor map
var current_detail := -1
var spawn_timer := 4.0

# Web-only: webcam "frame" gesture trigger for taking a photo (see
# scripts/gesture_input_web.gd). Null on native platforms.
var gesture_input: Node
var camera_label: Label

func _ready() -> void:
	monitor_screen.visible = false
	_build_feeds()
	_bind_monitors()
	_build_money_display()
	_build_film_display()
	_style_hud()
	_build_detail_view()
	_build_map()
	_build_banner()
	_build_overlay()
	_build_flash()
	_build_intro_overlay()
	intro_overlay.visible = true
	intro_overlay.modulate.a = 1.0
	_build_camera_indicator()
	_setup_gesture_input()

	GameManager.money_changed.connect(_on_money_changed)
	GameManager.night_changed.connect(_on_night_changed)
	GameManager.clock_changed.connect(_on_clock_changed)
	GameManager.photos_changed.connect(_on_photos_changed)
	GameManager.hour_changed.connect(_on_hour_changed)
	GameManager.game_over.connect(_on_game_over)

	GameManager.start_game()
	_update_clock_visual()

func _unhandled_input(event: InputEvent) -> void:
	if intro_sequence_running:
		return
	if detail_view != null and detail_view.visible:
		return

	if event is InputEventMouseMotion:
		var hovered_screen := _get_screen_at_point(event.position)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered_screen >= 0 else CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_screen := _get_screen_at_point(event.position)
		if clicked_screen >= 0:
			_open_detail(clicked_screen)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if intro_sequence_running or not GameManager.running:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = randf_range(4.0, 7.0)
		_spawn_ferret()

# --- construction -----------------------------------------------------------

func _build_feeds() -> void:
	var holder := Node.new()
	holder.name = "Feeds"
	add_child(holder)
	feeds.resize(ROOM_COUNT)
	rooms.resize(ROOM_COUNT)
	for i in ROOM_COUNT:
		var room_idx: int = SCREEN_TO_ROOM[i]
		# Wrap the editable Room scene in a SubViewport so it renders to a texture.
		var vp := SubViewport.new()
		vp.size = FEED_RENDER_SIZE
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.transparent_bg = false
		holder.add_child(vp)        # must be in tree before get_texture()

		var room := ROOM_SCENES[room_idx].instantiate() as Room
		room.room_id = room_idx + 1        # set before add_child so _ready() sees it
		room.scale = Vector2(
			FEED_RENDER_SIZE.x / ROOM_BASE_SIZE.x,
			FEED_RENDER_SIZE.y / ROOM_BASE_SIZE.y,
		)
		vp.add_child(room)

		feeds[i] = vp
		rooms[room_idx] = room

func _bind_monitors() -> void:
	for i in ROOM_COUNT:
		var screen := screen_layout.get_node_or_null("Screen%d" % i) as MonitorQuad
		if screen == null or i >= feeds.size():
			continue
		screen.set_feed_texture(feeds[i].get_texture())

func _style_hud() -> void:
	for l in [night_label, clock_label]:
		l.add_theme_font_size_override("font_size", 24)

func _build_money_display() -> void:
	money_sprites.clear()

	for child in money_display.get_children():
		if child is TextureRect:
			money_sprites.append(child)

func _build_film_display() -> void:
	film_sprites.clear()
	film_base_positions.clear()
	for child in film_row.get_children():
		if child is TextureRect:
			film_sprites.append(child)
			film_base_positions.append(child.position)
	_randomize_film_props()

func _randomize_film_props() -> void:
	for i in film_sprites.size():
		var film := film_sprites[i]
		var base_position := film_base_positions[i]
		film.position = base_position + Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
		)
		film.rotation_degrees = randf_range(-20.0, 20.0)

func _build_detail_view() -> void:
	detail_view = Control.new()
	detail_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_view.visible = false
	add_child(detail_view)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_view.add_child(dim)

	detail_texture = TextureRect.new()
	detail_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_texture.offset_left = 80
	detail_texture.offset_top = 70
	detail_texture.offset_right = -80
	detail_texture.offset_bottom = -110
	detail_view.add_child(detail_texture)

	detail_label = _make_label("CAM")
	detail_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	detail_label.offset_top = 24
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_view.add_child(detail_label)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -88
	bar.offset_bottom = -28
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 24)
	detail_view.add_child(bar)

	photo_btn = Button.new()
	photo_btn.text = "  Take Polaroid  "
	photo_btn.custom_minimum_size = Vector2(220, 48)
	photo_btn.pressed.connect(_take_photo)
	bar.add_child(photo_btn)

	var back_btn := Button.new()
	back_btn.text = "  Back to wall  "
	back_btn.custom_minimum_size = Vector2(180, 48)
	back_btn.pressed.connect(_close_detail)
	bar.add_child(back_btn)

func _build_map() -> void:
	# Floor map pinned to the bottom-right of the detail view. Each room is a
	# clickable cell that jumps the view to that camera (calls _open_detail), so
	# the player can hop between rooms without going back to the wall. Layout:
	#     [blank]   Entrance   [blank]
	#     Lounge    Bar        Poker
	#     [blank]   Roulette   Slot Machines
	# -1 marks a blank cell; numbers index ROOM_NAMES/ROOM_SCENES.
	var grid_order := [-1, 0, -1, 2, 1, 3, -1, 4, 5]
	var cell_size := Vector2(96, 50)

	map_panel = PanelContainer.new()
	map_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_panel.offset_right = -24
	map_panel.offset_bottom = -100   # sit above the Take Polaroid / Back button bar
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	sb.border_color = Color(0.45, 0.45, 0.55, 0.9)
	sb.set_border_width_all(2)
	map_panel.add_theme_stylebox_override("panel", sb)
	detail_view.add_child(map_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	map_panel.add_child(vb)

	var title := Label.new()
	title.text = "FLOOR MAP"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)

	for idx in grid_order:
		if idx == -1:
			var spacer := Control.new()
			spacer.custom_minimum_size = cell_size
			grid.add_child(spacer)
			continue
		var btn := Button.new()
		btn.text = ROOM_NAMES[idx]
		btn.custom_minimum_size = cell_size
		btn.add_theme_font_size_override("font_size", 12)
		btn.clip_text = true
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_open_detail.bind(_room_to_screen(idx)))
		grid.add_child(btn)
		map_buttons[idx] = btn

## Highlights the room currently shown full-screen and disables its map cell so
## it reads as "you are here" and can't re-trigger itself.
func _update_map_highlight() -> void:
	var current_room := _screen_to_room(current_detail) if current_detail >= 0 else -1
	for idx in map_buttons:
		var btn: Button = map_buttons[idx]
		if idx == current_room:
			btn.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
			btn.disabled = true
		else:
			btn.remove_theme_color_override("font_color")
			btn.disabled = false

func _build_banner() -> void:
	banner = _make_label("")
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 48)
	banner.visible = false
	add_child(banner)

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 24)
	overlay.add_child(vb)

	overlay_label = _make_label("")
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.add_theme_font_size_override("font_size", 52)
	vb.add_child(overlay_label)

	var restart := Button.new()
	restart.text = "  Play again  "
	restart.custom_minimum_size = Vector2(200, 52)
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	vb.add_child(restart)

func _build_flash() -> void:
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _build_intro_overlay() -> void:
	intro_overlay = Control.new()
	intro_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	intro_overlay.visible = false
	intro_overlay.modulate.a = 0.0
	add_child(intro_overlay)

	var dim := ColorRect.new()
	dim.color = Color.BLACK
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_overlay.add_child(dim)

	var day_center := CenterContainer.new()
	day_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_overlay.add_child(day_center)

	intro_day_card = Control.new()
	intro_day_card.custom_minimum_size = Vector2(1200, 520)
	day_center.add_child(intro_day_card)

	intro_day_label = Label.new()
	intro_day_label.layout_mode = 0
	intro_day_label.offset_left = 0.0
	intro_day_label.offset_top = 0.0
	intro_day_label.offset_right = 1200.0
	intro_day_label.offset_bottom = 280.0
	intro_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro_day_label.add_theme_font_override("font", CHUNKY_FONT)
	intro_day_label.add_theme_font_size_override("font_size", 293)
	intro_day_label.add_theme_color_override("font_color", Color.WHITE)
	intro_day_card.add_child(intro_day_label)

	var day_row := HBoxContainer.new()
	day_row.layout_mode = 0
	day_row.offset_left = 0.0
	day_row.offset_top = 255.0
	day_row.offset_right = 1200.0
	day_row.offset_bottom = 380.0
	day_row.alignment = BoxContainer.ALIGNMENT_CENTER
	day_row.add_theme_constant_override("separation", 18)
	intro_day_card.add_child(day_row)

	var intro_polaroid := TextureRect.new()
	intro_polaroid.custom_minimum_size = Vector2(138, 138)
	intro_polaroid.texture = POLAROID_TEXTURE
	intro_polaroid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	intro_polaroid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	day_row.add_child(intro_polaroid)

	var intro_film_row := HBoxContainer.new()
	intro_film_row.alignment = BoxContainer.ALIGNMENT_CENTER
	intro_film_row.add_theme_constant_override("separation", 6)
	day_row.add_child(intro_film_row)

	for i in GameManager.PHOTOS_PER_NIGHT:
		var intro_film := TextureRect.new()
		intro_film.custom_minimum_size = Vector2(46, 74)
		intro_film.texture = FILM_TEXTURE
		intro_film.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		intro_film.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		intro_film_row.add_child(intro_film)
		intro_day_films.append(intro_film)

	intro_instruction_card = CenterContainer.new()
	intro_instruction_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_instruction_card.visible = false
	intro_instruction_card.modulate.a = 0.0
	intro_overlay.add_child(intro_instruction_card)

	intro_instruction_label = Label.new()
	intro_instruction_label.custom_minimum_size = Vector2(1200, 260)
	intro_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_instruction_label.add_theme_font_override("font", MANROPE_FONT)
	intro_instruction_label.add_theme_font_size_override("font_size", 42)
	intro_instruction_label.add_theme_color_override("font_color", Color.WHITE)
	intro_instruction_label.text = "Stop all the raccoons from cheating at your casino\nby taking a picture of them on the polaroid."
	intro_instruction_card.add_child(intro_instruction_label)

func _build_camera_indicator() -> void:
	# Small top-right HUD readout of the webcam gesture detector (web only).
	camera_label = Label.new()
	camera_label.add_theme_font_size_override("font_size", 18)
	camera_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	camera_label.offset_left = -360
	camera_label.offset_right = -16
	camera_label.offset_top = 12
	camera_label.offset_bottom = 40
	camera_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	camera_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camera_label.visible = false  # shown only while a camera screen is open
	add_child(camera_label)

func _setup_gesture_input() -> void:
	if not OS.has_feature("web"):
		return
	gesture_input = preload("res://scripts/gesture_input_web.gd").new()
	add_child(gesture_input)
	# Same callback the "Take Polaroid" button uses; it self-guards when no room
	# is open, so a stray gesture on the monitor wall harmlessly does nothing.
	gesture_input.frame_gesture_detected.connect(_take_photo)
	gesture_input.frame_gesture_detected.connect(_flash_camera_indicator)
	gesture_input.camera_status_changed.connect(_on_camera_status_changed)

# --- gameplay ---------------------------------------------------------------

## Keeps the casino lively without completely locking movement by leaving a few
## seats open for hourly shuffling between rooms.
func _target_character_count() -> int:
	return maxi(18, _seat_capacity_total() - 4)

func _seat_capacity_total() -> int:
	var total := 0
	for room in rooms:
		total += room.players.size()
	return total

## Empties every room and rebuilds the roster, distributing patrons across the
## casino in seat-order rounds so larger rooms like Poker and Roulette don't
## look empty just because everyone starts at the Entrance.
func _reset_characters() -> void:
	characters.clear()
	var target_count := _target_character_count()
	for id in target_count:
		characters.append({"id": id, "room": -1, "seat": null})
	var next_character := 0
	var seat_round := 0
	while next_character < target_count:
		var placed_this_round := false
		for room_idx in ROOM_COUNT:
			if rooms[room_idx].players.size() <= seat_round:
				continue
			if _place_character(characters[next_character], room_idx):
				next_character += 1
				placed_this_round = true
				if next_character >= target_count:
					break
		if not placed_this_round:
			break
		seat_round += 1

func _place_character(ch: Dictionary, room_idx: int) -> bool:
	var seat := rooms[room_idx].free_seat()
	if seat == null:
		return false
	seat.occupy(ch.id)
	ch.room = room_idx
	ch.seat = seat
	return true

func _remove_character(ch: Dictionary) -> void:
	if ch.seat:
		ch.seat.vacate()
	ch.seat = null
	ch.room = -1

## Runs once per in-game hour: each seated character may step into a connected
## room that still has space, then queued characters fill any free Entrance
## seats. A cheating ferret keeps cheating in its new room (GameManager's
## active_ferrets reference is moved along with it).
func _on_hour_changed(_hour: int) -> void:
	if not GameManager.running:
		return

	var order := characters.duplicate()
	order.shuffle()
	for ch in order:
		if ch.room == -1:
			continue
		var options: Array[int] = []
		for next_room in ROOM_GRAPH[ch.room]:
			if rooms[next_room].free_seat_count() > 0:
				options.append(next_room)
		if options.is_empty():
			continue
		var target: int = options[randi() % options.size()]
		var old_seat: CasinoPlayer = ch.seat
		var was_ferret := old_seat.is_ferret
		_remove_character(ch)
		_place_character(ch, target)
		if was_ferret:
			ch.seat.set_ferret(true)
			GameManager.transfer_ferret(old_seat, ch.seat)

	for ch in characters:
		if ch.room == -1 and rooms[ENTRANCE_ROOM].free_seat_count() > 0:
			_place_character(ch, ENTRANCE_ROOM)

func _spawn_ferret() -> void:
	var order := range(ROOM_COUNT)
	order.shuffle()
	for idx in order:
		var room := rooms[idx]
		if room.get_active_ferret() != null:
			continue
		var victim := room.get_random_innocent()
		if victim:
			victim.set_ferret(true)
			GameManager.register_ferret(victim)
			return

func _open_detail(i: int) -> void:
	current_detail = i
	detail_texture.texture = feeds[i].get_texture()
	detail_label.text = "%s  —  look closely for a cheater" % ROOM_NAMES[_screen_to_room(i)]
	detail_view.visible = true
	monitor_screen.visible = false
	_update_map_highlight()
	# Turn on webcam gesture detection while this camera screen is open. The call
	# runs inside the click that opened the screen, so the browser allows the prompt.
	if gesture_input != null:
		camera_label.visible = true
		_on_camera_status_changed("starting")
		gesture_input.request_camera()

func _close_detail() -> void:
	detail_view.visible = false
	monitor_screen.visible = true
	mouse_default_cursor_shape = CURSOR_ARROW
	current_detail = -1
	# Stop detecting once the player is back on the monitor wall.
	if gesture_input != null:
		gesture_input.stop_camera()
		camera_label.visible = false

func _take_photo() -> void:
	if current_detail < 0:
		return
	if not GameManager.use_photo():      # out of film -> can't take a photo
		detail_label.text = "Out of film! No photos left tonight."
		return
	_play_flash()
	var ferret := rooms[_screen_to_room(current_detail)].get_active_ferret()
	if ferret:
		ferret.mark_caught()
		GameManager.catch_ferret(ferret)
		detail_label.text = "CHEATER CAUGHT!  +$%d" % int(GameManager.CATCH_BONUS)
	else:
		GameManager.false_accuse()
		detail_label.text = "No cheater here!  -$%d" % int(GameManager.FALSE_ACCUSE_PENALTY)

# --- signal handlers --------------------------------------------------------

func _on_money_changed(amount: float) -> void:
	var value := maxi(int(round(amount)), 0)
	var digits := "%06d" % value
	var money_chars := [
		MONEY_SYMBOL_TEXTURE,
		MONEY_DIGIT_TEXTURES[digits.substr(0, 1)],
		MONEY_DIGIT_TEXTURES[digits.substr(1, 1)],
		MONEY_DIGIT_TEXTURES[digits.substr(2, 1)],
		MONEY_DOT_TEXTURE,
		MONEY_DIGIT_TEXTURES[digits.substr(3, 1)],
		MONEY_DIGIT_TEXTURES[digits.substr(4, 1)],
		MONEY_DIGIT_TEXTURES[digits.substr(5, 1)],
	]
	for i in money_sprites.size():
		money_sprites[i].texture = money_chars[i]

func _on_night_changed(night: int) -> void:
	night_label.text = "Night %d / %d" % [night, GameManager.MAX_NIGHTS]
	for r in rooms:
		r.reset_players()
	_reset_characters()
	_close_detail()
	_randomize_film_props()
	GameManager.running = false
	await _play_night_intro(night)
	monitor_screen.visible = true
	GameManager.running = true

func _on_clock_changed(text: String) -> void:
	clock_label.text = text
	_update_clock_visual()

func _on_photos_changed(count: int) -> void:
	photos_label.text = "Photos: %d" % count
	if photo_btn:
		photo_btn.disabled = count <= 0
	for i in film_sprites.size():
		film_sprites[i].visible = i < count

func _on_camera_status_changed(status: String) -> void:
	if camera_label == null:
		return
	match status:
		"on":
			camera_label.text = "● Camera on — frame gesture = photo"
			camera_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
		"error":
			camera_label.text = "● Camera unavailable — use the button"
			camera_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
		_:  # "starting" / "off" (paused)
			camera_label.text = "● Camera starting…"
			camera_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))

func _flash_camera_indicator() -> void:
	if camera_label == null:
		return
	camera_label.modulate = Color(1.0, 1.0, 0.4)
	var t := create_tween()
	t.tween_property(camera_label, "modulate", Color(1, 1, 1), 0.4)

func _on_game_over(won: bool) -> void:
	overlay_label.text = "YOU SURVIVED!" if won else "GAME OVER"
	overlay_label.add_theme_color_override(
		"font_color", Color(0.6, 1, 0.6) if won else Color(1, 0.45, 0.45))
	overlay.visible = true

# --- helpers ----------------------------------------------------------------

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	return l

func _play_flash() -> void:
	flash.color.a = 0.9
	var t := create_tween()
	t.tween_property(flash, "color:a", 0.0, 0.35)

func _show_banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 1.0
	banner.visible = true
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(banner, "modulate:a", 0.0, 0.6)
	t.tween_callback(func(): banner.visible = false)

func _play_night_intro(night: int) -> void:
	intro_sequence_running = true
	intro_overlay.visible = true
	intro_day_card.visible = true
	intro_day_card.modulate.a = 0.0
	intro_instruction_card.visible = false
	intro_instruction_card.modulate.a = 0.0
	intro_day_label.text = "Day %d" % night
	for i in intro_day_films.size():
		intro_day_films[i].visible = i < GameManager.PHOTOS_PER_NIGHT

	intro_overlay.modulate.a = 1.0
	var fade_in_day := create_tween()
	fade_in_day.tween_property(intro_day_card, "modulate:a", 1.0, 1.0)
	await fade_in_day.finished
	await get_tree().create_timer(2.8).timeout

	if not has_shown_first_time_instructions:
		has_shown_first_time_instructions = true
		intro_instruction_card.visible = true
		var fade_day := create_tween()
		fade_day.tween_property(intro_day_card, "modulate:a", 0.0, 1.5)
		await fade_day.finished
		intro_day_card.visible = false
		await get_tree().create_timer(0.35).timeout
		var fade_in_instructions := create_tween()
		fade_in_instructions.tween_property(intro_instruction_card, "modulate:a", 1.0, 1.5)
		await fade_in_instructions.finished
		await get_tree().create_timer(4.8).timeout
	else:
		await get_tree().create_timer(0.9).timeout

	var fade_out := create_tween()
	fade_out.tween_property(intro_overlay, "modulate:a", 0.0, 1.6)
	await fade_out.finished
	intro_overlay.visible = false
	intro_instruction_card.visible = false
	intro_day_card.visible = true
	intro_day_card.modulate.a = 1.0
	intro_sequence_running = false

func _get_screen_at_point(point: Vector2) -> int:
	for i in range(ROOM_COUNT - 1, -1, -1):
		var screen := screen_layout.get_node_or_null("Screen%d" % i) as MonitorQuad
		if screen != null and screen.contains_global_point(point):
			return i
	return -1

func _screen_to_room(screen_idx: int) -> int:
	if screen_idx < 0 or screen_idx >= SCREEN_TO_ROOM.size():
		return 0
	return SCREEN_TO_ROOM[screen_idx]

func _room_to_screen(room_idx: int) -> int:
	return SCREEN_TO_ROOM.find(room_idx)

func _update_clock_visual() -> void:
	var elapsed_hours := (GameManager.NIGHT_DURATION - GameManager.night_time_left) / GameManager.SECONDS_PER_HOUR
	var hour_rotation_deg := -90.0 + (elapsed_hours * 30.0)
	var minute_rotation_deg := fmod(elapsed_hours * 360.0, 360.0)
	clock_hour_hand.rotation_degrees = hour_rotation_deg
	clock_minute_hand.rotation_degrees = minute_rotation_deg
