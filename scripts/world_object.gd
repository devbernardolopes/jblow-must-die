@tool
class_name WorldObject
extends CharacterBody2D
## Base for authored world objects (crates, barrels, rocks...).
##
## The scene only needs a CollisionShape2D (or CollisionPolygon2D) child. Its
## shape is also the footprint of the fake height effect, so the side faces
## stand on exactly what the object collides with.
@onready var label: Label = $Label

@export var data: WorldObjectData = null:
	set(value):
		if data != null and data.changed.is_connected(_on_data_changed):
			data.changed.disconnect(_on_data_changed)
		data = value
		if data != null:
			data.changed.connect(_on_data_changed)
		_ensure_visual()

@export var use_glass_crack_effect: bool = false:
	set(v):
		use_glass_crack_effect = v
		_toggle_glass_crack_effect(v)

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

var dead: bool = false

var health: float = 0.00:
	set(v):
		health = v
		if label:
			label.text = "%f.2" % [v]

signal damaged(amount: float, source: Node)
signal died(source: Node)

var color_rect: ColorRectImpactGlass = null
var hit_flash_effect: ColorRect = null

func get_color_rect() -> ColorRectImpactGlass:
	var _children = get_children()
	if _children and not _children.is_empty():
		for i in _children.size():
			var _child = _children[i]
			if _child is ColorRectImpactGlass:
				return _child
	return null

func remove_color_rect() -> void:
	var _children = get_children()
	if _children and not _children.is_empty():
		for i in _children.size():
			var _child = _children[i]
			if _child is ColorRectImpactGlass:
				remove_child(_child)

func _toggle_glass_crack_effect(_toggle: bool) -> void:
	var _color_rect = get_color_rect()
	
	if _toggle:
		color_rect = ColorRectImpactGlass.new()
		if not _color_rect:
			add_child(color_rect)
		var _size: Vector2 = Vector2.ONE
		
		if collision and collision.shape:
			if collision.shape.is_class("RectangleShape2D"):
				_size = (collision.shape as RectangleShape2D).size
	
		color_rect.set_size(_size * scale)
		#print(_size)
		color_rect.set_position((color_rect.size / 2) * -1.0)
		color_rect.color = Color.RED
	else:
		remove_color_rect()

func apply_crack(_point: Vector2 = Vector2.ZERO) -> void:
	if use_glass_crack_effect:
		if color_rect:
			color_rect.trigger_crack(_point)

func _ready() -> void:
	#collision_layer = PhysicsLayers.OBJECTS
	#collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ENTITIES | PhysicsLayers.OBJECTS | PhysicsLayers.PROJECTILES
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	
	_ensure_visual()
	_refresh_footprint()
	_toggle_glass_crack_effect(use_glass_crack_effect)
	
	#if not hit_flash_effect:
		#var _size: Vector2 = Vector2.ONE
		#hit_flash_effect = ColorRect.new()
		#
		#if collision and collision.shape:
			#if collision.shape.is_class("RectangleShape2D"):
				#_size = (collision.shape as RectangleShape2D).size
	#
		#hit_flash_effect.set_size(_size * scale)
		#hit_flash_effect.set_position((hit_flash_effect.size / 2) * -1.0)
		#add_child(hit_flash_effect)

	# In the editor the collision shape can be edited at any moment, so follow it.
	set_process(Engine.is_editor_hint())

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		if data != null:
			if data.breakable:
				health = data.health

func _process(_delta: float) -> void:
	if not collision or not collision_polygon:
		_refresh_footprint()

## Applies damage, emits `damaged`, and dies when health reaches zero.
func take_damage(amount: float, source: Node) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if use_glass_crack_effect:
		apply_crack(ShapeUtils.random_point_in(collision) * scale)
	damaged.emit(amount, source)
	if health <= 0.0:
		_die(source)

func _die(source: Node) -> void:
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
	#if animator != null:
		#animator.cancel_action()
	died.emit(source)
	queue_free()

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
		#if not sprite.material:
			#sprite.material = ShaderMaterial.new()
			#sprite.material.shader = load("res://shaders/fading_color_override.gdshader")
			#sprite.material.set_shader_parameter("active", true)
			#var tween = create_tween()
			#tween.set_loops()

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
	#if not Engine.is_editor_hint():
	#if not Engine.is_editor_hint():
		if _illusion == null:
			return
		collision = _find_collision()
		collision_polygon = _find_collision_polygon()
		var points := PackedVector2Array()
		if collision != null and collision.shape != null:
			#print("collision.shape.get_rect() = %f" % collision.shape.get_rect().get_area())
			points = HeightIllusion.footprint_from_shape(collision.shape, collision.transform)
		elif collision_polygon != null:
			#print("collision_polygon.shape.get_rect() = %f" % collision_polygon.shape.get_rect().get_area())
			points = HeightIllusion.footprint_from_polygon(collision_polygon.polygon, collision_polygon.transform)
		if points != _illusion.get_footprint():
			_illusion.set_footprint(points)
