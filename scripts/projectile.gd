class_name Projectile
extends CharacterBody2D
## Data-driven projectile. Walls are handled by the body shape, entities by the
## Hitbox area, so piercing shots never physically stop on a body.

const SCENE_PATH: String = "res://scenes/projectile.tscn"

var data: ProjectileData
var shooter: Node2D
var team: StringName = &""
var damage: float = 0.0

var _life: float
var _bounces_left: int
var _pierce_left: int
var _hit: Array[Node] = []
var _dead: bool = false

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var wall_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hit_shape: CollisionShape2D = $Hitbox/CollisionShape2D

static func spawn(
	p_data: ProjectileData,
	pos: Vector2,
	dir: Vector2,
	p_shooter: Node2D,
	p_damage: float = -1.0
) -> Projectile:
	if p_data == null or p_shooter == null or not p_shooter.is_inside_tree():
		return null
	var tree: SceneTree = p_shooter.get_tree()
	if tree == null:
		return null
	var root: Node = tree.get_first_node_in_group(&"projectiles_root")
	if root == null:
		root = tree.current_scene
	if root == null:
		return null

	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var projectile := scene.instantiate() as Projectile
	if projectile == null:
		return null
	projectile.data = p_data
	projectile.shooter = p_shooter
	var shooter_team: Variant = p_shooter.get(&"team")
	projectile.team = shooter_team if shooter_team is StringName else &""
	projectile.damage = p_damage if p_damage >= 0.0 else p_data.damage
	# Dedicated container so projectiles don't move with the entity that fired them.
	root.add_child(projectile)
	projectile.global_position = pos
	projectile.velocity = dir.normalized() * p_data.speed
	projectile._orient()
	return projectile

func _ready() -> void:
	if data == null:
		queue_free()
		return
	_life = data.lifetime
	_bounces_left = data.max_bounces
	_pierce_left = data.pierce

	_configure_shape(wall_shape)
	_configure_shape(hit_shape)
	_configure_sprite()
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_life -= delta
	if _life <= 0.0:
		_die()
		return

	var collision: KinematicCollision2D = move_and_collide(velocity * delta)
	if collision == null:
		return

	if _bounces_left > 0:
		_bounces_left -= 1
		var normal: Vector2 = collision.get_normal()
		velocity = velocity.bounce(normal)
		_orient()
		move_and_collide(collision.get_remainder().bounce(normal))
	else:
		_die()

func _draw() -> void:
	if data == null or not data.sprite_frames.is_empty():
		return
	draw_circle(Vector2.ZERO, maxf(data.radius, 1.0), data.placeholder_color)

func _configure_shape(shape_node: CollisionShape2D) -> void:
	var circle := shape_node.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		shape_node.shape = circle
	circle.radius = maxf(data.radius, 1.0)
	shape_node.debug_color = Color(1.0, 0.0, 0.0)

func _configure_sprite() -> void:
	if data.sprite_frames.is_empty():
		sprite.visible = false
		return
	var frames: SpriteFrames = data.sprite_frames.pick_random()
	if frames == null or frames.get_animation_names().is_empty():
		sprite.visible = false
		return
	sprite.visible = true
	sprite.sprite_frames = frames
	var animation: StringName = data.animation
	if not frames.has_animation(animation):
		animation = StringName(frames.get_animation_names()[0])
	sprite.scale = Vector2.ONE * data.scale_adjustment
	sprite.play(animation)

func _on_hitbox_body_entered(body: Node2D) -> void:
	if _dead or body == null or body == shooter or body in _hit:
		return
	if team != &"" and body.get(&"team") == team:
		return

	_hit.append(body)
	if damage > 0.0 and body.has_method(&"take_damage"):
		var source: Node = shooter if shooter != null and is_instance_valid(shooter) else self
		body.take_damage(damage, source)

	if _pierce_left < 0:
		return
	if _pierce_left > 0:
		_pierce_left -= 1
	else:
		_die()

func _orient() -> void:
	if data != null and data.rotate_to_direction:
		sprite.rotation = velocity.angle()

func _die() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	wall_shape.set_deferred(&"disabled", true)
	hit_shape.set_deferred(&"disabled", true)
	hitbox.set_deferred(&"monitoring", false)

	var impact: StringName = data.impact_animation if data != null else &""
	if not sprite.visible or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(impact):
		queue_free()
		return

	sprite.play(impact)
	sprite.top_level = true
	var duration: float = _animation_duration(impact)
	if duration <= 0.0:
		queue_free()
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		queue_free()
		return
	tree.create_timer(duration).timeout.connect(queue_free)

func _animation_duration(animation: StringName) -> float:
	var frames: SpriteFrames = sprite.sprite_frames
	var total: float = 0.0
	for index: int in range(frames.get_frame_count(animation)):
		total += frames.get_frame_duration(animation, index)
	var speed: float = frames.get_animation_speed(animation) * sprite.speed_scale
	if speed <= 0.0:
		speed = 1.0
	return total / speed
