extends Node2D
class_name Room
## The editable contents of one casino room: background + seated patrons.
## Root is a plain Node2D so it edits normally in the 2D canvas (open Room.tscn,
## drag the seats around, drop textures onto the sprites). At runtime main.gd
## drops this scene inside a SubViewport to turn it into a live camera feed.

@export var room_id := 1

var players: Array[CasinoPlayer] = []

func _ready() -> void:
	for c in $Seats.get_children():
		if c is CasinoPlayer:
			players.append(c)
	var bg := get_node_or_null("RoomBackground")
	if bg:
		bg.room_id = room_id
		bg.queue_redraw()

## Returns a currently-cheating patron in this room, or null.
func get_active_ferret() -> CasinoPlayer:
	for p in players:
		if p.is_ferret and not p.caught:
			return p
	return null

## Returns a random honest patron to recruit as a ferret, or null if none.
func get_random_innocent() -> CasinoPlayer:
	var pool: Array[CasinoPlayer] = []
	for p in players:
		if not p.is_ferret:
			pool.append(p)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

func reset_players() -> void:
	for p in players:
		p.reset()
