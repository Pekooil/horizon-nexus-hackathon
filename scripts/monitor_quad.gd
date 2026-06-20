@tool
extends Node2D
class_name MonitorQuad

signal pressed

@onready var guide: Polygon2D = $Guide
@onready var surface: MeshInstance2D = $Surface
@onready var hitbox: Area2D = $Hitbox
@onready var collision: CollisionPolygon2D = $Hitbox/CollisionPolygon2D

var _last_polygon := PackedVector2Array()

func _ready() -> void:
	hitbox.input_pickable = true
	if not hitbox.input_event.is_connected(_on_hitbox_input):
		hitbox.input_event.connect(_on_hitbox_input)
	_sync_geometry()
	set_process(true)

func _process(_delta: float) -> void:
	if guide.polygon != _last_polygon:
		_sync_geometry()

func set_feed_texture(texture: Texture2D) -> void:
	surface.texture = texture

func get_polygon_points() -> PackedVector2Array:
	return guide.polygon

func contains_global_point(global_point: Vector2) -> bool:
	var local_point := to_local(global_point)
	return Geometry2D.is_point_in_polygon(local_point, guide.polygon)

func _sync_geometry() -> void:
	var points := guide.polygon
	if points.size() < 4:
		return

	_last_polygon = points
	collision.polygon = points
	surface.mesh = _build_mesh(points)
	guide.visible = Engine.is_editor_hint()

func _build_mesh(points: PackedVector2Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(points[0].x, points[0].y, 0.0),
		Vector3(points[1].x, points[1].y, 0.0),
		Vector3(points[2].x, points[2].y, 0.0),
		Vector3(points[3].x, points[3].y, 0.0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _on_hitbox_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
