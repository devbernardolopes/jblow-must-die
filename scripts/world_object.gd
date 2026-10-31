@tool
class_name WorldObject
extends CharacterBody2D
## Base for authored world objects (crates, barrels, rocks...).
##
## The scene only needs a CollisionShape2D (or CollisionPolygon2D) child. Its
## shape is also the footprint of the fake height effect, so the side faces
## stand on exactly what the object collides with.

@export var data: WorldObjectData = null:
	set(value):
		if data != null and data.changed.is_connected(_on_data_changed):
			data.changed.disconnect(_on_data_changed)
		data = value
		if data != null:
			data.changed.connect(_on_data_changed)
		_ensure_visual()

@export_group("Editor preview")
## Editor only: where the "eye" is when the edited scene has no node in the
## "door_viewer" group. Ignored in game.
@export var preview_viewer_position: Vector2 = Vector2.ZERO:
	set(value):
		preview_viewer_position = value
		if _illusion != null:
			_illusion.preview_viewer_position = value

var collision: CollisionShape2D = null
var collision_polygon: CollisionPolygon2D = null

var _illusion: HeightIllusion = null


func _ready() -> void:
	collision_layer = PhysicsLayers.OBJECTS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ENTITIES | PhysicsLayers.OBJECTS | PhysicsLayers.PROJECTILES
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_ensure_visual()
	_refresh_footprint()
	# In the editor the collision shape can be edited at any moment, so follow it.
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_refresh_footprint()


func _on_data_changed() -> void:
	_ensure_visual()


func _find_collision() -> CollisionShape2D:
	for child: Node in get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null


func _find_collision_polygon() -> CollisionPolygon2D:
	for child: Node in get_children():
		if child is CollisionPolygon2D:
			return child as CollisionPolygon2D
	return null


func _find_existing_illusion() -> HeightIllusion:
	for child: Node in get_children(true):
		if child is HeightIllusion:
			return child as HeightIllusion
	return null


## Creates the visual once and only updates it afterwards.
func _ensure_visual() -> void:
	if _illusion == null:
		_illusion = _find_existing_illusion()  # survives a script reload
	if _illusion == null:
		_illusion = HeightIllusion.new()
		_illusion.name = "Visual"
		add_child(_illusion, false, Node.INTERNAL_MODE_FRONT)
		var top_sprite := Sprite2D.new()
		top_sprite.name = "Top"
		_illusion.add_child(top_sprite)
		_illusion.top = top_sprite

	var sprite := _illusion.top as Sprite2D
	if sprite != null:
		sprite.texture = data.visual if data != null else null
		sprite.visible = sprite.texture != null

	_illusion.preview_viewer_position = preview_viewer_position
	if data != null:
		_illusion.side_texture = data.side_texture
		_illusion.side_tint = data.side_tint
		_illusion.side_mapping = data.side_mapping
		_illusion.pixel_art = data.pixel_art
		_illusion.height_factor = data.height_factor
	else:
		_illusion.height_factor = 0.0
	_illusion.refresh()


## Footprint = collision shape. Re-found every time so a shape added or removed
## in the editor is picked up; in game this runs once.
func _refresh_footprint() -> void:
	if _illusion == null:
		return
	collision = _find_collision()
	collision_polygon = _find_collision_polygon()
	var points := PackedVector2Array()
	if collision != null and collision.shape != null:
		points = HeightIllusion.footprint_from_shape(collision.shape, collision.transform)
	elif collision_polygon != null:
		points = HeightIllusion.footprint_from_polygon(
			collision_polygon.polygon, collision_polygon.transform
		)
	if points != _illusion.get_footprint():
		_illusion.set_footprint(points)
