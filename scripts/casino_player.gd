extends Node2D
class_name CasinoPlayer
## A casino patron. This script only toggles node visibility; the actual art lives
## in CasinoPlayer.tscn as Sprite2D nodes you can swap textures on and move around:
##   Body  - the patron sprite
##   Tell  - the ferret giveaway (ears/tail/etc.), shown only while cheating
##   Caught - the "busted" marker, shown after being photographed

const DEFAULT_GOOD_HEAD := preload("res://assets/ferret-head.png")
const DEFAULT_BAD_HEAD := preload("res://assets/raccoon-head.png")
const DEFAULT_CAUGHT_HEAD := preload("res://assets/raccoon-caught.png")

@export var good_head_texture: Texture2D = DEFAULT_GOOD_HEAD
@export var bad_head_texture: Texture2D = DEFAULT_BAD_HEAD
@export var head_size := Vector2(44.0, 34.0)
@export var caught_texture: Texture2D = DEFAULT_CAUGHT_HEAD
@export var caught_size := Vector2(44.0, 34.0)

@onready var body: Sprite2D = $Body
@onready var tell: Node2D = $Tell
@onready var caught_mark: Sprite2D = $Caught

var occupied := false
var character_id := -1
var is_ferret := false
var caught := false

func _ready() -> void:
	_refresh()

## Seats use this as an occupancy slot, since the same room scene now hosts a
## roving roster of characters rather than 3 permanently-assigned patrons.
func occupy(id: int) -> void:
	occupied = true
	character_id = id
	is_ferret = false
	caught = false
	_refresh()

func vacate() -> void:
	occupied = false
	character_id = -1
	is_ferret = false
	caught = false
	_refresh()

func set_ferret(on: bool) -> void:
	is_ferret = on
	caught = false
	_refresh()

func mark_caught() -> void:
	caught = true
	is_ferret = false      # frees the seat to be recruited again later
	_refresh()

func reset() -> void:
	is_ferret = false
	caught = false
	_refresh()

func _refresh() -> void:
	visible = occupied
	if body:
		body.visible = not caught
		if not caught:
			body.texture = bad_head_texture if is_ferret else good_head_texture
			body.scale = Vector2(
				head_size.x / body.texture.get_width(),
				head_size.y / body.texture.get_height(),
			)
	if tell:
		tell.visible = false
	if caught_mark:
		caught_mark.visible = caught
		if caught:
			caught_mark.texture = caught_texture
			caught_mark.self_modulate = Color(1.0, 0.45, 0.45, 1.0)
			caught_mark.scale = Vector2(
				caught_size.x / caught_mark.texture.get_width(),
				caught_size.y / caught_mark.texture.get_height(),
			)
