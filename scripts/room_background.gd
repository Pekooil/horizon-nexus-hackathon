@tool
extends Node2D
class_name RoomBackground
## Placeholder casino-room art drawn in code, filling the 480x270 feed area.
## @tool so it also renders while you edit RoomFeed.tscn in the editor.
## Delete this node and drop in your own Sprite2D/TextureRect when you have art.

var room_id := 0

func _draw() -> void:
	# wall
	draw_rect(Rect2(0, 0, 480, 270), Color(0.10, 0.09, 0.13))
	# floor strip
	draw_rect(Rect2(0, 212, 480, 58), Color(0.17, 0.13, 0.10))
	# green felt table
	draw_rect(Rect2(56, 150, 368, 78), Color(0.07, 0.34, 0.18))
	draw_rect(Rect2(56, 150, 368, 78), Color(0.30, 0.22, 0.10), false, 4.0)

	# security-feed label, top-left
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12, 26), "CAM %d" % room_id,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.95, 0.6))
	# little "REC" dot, top-right
	draw_circle(Vector2(452, 20), 6, Color(0.9, 0.2, 0.2))
