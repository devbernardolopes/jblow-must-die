@tool
class_name WorldObject
extends CharacterBody2D

@export var data: WorldObjectData = null:
	set(v):
		data = v
		_ensure_visual()

var collision: CollisionShape2D = null
var collision_polygon: CollisionPolygon2D = null

func _ready() -> void:
	collision_layer = PhysicsLayers.OBJECTS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ENTITIES | PhysicsLayers.OBJECTS | PhysicsLayers.PROJECTILES
	collision = _find_collision()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_ensure_visual()
	if collision_polygon:
		#collision_polygon.polygon.get
		pass

	if collision:
		(collision.shape as RectangleShape2D).get_rect()
		#(collision.shape as RectangleShape2D).poly
		
		##(collision.shape as RectangleShape2D).get_rect()
		##(collision.shape as CircleShape2D).radius
		#pass

#func _process(delta: float) -> void:
	#pass

func _find_collision() -> CollisionShape2D:
	for child: Node in get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null

func _ensure_visual() -> void:
	if data and data.visual:
		var _sprite_2d: Sprite2D = Sprite2D.new()
		_sprite_2d.texture = data.visual
		add_child(_sprite_2d)
	#visual.scale = Vector2.ONE * frame_scale_multiplier

#func _configure_collision_shape() -> void:
	#if collision == null:
		#collision = CollisionShape2D.new()
		#add_child(collision)
#
	#var circle := collision.shape as CircleShape2D
	#if circle == null:
		#circle = CircleShape2D.new()
		#collision.shape = circle
	#circle.radius = Units.m_to_px(COLLISION_RADIUS_M)
	#collision.position = Vector2.ONE * collision_offset
	#collision.debug_color = Color.from_hsv(0.4, 0.9, 0.3, 0.5)
