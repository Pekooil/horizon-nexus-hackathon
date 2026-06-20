extends Control
## Root scene. Builds the 6 live camera feeds, the monitor wall, the click-to-zoom
## detail view with the Polaroid catch mechanic, the HUD, and win/lose overlay.

const ROOM_COUNT := 6
const FEED_RENDER_SIZE := Vector2i(960, 540)
const ROOM_SCENE := preload("res://scenes/Room.tscn")

# Monitor-wall nodes that live in Main.tscn (edit them in the editor):
@onready var monitor_screen: Control = $MonitorScreen
@onready var screen_layout: Node2D = $MonitorScreen/WallCenter/ScreenLayout
@onready var money_label: Label = $MonitorScreen/TopBar/Money
@onready var night_label: Label = $MonitorScreen/TopBar/Night
@onready var clock_label: Label = $MonitorScreen/TopBar/Clock

var feeds: Array[SubViewport] = []   # the off-screen render targets (textures)
var rooms: Array[Room] = []          # the editable room contents (game logic)

# Popups still built in code (modal UI, not part of the main screen):
var detail_view: Control
var detail_texture: TextureRect
var detail_label: Label
var banner: Label
var flash: ColorRect
var overlay: Control
var overlay_label: Label

var current_detail := -1
var spawn_timer := 4.0

func _ready() -> void:
	_build_feeds()
	_bind_monitors()
	_style_hud()
	_build_detail_view()
	_build_banner()
	_build_overlay()
	_build_flash()

	GameManager.money_changed.connect(_on_money_changed)
	GameManager.night_changed.connect(_on_night_changed)
	GameManager.clock_changed.connect(_on_clock_changed)
	GameManager.game_over.connect(_on_game_over)

	GameManager.start_game()

func _process(delta: float) -> void:
	if not GameManager.running:
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
	for i in ROOM_COUNT:
		# Wrap the editable Room scene in a SubViewport so it renders to a texture.
		var vp := SubViewport.new()
		vp.size = FEED_RENDER_SIZE
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.transparent_bg = false
		holder.add_child(vp)        # must be in tree before get_texture()

		var room := ROOM_SCENE.instantiate() as Room
		room.room_id = i + 1        # set before add_child so _ready() sees it
		vp.add_child(room)

		feeds.append(vp)
		rooms.append(room)

func _bind_monitors() -> void:
	# Each screen is an editable 4-point Polygon2D with a matching click hitbox.
	var feed_uvs := PackedVector2Array([
		Vector2(0, 0),
		Vector2(FEED_RENDER_SIZE.x, 0),
		Vector2(FEED_RENDER_SIZE.x, FEED_RENDER_SIZE.y),
		Vector2(0, FEED_RENDER_SIZE.y),
	])
	for i in ROOM_COUNT:
		var screen := screen_layout.get_node_or_null("Screen%d" % i) as Node2D
		if screen == null or i >= feeds.size():
			continue
		var surface := screen.get_node("Surface") as Polygon2D
		var hitbox := screen.get_node("Hitbox") as Area2D
		var collision := hitbox.get_node("CollisionPolygon2D") as CollisionPolygon2D
		if surface == null or hitbox == null or collision == null:
			continue

		surface.texture = feeds[i].get_texture()
		surface.uv = feed_uvs
		collision.polygon = surface.polygon
		hitbox.input_pickable = true
		if not hitbox.input_event.is_connected(_on_screen_hit):
			hitbox.input_event.connect(_on_screen_hit.bind(i))

func _on_screen_hit(_viewport: Node, event: InputEvent, _shape_idx: int, screen_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_detail(screen_idx)

func _style_hud() -> void:
	for l in [money_label, night_label, clock_label]:
		l.add_theme_font_size_override("font_size", 24)

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

	var photo_btn := Button.new()
	photo_btn.text = "  Take Polaroid  "
	photo_btn.custom_minimum_size = Vector2(220, 48)
	photo_btn.pressed.connect(_take_photo)
	bar.add_child(photo_btn)

	var back_btn := Button.new()
	back_btn.text = "  Back to wall  "
	back_btn.custom_minimum_size = Vector2(180, 48)
	back_btn.pressed.connect(_close_detail)
	bar.add_child(back_btn)

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

# --- gameplay ---------------------------------------------------------------

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
	detail_label.text = "CAM %d  —  look closely for a cheater" % (i + 1)
	detail_view.visible = true
	monitor_screen.visible = false

func _close_detail() -> void:
	detail_view.visible = false
	monitor_screen.visible = true
	current_detail = -1

func _take_photo() -> void:
	_play_flash()
	if current_detail < 0:
		return
	var ferret := rooms[current_detail].get_active_ferret()
	if ferret:
		ferret.mark_caught()
		GameManager.catch_ferret(ferret)
		detail_label.text = "CHEATER CAUGHT!  +$%d" % int(GameManager.CATCH_BONUS)
	else:
		GameManager.false_accuse()
		detail_label.text = "No cheater here!  -$%d" % int(GameManager.FALSE_ACCUSE_PENALTY)

# --- signal handlers --------------------------------------------------------

func _on_money_changed(amount: float) -> void:
	money_label.text = "$%d" % int(amount)
	money_label.add_theme_color_override(
		"font_color", Color(1, 0.4, 0.4) if amount < 250 else Color(0.7, 1, 0.7))

func _on_night_changed(night: int) -> void:
	night_label.text = "Night %d / %d" % [night, GameManager.MAX_NIGHTS]
	for r in rooms:
		r.reset_players()
	_close_detail()
	_show_banner("NIGHT %d" % night)

func _on_clock_changed(text: String) -> void:
	clock_label.text = text

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
