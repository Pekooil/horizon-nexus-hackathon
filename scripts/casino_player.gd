extends Node2D
class_name CasinoPlayer
## A casino patron. This script only toggles node visibility; the actual art lives
## in CasinoPlayer.tscn as Sprite2D nodes you can swap textures on and move around:
##   Body  - the patron sprite
##   Tell  - the ferret giveaway (ears/tail/etc.), shown only while cheating
##   Caught - the "busted" marker, shown after being photographed

@onready var tell: Node2D = $Tell
@onready var caught_mark: Node2D = $Caught

var is_ferret := false
var caught := false

func _ready() -> void:
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
	if tell:
		tell.visible = is_ferret and not caught
	if caught_mark:
		caught_mark.visible = caught
